#!/usr/bin/env bash
# teardown.sh — clean removal. Unchains ONLY our segment from the resurrect
# hook values, leaving any hook the user (or another plugin) set in place.
# Does NOT touch Claude's settings.json (run `hooks/install-claude-hook.sh
# uninstall` for that) and does NOT remove the ephemeral cache under
# $TMUX_TMPDIR. Your @agent-resume-* tmux.conf lines are left alone.
# Run from an attached client:  bash scripts/teardown.sh
set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP="$CURRENT_DIR/snapshot.sh"
REST="$CURRENT_DIR/restore.sh"
OUR_SAVE="bash '$SNAP'"
OUR_REST="bash '$REST'"

# remove our segment from a chained hook value, preserving everything else.
unchain_hook() {
    local opt="$1" seg="$2" cur new
    cur="$(tmux show-option -gqv "$opt" 2>/dev/null || true)"
    case "$cur" in
        *"$seg"*) ;;        # our segment is present -> strip it
        *) return 0 ;;      # not ours -> leave the user's value untouched
    esac
    if [ "$cur" = "$seg" ]; then
        tmux set -gu "$opt" 2>/dev/null
        return 0
    fi
    new="$cur"
    new="${new%"; $seg"}"                 # trailing  "...; ours"
    new="${new#"$seg; "}"                 # leading   "ours; ..."
    case "$new" in
        *"; $seg; "*) new="${new/"; $seg; "/"; "}" ;;  # middle "...; ours; ..."
    esac
    if [ "$new" = "$cur" ]; then          # embedded oddly -> literal strip
        new="${cur//"$seg"/}"
    fi
    if [ -n "$new" ] && [ "$new" != "$seg" ]; then
        tmux set -g "$opt" "$new" 2>/dev/null
    else
        tmux set -gu "$opt" 2>/dev/null
    fi
}

unchain_hook @resurrect-hook-post-save-all    "$OUR_SAVE"
unchain_hook @resurrect-hook-post-restore-all "$OUR_REST"

printf '%s\n' "tmux-agent-resume: resurrect hook chain cleared (user segments preserved)."
printf '%s\n' "  To remove the Claude SessionStart hook too: bash hooks/install-claude-hook.sh uninstall"
