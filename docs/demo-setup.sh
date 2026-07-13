#!/bin/bash
# demo-setup.sh — self-contained stage for docs/demo.tape. Starts an ISOLATED
# tmux server (socket: ar-demo, own config) — your real tmux server and config
# are never touched.
#
# Anonymous by construction: an identity-free cockpit shell/theme, fake data
# under /Users/demo/*, and CLAUDE_CONFIG_DIR pointed at a throwaway temp dir.
#
# SAFE BY DESIGN: this is a DRY RUN. Three bare-shell windows (named claude /
# codex / kimi) stand in for restored agent panes; a fixed snapshot TSV maps them
# to resume commands. The tape runs restore.sh with AGENT_RESUME_DRYRUN=1, so it
# only LOGS what it WOULD type after the per-CLI allowlist — nothing is sent and
# no AI CLI is ever launched.
set -u
unset TMUX TMUX_PANE
SOCK=ar-demo
WORK=/tmp/vhs-agent-resume-demo
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_BIN="${TMUX_BIN:-tmux}"

rm -rf "$WORK"; mkdir -p "$WORK/fake-config"
SNAP="$WORK/snap.tsv"
LOG="$WORK/restore.log"
rm -f "$SNAP" "$LOG"

# ── clean, anonymous shell for the pane. Convenience vars let the tape drive the
#    demo without typing identity-bearing absolute paths; CLAUDE_CONFIG_DIR points
#    at a throwaway dir so nothing can touch a real agent config. ──
cat > "$WORK/rc.sh" <<RC
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
export CLAUDE_CONFIG_DIR="$WORK/fake-config"
snap='$SNAP'
log='$LOG'
rest='$PLUGIN/scripts/restore.sh'
PS1='\[\e[38;2;166;227;161m\] dev \[\e[38;2;137;180;250m\]\W\[\e[0m\] ❯ '
PROMPT_COMMAND=
RC

# ── cockpit theme (catppuccin mocha, hardcoded, portable). Single status row:
#    session capsule (left) + clock capsule (right). It fully owns status-left AND
#    status-right so the default hostname never leaks. ──
cat > "$WORK/theme.conf" <<'CONF'
set -g default-terminal "tmux-256color"
set -as terminal-overrides ",xterm-256color:Tc"
set -g mouse on
setw -g automatic-rename off
set -g escape-time 0
set -g status on
set -g status-interval 2
set -g status-style "bg=#1E1E1E,fg=#cdd6f4"
set -g status-left '#[fg=#a6e3a1,bg=#1E1E1E]#[fg=#11111b,bg=#a6e3a1]  #[fg=#cdd6f4,bg=#313244] #S #[fg=#313244,bg=#1E1E1E] '
set -g status-left-length 40
set -g status-right '#[fg=#89dceb,bg=#1E1E1E]#[fg=#11111b,bg=#89dceb]  #[fg=#cdd6f4,bg=#313244] %H:%M #[fg=#313244,bg=#1E1E1E]'
set -g status-right-length 60
set -g window-status-format '#[fg=#6c7086] #I:#W '
set -g window-status-current-format '#[fg=#89b4fa,bold] #I:#W '
set -g window-status-separator ''
set -g pane-border-status top
set -g pane-border-format '#[align=centre]#{?pane_active,#[reverse],}#{pane_index}#[default] #{pane_current_command}'
set -g pane-border-style 'fg=#45475a'
set -g pane-active-border-style 'fg=#fab387,bold'
set -g message-style 'bg=#f9e2af,fg=#11111b,bold'
CONF

# ── isolated server: window 0 (console) runs the clean shell EXPLICITLY (a
#    session's first window is created before default-command applies). ──
"$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null
sleep 0.3
"$TMUX_BIN" -L "$SOCK" -f "$WORK/theme.conf" new-session -d -s demo -x 118 -y 25 -n console -c "$WORK" "bash --rcfile $WORK/rc.sh -i"
"$TMUX_BIN" -L "$SOCK" set -g default-command "bash --rcfile $WORK/rc.sh -i"

# ── three bare-shell stand-in windows for the "restored" agent panes. They run a
#    plain shell (NO real CLI); restore.sh's dry run only needs them to look like
#    bare shells so it logs a "would send" line for each. ──
P1=$("$TMUX_BIN" -L "$SOCK" new-window -dP -F '#{pane_id}' -n claude "bash --norc -i")
P2=$("$TMUX_BIN" -L "$SOCK" new-window -dP -F '#{pane_id}' -n codex  "bash --norc -i")
P3=$("$TMUX_BIN" -L "$SOCK" new-window -dP -F '#{pane_id}' -n kimi   "bash --norc -i")

# ── fixed snapshot TSV: pane, tool, mode, cwd, resume command. All fake:
#    /Users/demo/* paths and placeholder session ids that pass the allowlist. ──
printf '%s\t%s\t%s\t%s\t%s\n' "$P1" claude hook /Users/demo/webapp 'claude --resume 3f2a1b4c-5d6e-7f80-9a1b-2c3d4e5f6071' >  "$SNAP"
printf '%s\t%s\t%s\t%s\t%s\n' "$P2" codex  argv /Users/demo/api    'codex resume a1b2c3d4-e5f6-7a80-9b1c-2d3e4f5a6b7c'   >> "$SNAP"
printf '%s\t%s\t%s\t%s\t%s\n' "$P3" kimi   argv /Users/demo/infra  'kimi -r session_9f8e7d6c-5b4a-3210-fedc-ba9876543210' >> "$SNAP"

# start the demo on the console window
"$TMUX_BIN" -L "$SOCK" select-window -t demo:0
