#!/usr/bin/env bash
# claude-session-map.sh — Claude Code SessionStart hook. Writes a
# tty(pane) -> current session id map that snapshot.sh reads to answer "which
# claude session is live in this pane right now". A fresh claude's argv has no
# session id, and a --resume id goes stale after /clear -- only the SessionStart
# event carries the current id, and startup/resume/clear all fire this hook, so
# the map self-corrects.
#
# Hook rules: never `set -e`; SessionStart stdout is injected into the model
# context, so emit NOTHING on stdout; always exit 0.
set -u

# map dir: env (tests) > @agent-resume-map-dir (if inside tmux) > default cache.
# The default MUST match snapshot.sh's default so both agree without any config.
_cache="${TMUX_TMPDIR:-/tmp}/tmux-agent-resume-$(id -u)"
MAP_DIR="${AGENT_RESUME_MAP_DIR:-${CLAUDE_TTY_MAP_DIR:-}}"
if [ -z "$MAP_DIR" ] && [ -n "${TMUX:-}" ]; then
    MAP_DIR="$(tmux show-option -gqv @agent-resume-map-dir 2>/dev/null || true)"
fi
[ -n "$MAP_DIR" ] || MAP_DIR="$_cache/claude-map"

payload=$(cat 2>/dev/null || true)
sid=$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
cwd=$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$sid" ] || exit 0

# the hook is spawned detached (no controlling tty) but TMUX_PANE is inherited
# from claude -> key by pane id (%N). Non-tmux sessions (no TMUX_PANE) are not
# mapped. pane ids are recycled after a server restart, so stamp an epoch;
# snapshot.sh verifies the entry is newer than the agent process.
key="${TMUX_PANE:-}"
[ -n "$key" ] || exit 0

mkdir -p "$MAP_DIR" 2>/dev/null || exit 0
chmod 700 "$MAP_DIR" 2>/dev/null || true
[ -d "$MAP_DIR" ] && [ ! -L "$MAP_DIR" ] || exit 0
printf 'claude\t%s\t%s\t%s\n' "$sid" "${cwd:-}" "$(date +%s)" > "$MAP_DIR/$key" 2>/dev/null || true
exit 0
