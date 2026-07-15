#!/usr/bin/env bash
# restore.sh — tmux-resurrect post-restore-all hook. Reads the snapshot.sh
# sidecar and, for each pane still sitting at a shell prompt, types the resume
# command to bring the AI CLI agent back to its checkpoint.
#
# Safety guards:
#   - only send to a pane whose foreground is a bare shell (a running process =
#     resurrect already relaunched it, or a human took over -> skip)
#   - every payload must pass the per-CLI allowlist in validate.sh BEFORE it is
#     sent; a non-matching payload is dropped, logged, never typed
#   - cwd is pre-validated to a metachar-free absolute path (else skip)
#   - 1s between panes so cold-starting agents do not fight for resources
#   - atomic mkdir lock: continuum auto-restore and an active-restore watchdog
#     can both fire this hook within 1-2s
#   - @agent-resume-dry-run (or AGENT_RESUME_DRYRUN=1) logs, sends nothing
#
# Hook script rules: never `set -e`; exit 0.
set -uo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$CURRENT_DIR/common.sh"
# shellcheck source=scripts/validate.sh
. "$CURRENT_DIR/validate.sh"

CACHE="$(ar_cache_dir || true)"
: "${CACHE:=${TMUX_TMPDIR:-/tmp}}"

SNAP_FILE="$(ar_opt AGENT_RESUME_SNAP_FILE @agent-resume-snapshot-file "$HOME/.tmux/resurrect/agents.tsv")"
LOG="$(ar_opt      AGENT_RESUME_LOG        @agent-resume-log            "$CACHE/agent-resume.log")"
TOOLS="$(ar_opt    AGENT_RESUME_TOOLS      @agent-resume-tools          'claude codex agy copilot opencode kimi hermes qwen')"
DRYRUN="$(ar_opt   AGENT_RESUME_DRYRUN     @agent-resume-dry-run        '0')"

rlog() { printf '[%s] [restore] %s\n' "$(date +'%H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true; }

# `timeout` is GNU coreutils and is NOT present on stock macOS (only via
# homebrew, as `timeout` or `gtimeout`). Without this fallback every tmux call
# below would error out and every pane would look "not found" -> nothing ever
# resumes. Degrade to a bare tmux call when no timeout binary exists.
AR_TO="$(command -v timeout || command -v gtimeout || true)"
tt() {  # tt <seconds> <tmux args...>
    local s="$1"; shift
    if [ -n "$AR_TO" ]; then "$AR_TO" -k 2 "$s" tmux "$@"; else tmux "$@"; fi
}

[ -f "$SNAP_FILE" ] || { rlog "no snapshot file, nothing to resume"; exit 0; }

# atomic lock + stale reclaim (double-fire protection)
LOCK_DIR="$CACHE/agent-restore.lock"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    lockage=$(( $(date +%s) - $(ar_mtime "$LOCK_DIR") ))
    if [ "$lockage" -lt 120 ]; then
        rlog "another instance holds lock (age=${lockage}s), exiting"
        exit 0
    fi
    rlog "stale lock cleared (age=${lockage}s)"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

age=$(( $(date +%s) - $(ar_mtime "$SNAP_FILE") ))
sent=0; skipped=0

# Slurp the whole TSV into memory FIRST. The loop body runs tmux (via timeout),
# which intermittently swallows rows from an open file descriptor -- so process
# nothing while a file fd is live. With the rows in an array, the body cannot
# race the reader.
rows=()
while IFS= read -r line; do
    [ -n "$line" ] && rows+=("$line")
done < "$SNAP_FILE"

if [ "${#rows[@]}" -eq 0 ]; then
    rlog "snapshot empty, nothing to resume"
    exit 0
fi

tab=$'\t'
for line in "${rows[@]}"; do
    # split the 5 tab-separated fields with parameter expansion (no herestring:
    # bash 3.2's `<<<` uses a temp fd that the tmux calls in the body disturb).
    # The last field (cmd) may contain spaces but never tabs.
    coord="${line%%"$tab"*}"; rest="${line#*"$tab"}"
    tool="${rest%%"$tab"*}";  rest="${rest#*"$tab"}"
    mode="${rest%%"$tab"*}";  rest="${rest#*"$tab"}"
    cwd="${rest%%"$tab"*}";   cmd="${rest#*"$tab"}"
    [ -n "$coord" ] && [ -n "$cmd" ] || continue
    # @agent-resume-tools allowlist
    if ! ar_tool_enabled "$tool" "$TOOLS"; then
        rlog "skip $coord ($tool): disabled via @agent-resume-tools"
        skipped=$(( skipped + 1 )); continue
    fi
    curcmd=$(tt 2 display -p -t "$coord" '#{pane_current_command}' 2>/dev/null || true)
    if [ -z "$curcmd" ]; then
        rlog "skip $coord ($tool): pane not found after restore"
        skipped=$(( skipped + 1 )); continue
    fi
    case "$curcmd" in
        zsh|bash|sh|-zsh|-bash|fish|-fish) ;;
        *)  rlog "skip $coord ($tool): pane busy with '$curcmd' (not a bare shell)"
            skipped=$(( skipped + 1 )); continue ;;
    esac
    # cwd pre-validation: absolute, metachar-free (so %q below is a no-op and the
    # allowlist cd-prefix matches). A path with spaces or shell metacharacters is
    # rejected rather than risk a quoting bug.
    sendcmd="$cmd"
    if [ -n "$cwd" ]; then
        case "$cwd" in
            /*) ;;
            *)  rlog "skip $coord ($tool): cwd not absolute ($cwd)"
                skipped=$(( skipped + 1 )); continue ;;
        esac
        case "$cwd" in
            *[!A-Za-z0-9._/@:,+~-]*)
                rlog "skip $coord ($tool): cwd has unsafe chars ($cwd)"
                skipped=$(( skipped + 1 )); continue ;;
        esac
        sendcmd="cd $(printf '%q' "$cwd") && $cmd"
    fi
    # injection hardening: fail-closed allowlist. Never type an unvalidated string.
    if ! ar_validate "$tool" "$sendcmd"; then
        rlog "skip $coord ($tool/$mode): payload failed allowlist, not sent: $sendcmd"
        skipped=$(( skipped + 1 )); continue
    fi
    if [ "$DRYRUN" = "1" ]; then
        rlog "DRYRUN $coord ($tool/$mode): would send: $sendcmd"
        sent=$(( sent + 1 )); continue
    fi
    tt 3 send-keys -t "$coord" -l "$sendcmd" 2>/dev/null \
        && tt 3 send-keys -t "$coord" Enter 2>/dev/null \
        && rlog "resumed $coord ($tool/$mode): $sendcmd" \
        && sent=$(( sent + 1 ))
    sleep 1
done

rlog "done sent=$sent skipped=$skipped snapshot_age=${age}s"
exit 0
