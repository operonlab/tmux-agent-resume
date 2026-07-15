#!/usr/bin/env bash
# snapshot.sh — tmux-resurrect post-save-all hook. Records, per pane, which AI
# CLI agent is running, its current session id, and the exact command that will
# resume it. restore.sh replays that after a restart. Battle-tested across 8
# CLIs on macOS, 2026-07 (see docs/per-cli-matrix.md for the reverse-lookup
# method, resume command, cwd binding, and known limits of each CLI).
#
# session id source, per tool (priority order):
#   claude : $MAP_DIR/<pane_id> (written by the SessionStart hook = the CURRENT
#            session, exact) > argv verbatim. Map epoch must be >= the agent
#            process start time or it is a stale entry from an old server that
#            recycled the same pane id -> fall back to argv.
#   codex  : lsof the open rollout-*-<uuid>.jsonl -> `codex resume <uuid>`
#   agy    : lsof the held brain/<uuid> dir       -> `agy --conversation <uuid>`
#   copilot: log filename embeds the pid; last "Workspace initialized" id
#            -> `copilot --resume=<uuid>`
#   opencode: argv already has -s ses_xxx -> replay; else, single-instance only,
#            newest session.id from the shared log
#   kimi   : renames itself to kimi-code (argv unusable); session_index.jsonl
#            filtered by workDir==cwd, newest state.json -> `kimi -r <sid>`
#   hermes : python wrapper; argv --resume replays; else id timestamp ~ process
#            start time, reverse-looked-up from agent.log
#   qwen   : node; official runtime sidecar <sid>.runtime.json {pid,session_id,
#            work_dir} -> `qwen --resume <sid>`
#   gemini : discontinued 2026-06-18, removed.
#
# cwd binding (restore prepends `cd`): claude/kimi/qwen hard-bind their session
# to a directory; codex/agy/copilot/opencode/hermes do not.
#
# Output TSV:  coord \t tool \t mode \t cwd \t resume_cmd  (last field may hold spaces)
#
# Hook script rules: never `set -e`; emit nothing important to stdout; exit 0.
set -uo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$CURRENT_DIR/common.sh"

CACHE="$(ar_cache_dir || true)"
: "${CACHE:=${TMUX_TMPDIR:-/tmp}}"

SNAP_FILE="$(ar_opt AGENT_RESUME_SNAP_FILE @agent-resume-snapshot-file "$HOME/.tmux/resurrect/agents.tsv")"
MAP_DIR="$(ar_opt AGENT_RESUME_MAP_DIR   @agent-resume-map-dir       "$CACHE/claude-map")"
LOG="$(ar_opt      AGENT_RESUME_LOG       @agent-resume-log           "$CACHE/agent-resume.log")"
TOOLS="$(ar_opt    AGENT_RESUME_TOOLS     @agent-resume-tools         'claude codex agy copilot opencode kimi hermes qwen')"

slog() { printf '[%s] [snapshot] %s\n' "$(date +'%H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true; }

# process start epoch (etime); claude stale-map guard and hermes timestamp share it
_proc_start_epoch() {
    ps -o etime= -p "$1" 2>/dev/null | awk -v now="$(date +%s)" '{
        n=split($1,a,"-"); d=0; t=a[n]
        if (n==2) d=a[1]
        m=split(t,b,":")
        s=(m==3)? b[1]*3600+b[2]*60+b[3] : b[1]*60+b[2]
        print now - (d*86400 + s) }'
}

# strip session/conversation flags from argv (they are replaced by the detected
# current id). $1=argv  $2=value flags (space sep)  $3=boolean flags (space sep)
_strip_session_flags() {
    local argvstr="$1" vflags="$2" bflags="${3:-}"
    # shellcheck disable=SC2086
    set -- $argvstr
    local out="" skip=0 a f hit
    for a in "$@"; do
        if [ "$skip" = "1" ]; then
            skip=0
            case "$a" in -*) ;; *) continue ;; esac
        fi
        hit=0
        for f in $vflags; do
            case "$a" in
                "$f") skip=1; hit=1; break ;;
                "$f"=*) hit=1; break ;;
            esac
        done
        if [ "$hit" = "0" ]; then
            for f in $bflags; do
                case "$a" in "$f") hit=1; break ;; esac
            done
        fi
        [ "$hit" = "1" ] && continue
        out="$out $a"
    done
    printf '%s' "${out# }"
}

tmpfile=$(mktemp) || exit 0
count=0

# one ps snapshot: tty + argv (avoid scanning once per pane)
psfile=$(mktemp) || { rm -f "$tmpfile"; exit 0; }
ps -axo pid=,tty=,command= > "$psfile" 2>/dev/null || true

while IFS=$'\t' read -r coord paneid ppid ptty ppath; do
    ttybase=${ptty##*/}
    [ -n "$ttybase" ] || continue
    # known agent process on the pane tty that is not the pane shell (earliest pid).
    # process name is not trustworthy: kimi renames to kimi-code, hermes is
    # python3, qwen is node -> basename allowlist plus argv path matching.
    line=$(awk -v tty="$ttybase" -v shellpid="$ppid" '
        $2 == tty && $1 != shellpid {
            cmd=$3; sub(".*/", "", cmd); tool=""
            if (cmd ~ /^(claude|codex|copilot|agy|opencode|qwen)$/) tool=cmd
            else if (cmd == "kimi-code" || cmd == "kimi") tool="kimi"
            else if ($0 ~ /\.hermes\/hermes-agent\/hermes/) tool="hermes"
            else if ($0 ~ /qwen-code\/.*cli\.js/ || $0 ~ /\/bin\/qwen( |$)/) tool="qwen"
            if (tool != "") { print tool "\t" $0; exit }
        }' "$psfile")
    [ -n "$line" ] || continue
    tool=${line%%$'\t'*}
    # honour @agent-resume-tools allowlist
    ar_tool_enabled "$tool" "$TOOLS" || continue
    pline=${line#*$'\t'}
    apid=$(printf '%s' "$pline" | awk '{print $1}')
    argv=$(printf '%s' "$pline" | awk '{ $1=""; $2=""; sub(/^  */,""); print }')

    mode="argv"; cmd="$argv"; rowcwd="$ppath"
    case "$tool" in
        claude)
            mapfile_path="$MAP_DIR/$paneid"
            if [ -f "$mapfile_path" ]; then
                sid=$(awk -F'\t' '$1=="claude"{print $2}' "$mapfile_path" 2>/dev/null | head -1)
                mapcwd=$(awk -F'\t' '$1=="claude"{print $3}' "$mapfile_path" 2>/dev/null | head -1)
                mapep=$(awk -F'\t' '$1=="claude"{print $4}' "$mapfile_path" 2>/dev/null | head -1)
                # stale-map guard: pane ids are recycled after a server restart ->
                # the map entry must be newer than this claude's start (±10s fuzz)
                started=$(_proc_start_epoch "$apid")
                if [ -n "$sid" ] && [ -n "$mapep" ] && [ -n "$started" ] \
                    && [ "$mapep" -ge "$(( started - 10 ))" ]; then
                    # cwd comes from the map (SessionStart's real cwd): the transcript
                    # project slug is bound to the session's starting cwd, while
                    # pane_current_path is often the outer shell's cwd. Verify the dir
                    # and transcript both exist, else fall back to argv (fail loud).
                    rcwd="${mapcwd:-$ppath}"
                    slug=$(printf '%s' "$rcwd" | sed 's/[^A-Za-z0-9]/-/g')
                    if [ -d "$rcwd" ] && [ -f "$HOME/.claude/projects/$slug/$sid.jsonl" ]; then
                        base=$(_strip_session_flags "$argv" "--resume --session-id" "--continue --fork-session -c")
                        cmd="$base --resume $sid"
                        mode="map"
                        rowcwd="$rcwd"
                    else
                        slog "warn $coord: sid $sid not resumable (cwd=$rcwd dir=$([ -d "$rcwd" ] && echo ok || echo gone) transcript=$([ -f "$HOME/.claude/projects/$slug/$sid.jsonl" ] && echo ok || echo missing)) -> argv fallback"
                    fi
                fi
            fi
            ;;
        codex)
            rollout=$(lsof -p "$apid" 2>/dev/null | grep -o 'rollout-[^ ]*\.jsonl' | head -1)
            if [ -n "$rollout" ]; then
                sid=$(printf '%s' "$rollout" | sed -n 's/.*rollout-.*-\([0-9a-f-]\{36\}\)\.jsonl/\1/p')
                if [ -n "$sid" ]; then cmd="codex resume $sid"; mode="lsof"; fi
            fi
            ;;
        agy)
            # an agy with an active conversation holds its brain/<uuid> dir (fresh
            # agents do not) -> lsof. Multiple uuids = picker transient -> keep argv.
            bid=$(lsof -p "$apid" 2>/dev/null | grep -oE 'antigravity-cli/brain/[0-9a-f-]{36}' \
                | awk -F/ '{print $NF}' | sort -u)
            if [ -n "$bid" ] && [ "$(printf '%s\n' "$bid" | grep -c .)" -eq 1 ]; then
                base=$(_strip_session_flags "$argv" "--conversation" "--continue -c")
                cmd="$base --conversation $bid"
                mode="lsof"
            fi
            ;;
        copilot)
            # lsof only shows the global session-store.db; the log filename embeds
            # the pid and is the authoritative mapping.
            clog=$(ls -t "$HOME/.copilot/logs/process-"*"-${apid}.log" 2>/dev/null | head -1)
            if [ -n "$clog" ]; then
                sid=$(grep 'Workspace initialized' "$clog" 2>/dev/null | tail -1 \
                    | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
                if [ -n "$sid" ]; then
                    base=$(_strip_session_flags "$argv" "--resume --session-id" "--continue")
                    cmd="$base --resume=$sid"
                    mode="log"
                fi
            fi
            ;;
        opencode)
            # sqlite backend (v1.17+) has no per-session file. argv -s -> replay.
            if ! printf '%s' "$argv" | grep -qE '(^| )(-s|--session)[= ]'; then
                onum=$(awk '{c=$3; sub(".*/","",c); if (c=="opencode") n++} END{print n+0}' "$psfile")
                oclog="$HOME/.local/share/opencode/log/opencode.log"
                if [ "$onum" = "1" ] && [ -f "$oclog" ]; then
                    sid=$(grep -oE 'session\.id=ses_[A-Za-z0-9]+' "$oclog" 2>/dev/null | tail -1 | cut -d= -f2)
                    if [ -n "$sid" ]; then
                        base=$(_strip_session_flags "$argv" "-s --session" "-c --continue --fork")
                        cmd="$base -s $sid"
                        mode="log"
                    fi
                fi
            fi
            ;;
        kimi)
            # argv destroyed by the self-rename (single kimi-code token) -> rebuild;
            # resume hard-binds workDir -> use it. Same-cwd instances are
            # indistinguishable; take the most recently active.
            cmd="kimi"
            kcwd=$(ar_proc_cwd "$apid")
            kidx="$HOME/.kimi-code/session_index.jsonl"
            if [ -n "$kcwd" ] && [ -f "$kidx" ]; then
                best=""; bestm=0; matched=0
                while IFS= read -r kline; do
                    case "$kline" in *"\"workDir\":\"$kcwd\""*) ;; *) continue ;; esac
                    sdir=$(printf '%s' "$kline" | sed -n 's/.*"sessionDir":"\([^"]*\)".*/\1/p')
                    ksid=$(printf '%s' "$kline" | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
                    [ -n "$sdir" ] && [ -f "$sdir/state.json" ] || continue
                    matched=$(( matched + 1 ))
                    m=$(ar_mtime "$sdir/state.json")
                    if [ "$m" -gt "$bestm" ]; then bestm=$m; best="$ksid"; fi
                done < "$kidx"
                if [ -n "$best" ]; then
                    cmd="kimi -r $best"
                    mode="index"
                    rowcwd="$kcwd"
                elif [ "$matched" -gt 0 ]; then
                    slog "warn $coord (kimi): $matched session(s) matched cwd but none selectable (mtime probe empty -- platform tool?) -> argv fallback"
                fi
            elif [ -z "$kcwd" ] && [ -f "$kidx" ]; then
                # a resumable session index exists but the cwd probe came back
                # empty (lsof/readlink absent or wrong-OS) -> log, don't drop it
                # to bare argv in silence. This is the A5 loud-degradation contract.
                slog "warn $coord (kimi): cwd probe empty (platform tool absent?) -> argv fallback"
            fi
            ;;
        hermes)
            # argv --resume replays as-is (python wrapper). fresh: session id
            # YYYYMMDD_HHMMSS_<6hex> timestamp ~ process start, reverse-looked-up.
            if ! printf '%s' "$argv" | grep -qE '(--resume|-r)([= ]|$)'; then
                hlog="$HOME/.hermes/logs/agent.log"
                started=$(_proc_start_epoch "$apid")
                if [ -f "$hlog" ] && [ -n "$started" ]; then
                    hsid=""; hcands=0
                    for hid in $(tail -c 200000 "$hlog" 2>/dev/null \
                        | grep -oE 'session=[0-9]{8}_[0-9]{6}_[0-9a-f]{6}' | cut -d= -f2 | sort -u); do
                        hcands=$(( hcands + 1 ))
                        hts=$(ar_epoch_from_stamp "${hid%_*}"); [ -n "$hts" ] || continue
                        d=$(( started - hts )); [ "$d" -lt 0 ] && d=$(( -d ))
                        [ "$d" -le 120 ] && hsid="$hid"
                    done
                    if [ -n "$hsid" ]; then
                        htail=$(printf '%s' "$argv" | sed 's|.*/hermes-agent/hermes||')
                        base=$(_strip_session_flags "$htail" "--resume -r --continue" "")
                        cmd="hermes${base:+ $base} --resume $hsid"
                        mode="log"
                    elif [ "$hcands" -gt 0 ]; then
                        slog "warn $coord (hermes): $hcands session id(s) in log but none parseable/matched (date probe empty -- platform tool?) -> argv fallback"
                    fi
                fi
            fi
            ;;
        qwen)
            # official runtime sidecar ~/.qwen/projects/<cwd>/chats/<sid>.runtime.json
            # {pid,session_id,work_dir}. File is not deleted on exit -> verify pid
            # belongs to a qwen on this pane tty. resume hard-binds work_dir.
            qpids=$(awk -v tty="$ttybase" \
                '$2==tty && ($0 ~ /qwen-code\/.*cli\.js/ || $0 ~ /\/bin\/qwen( |$)/) {print $1}' "$psfile")
            for rj in "$HOME/.qwen/projects/"*"/chats/"*.runtime.json; do
                [ -f "$rj" ] || continue
                rpid=$(sed -n 's/.*"pid":[[:space:]]*\([0-9]*\).*/\1/p' "$rj" | head -1)
                [ -n "$rpid" ] || continue
                case " $(printf '%s' "$qpids" | tr '\n' ' ') " in
                    *" $rpid "*) ;;
                    *) continue ;;
                esac
                sid=$(sed -n 's/.*"session_id":[[:space:]]*"\([^"]*\)".*/\1/p' "$rj" | head -1)
                qwd=$(sed -n 's/.*"work_dir":[[:space:]]*"\([^"]*\)".*/\1/p' "$rj" | head -1)
                if [ -n "$sid" ]; then
                    cmd="qwen --resume $sid"
                    mode="runtime"
                    [ -n "$qwd" ] && rowcwd="$qwd"
                fi
                break
            done
            ;;
    esac

    printf '%s\t%s\t%s\t%s\t%s\n' "$coord" "$tool" "$mode" "$rowcwd" "$cmd" >> "$tmpfile"
    count=$(( count + 1 ))
done < <(tmux list-panes -a -F $'#{session_name}:#{window_index}.#{pane_index}\t#{pane_id}\t#{pane_pid}\t#{pane_tty}\t#{pane_current_path}' 2>/dev/null)

ar_rotate_snapshots "$SNAP_FILE" "$tmpfile"
rm -f "$psfile"
slog "snapshot ok agents=$count file=$SNAP_FILE"
exit 0
