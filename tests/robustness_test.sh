#!/usr/bin/env bash
# robustness_test.sh — tests for the snapshot rotation (A6) and the portable
# id-probe fallback + loud warning (A5).
#
# Rotation and the portable primitives are exercised as pure filesystem/string
# calls against scripts/common.sh (no tmux). The warning path is driven through
# scripts/snapshot.sh with a fake `kimi-code` agent on a throwaway `-L` socket
# (never the real server); a failing `stat` shim stands in for "the platform
# tool is absent" so the mtime probe yields nothing.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/scripts/common.sh"

TMPD="$(mktemp -d)"
REALTMUX="$(command -v tmux || true)"
SOCK="agent-resume-robust-$$"
SHIM=""
KPID=""
pass=0
fail=0

ok()   { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }
skip() { printf 'SKIP: %s\n' "$1"; }

cleanup() {
    [ -n "$KPID" ] && kill "$KPID" 2>/dev/null
    [ -n "$REALTMUX" ] && "$REALTMUX" -L "$SOCK" kill-server 2>/dev/null
    [ -n "$SHIM" ] && rm -rf "$SHIM"
    rm -rf "$TMPD"
}
trap cleanup EXIT

count_snaps() { ls "$1"/agents.*.tsv 2>/dev/null | grep -c . ; }

# ── 1. rotation: identical snapshots dedup to a single file ───────────────
D1="$TMPD/rot1"; mkdir -p "$D1"; SNAP1="$D1/agents.tsv"
t="$(mktemp)"; printf 'same\n' > "$t"; ar_rotate_snapshots "$SNAP1" "$t"
t="$(mktemp)"; printf 'same\n' > "$t"; ar_rotate_snapshots "$SNAP1" "$t"
n="$(count_snaps "$D1")"
if [ "$n" = "1" ]; then ok "rotation dedups identical snapshots (1 file kept)"
else bad "rotation kept $n files for identical snapshots (expected 1)"; fi

# touch <file> to an mtime <days> in the past (portable BSD/GNU).
touch_days_ago() {
    local ep fmt
    ep=$(( $(date +%s) - $2 * 86400 ))
    if [ "$(uname)" = Darwin ]; then fmt="$(date -r "$ep" +%Y%m%d%H%M.%S)"
    else fmt="$(date -d "@$ep" +%Y%m%d%H%M.%S)"; fi
    touch -t "$fmt" "$1"
}

# Pin the floor + age-out through the env layer (ar_opt reads env before any
# tmux option), so rotation runs hermetically with keep=3, days=30.
AGENT_RESUME_KEEP=3
AGENT_RESUME_KEEP_DAYS=30

# ── 2. rotation age-out: a beyond-floor but RECENT snapshot is KEPT; only the
#       beyond-floor snapshots older than KEEP_DAYS are pruned. This is the
#       floor + age-out discriminator — a hard count cap would also delete the
#       recent rC. ─────────────────────────────────────────────────────────
D2="$TMPD/rot2"; mkdir -p "$D2"; SNAP2="$D2/agents.tsv"
mkf() { printf '%s\n' "$1" > "$D2/agents.$1.tsv"; touch_days_ago "$D2/agents.$1.tsv" "$2"; }
mkf rA 1      # recent, inside floor
mkf rB 2      # recent, inside floor
mkf rC 4      # recent, BEYOND floor -> kept (age-out, not a hard cap)
mkf oD 40     # old, beyond floor -> pruned
mkf oE 50     # old, beyond floor -> pruned
ln -sfn agents.rA.tsv "$SNAP2"
t="$(mktemp)"; printf 'newest\n' > "$t"; ar_rotate_snapshots "$SNAP2" "$t"
n="$(count_snaps "$D2")"
if [ "$n" = "4" ] \
   && [ -e "$D2/agents.rC.tsv" ] \
   && [ ! -e "$D2/agents.oD.tsv" ] \
   && [ ! -e "$D2/agents.oE.tsv" ]; then
    ok "rotation age-out: recent-beyond-floor kept, only >KEEP_DAYS beyond floor pruned"
else
    bad "rotation age-out wrong: n=$n (rC must stay, oD/oE must go)"
fi
newest="$(ls -t "$D2"/agents.*.tsv | head -1)"
if [ "$(readlink "$SNAP2")" = "$(basename "$newest")" ]; then
    ok "rotation points 'last' symlink at the newest snapshot"
else
    bad "rotation 'last' -> $(readlink "$SNAP2"), newest is $(basename "$newest")"
fi

# ── 2b. rotation floor precision: with every file older than KEEP_DAYS, the
#        newest KEEP by rank are protected and everything beyond is pruned —
#        this pins the keep boundary (a +/-1 off-by-one shifts the count). ───
D2b="$TMPD/rot2b"; mkdir -p "$D2b"; SNAP2b="$D2b/agents.tsv"
mkf2() { printf '%s\n' "$1" > "$D2b/agents.$1.tsv"; touch_days_ago "$D2b/agents.$1.tsv" "$2"; }
mkf2 q1 31   # inside floor by rank (kept despite being >KEEP_DAYS)
mkf2 q2 33   # inside floor by rank (kept despite being >KEEP_DAYS)
mkf2 q3 35   # first beyond floor -> pruned
mkf2 q4 40   # beyond floor -> pruned
mkf2 q5 45   # beyond floor -> pruned
ln -sfn agents.q1.tsv "$SNAP2b"
t="$(mktemp)"; printf 'newest\n' > "$t"; ar_rotate_snapshots "$SNAP2b" "$t"
n="$(count_snaps "$D2b")"
if [ "$n" = "3" ] \
   && [ -e "$D2b/agents.q2.tsv" ] \
   && [ ! -e "$D2b/agents.q3.tsv" ]; then
    ok "rotation floor: newest KEEP protected by rank, beyond-floor pruned (boundary pinned)"
else
    bad "rotation floor wrong: n=$n (q2 must stay inside floor, q3 must be pruned)"
fi

unset AGENT_RESUME_KEEP AGENT_RESUME_KEEP_DAYS

# ── 3. portable primitives select the right branch per OS ─────────────────
mf="$TMPD/mfile"; before="$(date +%s)"; : > "$mf"; after="$(date +%s)"
native="$(ar_mtime "$mf")"
if [ "$native" -ge "$before" ] && [ "$native" -le "$after" ]; then
    ok "ar_mtime returns the real mtime on the native branch ($native)"
else
    bad "ar_mtime native gave $native, not in [$before,$after]"
fi
# forcing the OTHER OS runs the wrong stat flag -> degrades to 0
if [ "$(uname)" = Darwin ]; then opp="$(AR_OS=Linux ar_mtime "$mf")"
else opp="$(AR_OS=Darwin ar_mtime "$mf")"; fi
if [ "$opp" = "0" ]; then ok "ar_mtime degrades to 0 on the wrong-OS branch (dispatch works)"
else bad "ar_mtime wrong-OS branch gave $opp, expected 0"; fi

stamp="20260101_120000"
ep="$(ar_epoch_from_stamp "$stamp")"
if [ "$(uname)" = Darwin ]; then rt="$(date -r "$ep" +%Y%m%d_%H%M%S 2>/dev/null)"
else rt="$(date -d "@$ep" +%Y%m%d_%H%M%S 2>/dev/null)"; fi
if [ -n "$ep" ] && [ "$rt" = "$stamp" ]; then
    ok "ar_epoch_from_stamp parses the native branch (round-trips $stamp)"
else
    bad "ar_epoch_from_stamp gave ep=$ep round-trip=$rt (expected $stamp)"
fi

# ── 4. warning path: probe degrades to a LOGGED warning, not silent drop ──
if [ -z "$REALTMUX" ]; then
    skip "tmux not installed — warning-path integration check skipped"
    printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ] && exit 0 || exit 1
fi
unset TMUX
SHIM="$(mktemp -d)"
printf '#!/bin/sh\nexec %s -L %s "$@"\n' "$REALTMUX" "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"

HOMEDIR="$TMPD/home"; mkdir -p "$HOMEDIR/.kimi-code"
WORK="$TMPD/work"; mkdir -p "$WORK"
tmux -f /dev/null new-session -d -s k -c "$WORK"
tmux send-keys -t k "cd '$WORK'; bash -c 'exec -a kimi-code sleep 300' &" Enter
sleep 1
KPID="$(ps -axo pid=,command= | awk '/[k]imi-code/{print $1; exit}')"

if [ -z "$KPID" ]; then
    bad "test setup: fake kimi-code agent not found in ps"
else
    KCWD="$(ar_proc_cwd "$KPID")"
    SDIR="$TMPD/sess"; mkdir -p "$SDIR"; printf '{}' > "$SDIR/state.json"
    printf '{"workDir":"%s","sessionDir":"%s","sessionId":"sess-abc"}\n' \
        "$KCWD" "$SDIR" > "$HOMEDIR/.kimi-code/session_index.jsonl"

    # 4a. probe works -> resume command built (mode=index)
    SNAPA="$TMPD/a.tsv"; LOGA="$TMPD/a.log"
    HOME="$HOMEDIR" AGENT_RESUME_SNAP_FILE="$SNAPA" AGENT_RESUME_LOG="$LOGA" \
        AGENT_RESUME_TOOLS="kimi" bash "$ROOT/scripts/snapshot.sh" >/dev/null 2>&1
    rowa="$(cat "$SNAPA" 2>/dev/null)"
    if printf '%s' "$rowa" | grep -q $'\tkimi\tindex\t' \
       && printf '%s' "$rowa" | grep -q 'kimi -r sess-abc'; then
        ok "probe resolves the kimi session (mode=index, resume built)"
    else
        bad "probe did not build resume cmd (row: $rowa)"
    fi

    # 4b. macOS tool absent (failing stat shim) -> LOGGED warning, argv fallback
    printf '#!/bin/sh\nexit 1\n' > "$SHIM/stat"; chmod +x "$SHIM/stat"
    SNAPB="$TMPD/b.tsv"; LOGB="$TMPD/b.log"
    HOME="$HOMEDIR" AGENT_RESUME_SNAP_FILE="$SNAPB" AGENT_RESUME_LOG="$LOGB" \
        AGENT_RESUME_TOOLS="kimi" bash "$ROOT/scripts/snapshot.sh" >/dev/null 2>&1
    rowb="$(cat "$SNAPB" 2>/dev/null)"
    if grep -q 'warn.*kimi.*none selectable' "$LOGB" 2>/dev/null; then
        ok "probe degradation is logged loudly (not silent)"
    else
        bad "probe degraded silently — no warning in log ($(tr '\n' '|' < "$LOGB" 2>/dev/null))"
    fi
    if printf '%s' "$rowb" | grep -q $'\tkimi\targv\t'; then
        ok "degraded probe falls back to bare argv (mode=argv)"
    else
        bad "degraded probe row unexpected (row: $rowb)"
    fi

    # 4c. cwd probe ITSELF empty (id-probe tool absent / wrong-OS) -> a resumable
    #     index still exists, so this must LOG loudly, not drop to bare argv in
    #     silence. Shim the OS-appropriate cwd probe (lsof / readlink) to fail.
    if [ "$(uname)" = Darwin ]; then printf '#!/bin/sh\nexit 1\n' > "$SHIM/lsof"
    else printf '#!/bin/sh\nexit 1\n' > "$SHIM/readlink"; fi
    chmod +x "$SHIM/lsof" "$SHIM/readlink" 2>/dev/null
    SNAPC="$TMPD/c.tsv"; LOGC="$TMPD/c.log"
    HOME="$HOMEDIR" AGENT_RESUME_SNAP_FILE="$SNAPC" AGENT_RESUME_LOG="$LOGC" \
        AGENT_RESUME_TOOLS="kimi" bash "$ROOT/scripts/snapshot.sh" >/dev/null 2>&1
    rowc="$(cat "$SNAPC" 2>/dev/null)"
    if grep -q 'warn.*kimi.*cwd probe empty' "$LOGC" 2>/dev/null; then
        ok "cwd probe empty is logged loudly (not a silent argv drop)"
    else
        bad "cwd probe empty degraded silently ($(tr '\n' '|' < "$LOGC" 2>/dev/null))"
    fi
    if printf '%s' "$rowc" | grep -q $'\tkimi\targv\t'; then
        ok "cwd-probe-empty falls back to bare argv (mode=argv)"
    else
        bad "cwd-probe-empty row unexpected (row: $rowc)"
    fi
fi

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && exit 0 || exit 1
