#!/usr/bin/env bash
# smoke.sh — integration tests for tmux-agent-resume.
#
# EVERY tmux call runs against a throwaway `-L` socket via a PATH shim, so the
# user's real (default-socket) server is never touched. No AI CLI is launched;
# panes are plain shells / `sleep`, and restore runs in dry-run so nothing is
# ever typed for real.
#
# What CAN be verified headless (this script):
#   - all scripts parse (bash -n)
#   - agent-resume.tmux CHAINS onto an existing resurrect hook (never clobbers)
#     and is idempotent across reloads
#   - snapshot.sh on a server with no AI CLI writes an empty (agents=0) TSV
#   - restore.sh skips a busy pane, rejects an injection payload via the
#     allowlist, and would-send a validated payload (dry-run)
#   - teardown.sh removes only our hook segment, preserving the user's
#
# What CANNOT be verified headless: an actual AI CLI reattaching to its real
# session (needs a live agent + a server restart). That is the battle-tested
# path documented in README/per-cli-matrix and is a human check.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="agent-resume-smoke-$$"
REALTMUX="$(command -v tmux || true)"
SHIM=""
TMPD="$(mktemp -d)"
pass=0
fail=0

ok()   { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }
skip() { printf 'SKIP: %s\n' "$1"; }

cleanup() {
    [ -n "$REALTMUX" ] && "$REALTMUX" -L "$SOCK" kill-server 2>/dev/null
    rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK" 2>/dev/null
    [ -n "$SHIM" ] && rm -rf "$SHIM"
    rm -rf "$TMPD"
}
trap cleanup EXIT

# ── 1. syntax ─────────────────────────────────────────────────
for f in agent-resume.tmux scripts/common.sh scripts/validate.sh scripts/snapshot.sh \
         scripts/restore.sh scripts/teardown.sh hooks/claude-session-map.sh \
         hooks/install-claude-hook.sh; do
    if bash -n "$ROOT/$f" 2>/dev/null; then ok "bash -n $f"; else bad "bash -n $f"; fi
done

if [ -z "$REALTMUX" ]; then
    skip "tmux not installed — server-backed checks skipped"
    printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ] && exit 0 || exit 1
fi

# ── PATH shim: any bare `tmux` routes to the isolated socket ───
SHIM="$(mktemp -d)"
printf '#!/bin/sh\nexec %s -L %s "$@"\n' "$REALTMUX" "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"

tmux -f /dev/null new-session -d -s t
tmux new-window -t t:1
tmux new-window -t t:2 "sleep 300"
sleep 0.4

# resolve the three pane coords (bareA, bareB, busy=sleep)
list_coords() { tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'; }
BAREA="$(list_coords | awk '$2 ~ /^-?(zsh|bash|sh)$/ {print $1; exit}')"
BAREB="$(list_coords | awk '$2 ~ /^-?(zsh|bash|sh)$/' | awk 'NR==2{print $1}')"
BUSY="$(list_coords  | awk '$2 == "sleep" {print $1; exit}')"

# ── 2. hook chain preserves an existing user hook ─────────────
tmux set -g @resurrect-hook-post-save-all 'echo mine'
tmux set -g @resurrect-hook-post-restore-all 'echo myrestore'
bash "$ROOT/agent-resume.tmux" >/dev/null 2>&1
save_val="$(tmux show-option -gqv @resurrect-hook-post-save-all)"
rest_val="$(tmux show-option -gqv @resurrect-hook-post-restore-all)"
if printf '%s' "$save_val" | grep -q 'echo mine' \
   && printf '%s' "$save_val" | grep -q 'snapshot.sh'; then
    ok "post-save-all chains user 'echo mine' + our snapshot.sh"
else
    bad "post-save-all chain missing a piece: [$save_val]"
fi
if printf '%s' "$rest_val" | grep -q 'echo myrestore' \
   && printf '%s' "$rest_val" | grep -q 'restore.sh'; then
    ok "post-restore-all chains user 'echo myrestore' + our restore.sh"
else
    bad "post-restore-all chain missing a piece: [$rest_val]"
fi

# ── 3. idempotent across reloads (no duplicate segment) ───────
bash "$ROOT/agent-resume.tmux" >/dev/null 2>&1
save_val2="$(tmux show-option -gqv @resurrect-hook-post-save-all)"
n_snap="$(printf '%s' "$save_val2" | grep -o 'snapshot.sh' | wc -l | tr -d ' ')"
if [ "$n_snap" = "1" ]; then
    ok "reload is idempotent (snapshot.sh appears once)"
else
    bad "reload duplicated our segment (snapshot.sh x$n_snap)"
fi

# ── 4. snapshot: no AI CLI -> empty (agents=0) TSV, no crash ──
SNAP_TSV="$TMPD/agents.tsv"
SNAP_LOG="$TMPD/snap.log"
snap_err="$(AGENT_RESUME_SNAP_FILE="$SNAP_TSV" AGENT_RESUME_LOG="$SNAP_LOG" \
            bash "$ROOT/scripts/snapshot.sh" 2>&1)"
snap_rc=$?
lines="$( [ -f "$SNAP_TSV" ] && wc -l < "$SNAP_TSV" | tr -d ' ' || echo missing )"
if [ "$snap_rc" -eq 0 ] && [ "$lines" = "0" ] && [ -z "$snap_err" ]; then
    ok "snapshot on AI-CLI-free server -> empty TSV, exit 0, no stderr"
else
    bad "snapshot rc=$snap_rc lines=$lines err=[$snap_err]"
fi
grep -q 'agents=0' "$SNAP_LOG" 2>/dev/null && ok "snapshot logged agents=0" \
    || bad "snapshot log missing agents=0"

# ── 5. restore: busy-skip + injection-reject + validated dry-run ─
if [ -z "$BAREA" ] || [ -z "$BAREB" ] || [ -z "$BUSY" ]; then
    bad "test setup: could not resolve panes (bareA=$BAREA bareB=$BAREB busy=$BUSY)"
fi
U='12345678-1234-1234-1234-123456789abc'
REST_TSV="$TMPD/restore.tsv"
REST_LOG="$TMPD/restore.log"
{
    printf '%s\tclaude\tmap\t/tmp\tclaude --resume %s\n' "$BAREA" "$U"   # valid  -> would send
    printf '%s\tclaude\tmap\t\tclaude; id\n'             "$BAREB"        # inject -> reject
    printf '%s\tclaude\tmap\t\tclaude --resume %s\n'     "$BUSY"  "$U"   # busy   -> skip
} > "$REST_TSV"
AGENT_RESUME_SNAP_FILE="$REST_TSV" AGENT_RESUME_LOG="$REST_LOG" AGENT_RESUME_DRYRUN=1 \
    bash "$ROOT/scripts/restore.sh" >/dev/null 2>&1

if grep -q "busy with 'sleep'" "$REST_LOG" 2>/dev/null; then
    ok "restore skips busy (sleep) pane"
else
    bad "restore did not skip busy pane (log: $(tr '\n' '|' < "$REST_LOG"))"
fi
if grep -q 'failed allowlist' "$REST_LOG" 2>/dev/null \
   && ! grep -q 'would send: claude; id' "$REST_LOG" 2>/dev/null; then
    ok "restore rejects injection payload (never reaches send)"
else
    bad "restore did not reject injection (log: $(tr '\n' '|' < "$REST_LOG"))"
fi
if grep -q "DRYRUN $BAREA .*would send: cd /tmp && claude --resume $U" "$REST_LOG" 2>/dev/null; then
    ok "restore would-send validated payload (dry-run)"
else
    bad "restore did not dry-run the valid payload (log: $(tr '\n' '|' < "$REST_LOG"))"
fi

# ── 6. teardown removes only our segment ──────────────────────
bash "$ROOT/scripts/teardown.sh" >/dev/null 2>&1
save_after="$(tmux show-option -gqv @resurrect-hook-post-save-all)"
rest_after="$(tmux show-option -gqv @resurrect-hook-post-restore-all)"
if [ "$save_after" = 'echo mine' ] && [ "$rest_after" = 'echo myrestore' ]; then
    ok "teardown restored user hooks exactly (our segment removed)"
else
    bad "teardown left [$save_after] / [$rest_after]"
fi

skip "live AI CLI reattach across a real server restart — human check (see README)"

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && exit 0 || exit 1
