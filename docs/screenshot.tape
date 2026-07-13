# tmux-agent-resume — hero screenshot: the restore --dry-run "would-send" list.
#   Record with vhs (https://github.com/charmbracelet/vhs):
#     cd tmux-agent-resume && vhs docs/screenshot.tape
#
# Fully isolated and safe to run:
#   - throwaway tmux server (-L shot-agent-resume -f /dev/null), killed at the end;
#     it never touches your real tmux;
#   - DRY RUN only: restore.sh with AGENT_RESUME_DRYRUN=1 *logs* what it would type
#     and sends zero keystrokes; no AI CLI is ever launched;
#   - eight bare shells stand in for restored agent panes;
#   - the resume commands are fake, but each one is assembled by the real
#     restore.sh and clears the real per-CLI allowlist (scripts/validate.sh).
# The visible frame is a clean table rendered straight from restore.sh's own log.

Output "/tmp/tmux-agent-resume-hero.gif"
Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 22
Set Width 1600
Set Height 560
Set Padding 30
Set TypingSpeed 1ms

Hide
Type `PS1=''` Enter
Type `W=$(mktemp -d /tmp/tmux-agent-resume-shot.XXXXXX); SOCK=shot-agent-resume; SNAP="$W/snap.tsv"; LOG="$W/ar.log"; TABLE="$W/table.txt"` Enter
Type `SD="${TMUX_TMPDIR:-/tmp/tmux-$(id -u)}"; tmux -L "$SOCK" -f /dev/null kill-server 2>/dev/null; rm -f "$SD/$SOCK"` Enter
Type `tmux -L "$SOCK" -f /dev/null new-session -d -s d -n claude 'bash --norc -i'` Enter
Type `for w in codex agy copilot opencode kimi hermes qwen; do tmux -L "$SOCK" -f /dev/null new-window -d -n "$w" 'bash --norc -i'; done` Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' %0 claude   map     /work/webapp 'claude --resume 3f2a1b4c-5d6e-7f80-9a1b-2c3d4e5f6071'  >  "$SNAP"` Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' %1 codex    lsof    /work/api    'codex resume a1b2c3d4-e5f6-7a80-9b1c-2d3e4f5a6b7c'       >> "$SNAP"` Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' %2 agy      lsof    /work/ui     'agy --conversation 5e4d3c2b-1a09-4f8e-7d6c-5b4a39281706' >> "$SNAP"` Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' %3 copilot  log     /work/cli    'copilot --resume=7c6d5e4f-3a2b-1c09-8d7e-6f5a4b3c2d1e'   >> "$SNAP"` Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' %4 opencode log     /work/db     'opencode -s ses_8a7b6c5d4e3f2109'                        >> "$SNAP"` Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' %5 kimi     index   /work/infra  'kimi -r session_9f8e7d6c-5b4a-3210-fedc-ba9876543210'    >> "$SNAP"` Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' %6 hermes   log     /work/etl    'hermes --resume 20260712_143022_a1b2c3'                  >> "$SNAP"` Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' %7 qwen     runtime /work/ml     'qwen --resume 4b3a2c1d-0e9f-8a7b-6c5d-4e3f2a1b0c9d'      >> "$SNAP"` Enter
Type `SP=$(tmux -L "$SOCK" -f /dev/null display -p '#{socket_path}'); PP=$(tmux -L "$SOCK" -f /dev/null display -p '#{pid}')` Enter
Type `TMUX="$SP,$PP,0" AGENT_RESUME_DRYRUN=1 AGENT_RESUME_SNAP_FILE="$SNAP" AGENT_RESUME_LOG="$LOG" ./scripts/restore.sh` Enter
Type `tmux -L "$SOCK" -f /dev/null kill-server 2>/dev/null; rm -f "$SD/$SOCK"` Enter
Type `awk 'BEGIN{printf "\n  \033[1;36mtmux-agent-resume\033[0m \033[2m—\033[0m replays each AI agent back to its \033[1mexact session\033[0m after a tmux restart\n  \033[2mrestore --dry-run · what it would type into every recovered pane — nothing is sent\033[0m\n\n  \033[2m%-3s %-5s %-9s %-8s %s\033[0m\n","OK","PANE","AGENT","VIA","RESUME COMMAND IT WOULD TYPE"; printf "  \033[2m─── ───── ───────── ──────── ─────────────────────────────────────────────────────\033[0m\n"} /would send:/{s=index($0,"would send: ");cmd=substr($0,s+12);left=substr($0,1,s-1);match(left,/DRYRUN [^ ]+/);coord=substr(left,RSTART+7,RLENGTH-7);match(left,/\([^)]+\)/);tv=substr(left,RSTART+1,RLENGTH-2);split(tv,b,"/");printf "  \033[32m✓\033[0m   %-5s \033[1m%-9s\033[0m \033[2m%-8s\033[0m %s\n",coord,b[1],b[2],cmd} /done sent=/{match($0,/sent=[0-9]+/);sent=substr($0,RSTART+5,RLENGTH-5);match($0,/skipped=[0-9]+/);sk=substr($0,RSTART+8,RLENGTH-8);printf "\n  \033[32m✓ %s panes passed the per-CLI allowlist\033[0m  \033[2m·\033[0m  \033[2m%s skipped · 0 keystrokes sent\033[0m\n\n",sent,sk}' "$LOG" > "$TABLE"` Enter
Type `clear; cat "$TABLE"` Enter
Sleep 700ms
Show
Sleep 200ms
Screenshot "docs/screenshot.png"
Sleep 200ms
Hide
Type `rm -rf "$W"; tmux -L "$SOCK" -f /dev/null kill-server 2>/dev/null; rm -f "$SD/$SOCK"` Enter
Sleep 200ms
