#!/usr/bin/env bash
# install-claude-hook.sh — idempotently register (or remove) the
# claude-session-map.sh SessionStart hook in Claude Code's settings.json.
#
# TARGET DIRECTORY: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}. Set CLAUDE_CONFIG_DIR to
# point this at a throwaway directory (the test harness always does). On a real
# machine the user runs this themselves, once.
#
# Usage:
#   install-claude-hook.sh            # add the hook (idempotent)
#   install-claude-hook.sh uninstall  # remove exactly the hook we added
#
# Requires jq. Writes are atomic (temp file + mv) and validated before swap.
set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$CURRENT_DIR/claude-session-map.sh"
HOOK_CMD="bash '$HOOK_SCRIPT'"

CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG_DIR/settings.json"

action="${1:-install}"

if ! command -v jq >/dev/null 2>&1; then
    cat >&2 <<EOF
install-claude-hook: jq is required but not found.

Add this to $SETTINGS manually, under .hooks.SessionStart:
  { "hooks": [ { "type": "command", "command": "$HOOK_CMD" } ] }
EOF
    exit 1
fi

mkdir -p "$CFG_DIR" 2>/dev/null || { printf 'install-claude-hook: cannot create %s\n' "$CFG_DIR" >&2; exit 1; }

# current settings (or an empty object)
if [ -f "$SETTINGS" ]; then
    src="$(cat "$SETTINGS")"
else
    src='{}'
fi

# validate existing json up front so we never clobber a broken-but-precious file
if ! printf '%s' "$src" | jq -e . >/dev/null 2>&1; then
    printf 'install-claude-hook: %s is not valid JSON; refusing to edit.\n' "$SETTINGS" >&2
    exit 1
fi

tmp="$SETTINGS.tmp.$$"
case "$action" in
    install)
        out="$(printf '%s' "$src" | jq --arg cmd "$HOOK_CMD" '
            .hooks //= {} |
            .hooks.SessionStart //= [] |
            if ([.hooks.SessionStart[]?.hooks[]?.command] | index($cmd)) then .
            else .hooks.SessionStart += [{"hooks":[{"type":"command","command":$cmd}]}]
            end
        ')" || { printf 'install-claude-hook: jq transform failed\n' >&2; exit 1; }
        already="$(printf '%s' "$src" | jq --arg cmd "$HOOK_CMD" \
            '([.hooks.SessionStart[]?.hooks[]?.command] | index($cmd)) != null')"
        printf '%s\n' "$out" > "$tmp" || exit 1
        jq -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; printf 'install-claude-hook: produced invalid JSON, aborting\n' >&2; exit 1; }
        mv -f "$tmp" "$SETTINGS" || { rm -f "$tmp"; exit 1; }
        if [ "$already" = "true" ]; then
            printf 'install-claude-hook: already installed in %s (no change).\n' "$SETTINGS"
        else
            printf 'install-claude-hook: SessionStart hook added to %s.\n' "$SETTINGS"
        fi
        ;;
    uninstall)
        if [ ! -f "$SETTINGS" ]; then
            printf 'install-claude-hook: %s does not exist, nothing to remove.\n' "$SETTINGS"
            exit 0
        fi
        out="$(printf '%s' "$src" | jq --arg cmd "$HOOK_CMD" '
            if (.hooks.SessionStart | type) == "array" then
              .hooks.SessionStart |= map(
                .hooks |= (map(select(.command != $cmd)))
              )
              | .hooks.SessionStart |= map(select((.hooks | length) > 0))
            else . end
        ')" || { printf 'install-claude-hook: jq transform failed\n' >&2; exit 1; }
        printf '%s\n' "$out" > "$tmp" || exit 1
        jq -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; printf 'install-claude-hook: produced invalid JSON, aborting\n' >&2; exit 1; }
        mv -f "$tmp" "$SETTINGS" || { rm -f "$tmp"; exit 1; }
        printf 'install-claude-hook: SessionStart hook removed from %s.\n' "$SETTINGS"
        ;;
    *)
        printf 'usage: %s [install|uninstall]\n' "$(basename "$0")" >&2
        exit 2
        ;;
esac
exit 0
