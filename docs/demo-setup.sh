#!/bin/bash
# demo-setup.sh — self-contained stage for docs/demo.tape. Starts an ISOLATED
# tmux server (socket: ar-demo, own config) — your real tmux server and config
# are never touched.
#
# Anonymous by construction: an identity-free Starship-clone prompt (user "dev"),
# a staged demo-app git repo, fake snapshot data under /Users/demo/*, and
# CLAUDE_CONFIG_DIR pointed at a throwaway temp dir.
#
# FAMILY-CONSISTENT: the same two-row pill cockpit as the rest of the plugin
# family (catppuccin mocha, half-circle end-caps). Row 1 = session / window /
# cluster / weather-clock chrome; Row 2 left = staged CLAUDE/CODEX/GEMINI quota
# pills, Row 2 right = a NET/CPU/MEM/DISK system capsule. The cockpit is pure
# chrome here — this plugin has no live status token; its REAL data is the typed
# restore flow in the pane body (snapshot TSV + restore.sh dry run + log).
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

# ── glyphs (byte escapes) + mocha palette ──
CAPL=$(printf '\xee\x82\xb6'); CAPR=$(printf '\xee\x82\xb4'); SEP=$(printf '\xee\x82\xb0')
I_TERM=$(printf '\xee\x9e\x95');   I_ROBOT=$(printf '\xf3\xb0\x9a\xa9')
I_PLAY=$(printf '\xef\x81\x8b');   I_PAUSE=$(printf '\xef\x81\x8c')
I_FLEET=$(printf '\xef\x84\x88');  I_CAL=$(printf '\xef\x86\xae')
I_THERMO=$(printf '\xef\x8b\x89'); I_CLOCK=$(printf '\xef\x80\x97')
I_NET=$(printf '\xef\x83\xac');    I_CPU=$(printf '\xf3\xb0\x93\x85')
I_MEM=$(printf '\xf3\xb0\x8d\x9b');I_DISK=$(printf '\xef\x82\xa0')
I_CLAUDE=$(printf '\xef\x81\xa9'); I_CODEX=$(printf '\xef\x84\xa1'); I_GEMINI=$(printf '\xef\x86\xa0')
BG='#1E1E1E'; CRUST='#11111b'; FG='#cdd6f4'; SURF='#313244'
PEACH='#fab387'; YELLOW='#f9e2af'; MAROON='#eba0ac'; LAVENDER='#b4befe'
MAUVE='#cba6f7'; PINK='#f5c2e7'; BLUE='#89b4fa'; SKY='#89dceb'
SAPPHIRE='#74c7ec'; TEAL='#94e2d5'; GREEN='#a6e3a1'; RED='#f38ba8'

p_open()  { printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s]%s  ' "$1" "$BG" "$CAPL" "$CRUST" "$1" "$2"; }
p_text()  { printf '#[fg=%s,bg=%s] %s ' "$FG" "$SURF" "$1"; }
p_badge() { printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s]%s ' "$1" "$SURF" "$CAPL" "$CRUST" "$1" "$2"; }
p_ibadge(){ printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s]%s  ' "$1" "$SURF" "$CAPL" "$CRUST" "$1" "$2"; }
p_close() { printf '#[fg=%s,bg=%s]%s ' "$SURF" "$BG" "$CAPR"; }

# ── Row 1 pieces: session pill · window chips · cluster capsule · right pill ──
LEFT_R1="#[fg=$GREEN,bg=$BG]${CAPL}#[fg=$CRUST,bg=$GREEN]${I_TERM}  #[fg=$FG,bg=$SURF] #S #[fg=$SURF,bg=$BG]${CAPR} "
WINF="#[fg=$CRUST,bg=#9399b2]#[fg=$BG,reverse]${CAPL}#[none]#I #[fg=$FG,bg=$SURF] #W "
WINCUR="#[fg=$CRUST,bg=$PEACH]#[fg=$BG,reverse]${CAPL}#[none]#I #[fg=$FG,bg=#45475a] #W "
CLUSTER="#[fg=$MAUVE,bg=$BG]${CAPL}#[fg=$CRUST,bg=$MAUVE]${I_ROBOT}  #[fg=$FG,bg=$SURF] ${I_PLAY} 1  ${I_PAUSE} 8 #[fg=$SAPPHIRE,bg=$SURF]${CAPL}#[fg=$CRUST,bg=$SAPPHIRE]${I_FLEET}  #[fg=$FG,bg=$SURF] #[fg=$GREEN,bg=$SURF]M #[fg=$GREEN,bg=$SURF]W #[fg=$RED,bg=$SURF]A #[fg=$SURF,bg=$BG]${CAPR}"
RIGHT_R1="#[fg=$PINK,bg=$BG]${CAPL}#[fg=$CRUST,bg=$PINK]${I_CAL}  #[fg=$FG,bg=$SURF] #W #[fg=$SKY,bg=$SURF]${CAPL}#[fg=$CRUST,bg=$SKY]${I_THERMO}  #[fg=$FG,bg=$SURF] 🌤️ 29°C #[fg=$SAPPHIRE,bg=$SURF]${CAPL}#[fg=$CRUST,bg=$SAPPHIRE]${I_CLOCK}  #[fg=$FG,bg=$SURF] %Y/%m/%d %H:%M #[fg=$SURF,bg=$BG]${CAPR}"
FMT0="#[align=left bg=$BG]${LEFT_R1}#[list=on]#{W:#{T:@pw-fmt},#{T:@pw-cur}}#[nolist align=right]${RIGHT_R1}#[align=absolute-centre]${CLUSTER}"

# ── Row 2: quota trio (left, staged chrome) · net/cpu/mem/disk capsule (right).
#    Both are static demo chrome — this plugin has no live status token, so the
#    cockpit is pure set dressing and its readings are fixed, honest values. ──
ROW2_L="$(p_open "$PEACH" "$I_CLAUDE")$(p_text CLAUDE)$(p_badge "$YELLOW" 5H)$(p_text 40%%)$(p_badge "$MAROON" 7D)$(p_text 61%%)$(p_close)$(p_open "$LAVENDER" "$I_CODEX")$(p_text CODEX)$(p_badge "$MAUVE" 5H)$(p_text 65%%)$(p_badge "$PINK" 7D)$(p_text 12%%)$(p_close)$(p_open "$BLUE" "$I_GEMINI")$(p_text GEMINI)$(p_badge "$SKY" 5H)$(p_text 8%%)$(p_badge "$SAPPHIRE" 7D)$(p_text 3%%)$(p_close)"
ROW2_R="$(p_open "$TEAL" "$I_NET")$(p_text "↓17K ↑30K")$(p_ibadge "$GREEN" "$I_CPU")$(p_text "34%%")$(p_ibadge "$YELLOW" "$I_MEM")$(p_text "16.7/24G")$(p_ibadge "$PEACH" "$I_DISK")$(p_text "58%%")$(p_close)"
FMT1="#[align=left bg=$BG]${ROW2_L}#[align=right]${ROW2_R}"

# ── pane shell: byte-exact Starship clone (catppuccin_mocha), user = "dev" —
#    same segmented prompt as the rest of the plugin family. The convenience vars
#    (snap/log/rest) let the tape drive the restore flow without typing any
#    identity-bearing absolute path; CLAUDE_CONFIG_DIR points at a throwaway dir
#    so nothing can touch a real agent config. ──
cat > "$WORK/rc.sh" <<'RC'
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
_SEP=$(printf '\xee\x82\xb0'); _CAPL=$(printf '\xee\x82\xb6'); _CAPR=$(printf '\xee\x82\xb4')
_APPLE=$(printf '\xef\x85\xb9'); _BRANCH=$(printf '\xef\x90\x98')
_CLOCKG=$(printf '\xef\x90\xba'); _ARROW=$(printf '\xef\x90\xb2')
_SURF0='49;50;68'; _PEACH='250;179;135'; _GREEN='166;227;161'; _TEAL='148;226;213'
_BLUE='137;180;250'; _PINK='245;194;231'; _TEXT='205;214;244'; _MANTLE='24;24;37'; _BASE='30;30;46'
_p10line() {
  local b git=""
  if b=$(git branch --show-current 2>/dev/null) && [ -n "$b" ]; then
    git=$(printf '\033[38;2;%s;48;2;%sm %s %s ' "$_BASE" "$_GREEN" "$_BRANCH" "$b")
  fi
  printf '\033[38;2;%sm%s\033[38;2;%s;48;2;%sm%s dev \033[38;2;%s;48;2;%sm%s\033[38;2;%s;48;2;%sm …/%s \033[38;2;%s;48;2;%sm%s%s\033[38;2;%s;48;2;%sm%s\033[38;2;%s;48;2;%sm%s\033[38;2;%s;48;2;%sm%s\033[38;2;%s;48;2;%sm %s %s \033[0m\033[38;2;%sm%s\033[0m \n' \
    "$_SURF0" "$_CAPL" "$_TEXT" "$_SURF0" "$_APPLE" "$_SURF0" "$_PEACH" "$_SEP" \
    "$_MANTLE" "$_PEACH" "${PWD##*/}" "$_PEACH" "$_GREEN" "$_SEP" "$git" \
    "$_GREEN" "$_TEAL" "$_SEP" "$_TEAL" "$_BLUE" "$_SEP" "$_BLUE" "$_PINK" "$_SEP" \
    "$_MANTLE" "$_PINK" "$_CLOCKG" "$(date '+%I:%M %p')" "$_PINK" "$_CAPR"
}
PROMPT_COMMAND=_p10line
PS1='\[\033[1;38;2;166;227;161m\]'"$_ARROW"'\[\033[0m\] '
RC

# restore-flow convenience vars (appended so the Starship body stays verbatim)
cat >> "$WORK/rc.sh" <<RC
export CLAUDE_CONFIG_DIR="$WORK/fake-config"
snap='$SNAP'
log='$LOG'
rest='$PLUGIN/scripts/restore.sh'
RC

# ── staged sample project so the Starship prompt shows a …/demo-app + branch pill.
#    The console window runs the restore flow from inside it. ──
APP="$WORK/demo-app"
rm -rf "$APP"; mkdir -p "$APP/src"
printf '# demo-app\n\nA tiny sample project.\n' > "$APP/README.md"
printf 'flask\npytest\n' > "$APP/requirements.txt"
git -C "$APP" init -q -b main
git -C "$APP" -c user.name=dev -c user.email=dev@example.com add -A
git -C "$APP" -c user.name=dev -c user.email=dev@example.com commit -qm "initial commit"

# ── base theme (static parts; the format rows are set after server start) ──
cat > "$WORK/theme.conf" <<'CONF'
set -g default-terminal "tmux-256color"
set -as terminal-overrides ",xterm-256color:Tc"
set -g mouse on
setw -g automatic-rename off
set -g escape-time 0
set -g status 2
set -g status-interval 2
set -g status-style "bg=#1E1E1E,fg=#cdd6f4"
set -g status-left-length 30
set -g status-right-length 200
set -g window-status-separator ''
set -g pane-border-status top
set -g pane-border-format '#[align=centre]#{?pane_active,#[reverse],}#{pane_index}#[default] #{pane_current_command}'
set -g pane-border-style 'fg=#45475a'
set -g pane-active-border-style 'fg=#fab387,bold'
set -g message-style 'bg=#f9e2af,fg=#11111b,bold'
CONF

# ── isolated server: window 0 (console) runs the clean Starship shell EXPLICITLY,
#    from inside the staged demo-app (a session's first window is created before
#    default-command applies — classic prompt leak). ──
"$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null
sleep 0.3
"$TMUX_BIN" -L "$SOCK" -f "$WORK/theme.conf" new-session -d -s demo -x 118 -y 30 -n console -c "$APP" "bash --rcfile $WORK/rc.sh -i"
"$TMUX_BIN" -L "$SOCK" set -g default-command "bash --rcfile $WORK/rc.sh -i"

# cockpit rows (composed above with byte-escape glyphs)
"$TMUX_BIN" -L "$SOCK" set -g @pw-fmt "$WINF"
"$TMUX_BIN" -L "$SOCK" set -g @pw-cur "$WINCUR"
"$TMUX_BIN" -L "$SOCK" set -g 'status-format[0]' "$FMT0"
"$TMUX_BIN" -L "$SOCK" set -g 'status-format[1]' "$FMT1"

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
