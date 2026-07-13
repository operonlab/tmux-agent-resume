# tmux-agent-resume demo — recorded with vhs (https://github.com/charmbracelet/vhs)
#   cd tmux-agent-resume && vhs docs/demo.tape
#
# Runs in a throwaway, isolated tmux server (-L vhsdemo-agent-resume,
# -f /dev/null) so it never touches your real tmux. It is a DRY RUN: three
# bare-shell windows stand in for restored agent panes, a fake snapshot TSV
# maps them to resume commands, and restore.sh (with AGENT_RESUME_DRYRUN=1)
# logs exactly what it WOULD type after passing the per-CLI allowlist —
# nothing is sent and no CLI is launched.

Output "docs/demo.gif"
Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 660
Set Padding 12
Set TypingSpeed 40ms

Hide
Type `tmux -L vhsdemo-agent-resume -f /dev/null new-session -d -s demo -n console 'bash --norc -i'`
Enter
Type `tmux -L vhsdemo-agent-resume attach -t demo`
Enter
Sleep 800ms
Type `PS1='ar> '`
Enter
Type `tmux -L vhsdemo-agent-resume set -g status-right ''`
Enter
Type `P1=$(tmux -L vhsdemo-agent-resume new-window -dP -F '#{pane_id}' -n claude 'bash --norc -i')`
Enter
Type `P2=$(tmux -L vhsdemo-agent-resume new-window -dP -F '#{pane_id}' -n codex 'bash --norc -i')`
Enter
Type `P3=$(tmux -L vhsdemo-agent-resume new-window -dP -F '#{pane_id}' -n kimi 'bash --norc -i')`
Enter
Type `SNAP=/tmp/vhsdemo-ar-snap.tsv; LOG=/tmp/vhsdemo-ar.log; rm -f "$SNAP" "$LOG"`
Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' "$P1" claude hook /Users/demo/webapp 'claude --resume 3f2a1b4c-5d6e-7f80-9a1b-2c3d4e5f6071' > "$SNAP"`
Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' "$P2" codex argv /Users/demo/api 'codex resume a1b2c3d4-e5f6-7a80-9b1c-2d3e4f5a6b7c' >> "$SNAP"`
Enter
Type `printf '%s\t%s\t%s\t%s\t%s\n' "$P3" kimi argv /Users/demo/infra 'kimi -r session_9f8e7d6c-5b4a-3210-fedc-ba9876543210' >> "$SNAP"`
Enter
Type "clear"
Enter
Sleep 400ms
Show
Type "# tmux-agent-resume replays each AI CLI to its exact session after a crash."
Enter
Type "# the snapshot it recorded on save (pane, tool, mode, cwd, resume command):"
Enter
Type `column -t -s $'\t' "$SNAP"`
Enter
Sleep 3.5s
Type "# dry run: log what it WOULD type — sends nothing, launches no CLI."
Enter
Type `AGENT_RESUME_DRYRUN=1 AGENT_RESUME_SNAP_FILE="$SNAP" AGENT_RESUME_LOG="$LOG" ./scripts/restore.sh`
Enter
Sleep 800ms
Type `cat "$LOG"`
Enter
Sleep 4.5s
Hide
Type `rm -f "$SNAP" "$LOG"`
Enter
Type `tmux -L vhsdemo-agent-resume kill-server`
Enter
Sleep 500ms
