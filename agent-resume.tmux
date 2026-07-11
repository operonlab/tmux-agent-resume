#!/usr/bin/env bash
# agent-resume.tmux — TPM entry point. Chains our snapshot/restore scripts onto
# tmux-resurrect's post-save-all / post-restore-all hooks WITHOUT clobbering any
# hook value the user (or another plugin) already set. Idempotent across reloads.
set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP="$CURRENT_DIR/scripts/snapshot.sh"
REST="$CURRENT_DIR/scripts/restore.sh"

# resurrect eval's the hook value as a SHELL command string (see its helpers.sh:
# `eval "$hook $args"`), so our segment is a plain `bash '<path>'` invocation.
OUR_SAVE="bash '$SNAP'"
OUR_REST="bash '$REST'"

# $1=@option  $2=our segment. Append our segment unless already present. Keeps
# the user's existing value first, joined with '; '.
chain_hook() {
    local opt="$1" seg="$2" cur
    cur="$(tmux show-option -gqv "$opt" 2>/dev/null || true)"
    case "$cur" in
        *"$seg"*) return 0 ;;                                   # already chained
        "")  tmux set -g "$opt" "$seg" ;;                        # nothing there yet
        *)   tmux set -g "$opt" "$cur; $seg" ;;                  # preserve + append
    esac
}

chain_hook @resurrect-hook-post-save-all    "$OUR_SAVE"
chain_hook @resurrect-hook-post-restore-all "$OUR_REST"

# peer dependency check (non-fatal): the hooks above only ever fire if
# tmux-resurrect is installed. Warn once if we cannot find it.
resurrect_present() {
    local pdir="${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins}"
    [ -d "$pdir/tmux-resurrect" ] && return 0
    tmux list-keys 2>/dev/null | grep -q 'resurrect' && return 0
    return 1
}
if ! resurrect_present; then
    tmux display-message "tmux-agent-resume: tmux-resurrect not found — it is a peer dependency (see README)."
fi

# the last matched-case guard can leave a non-zero $? on a clean run; don't let
# that surface as a scary "returned 1" on every config reload.
exit 0
