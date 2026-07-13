# tmux-agent-resume demo — replay each AI CLI to its exact session after a crash.
# Fully self-contained: docs/demo-setup.sh stages an anonymous cockpit shell and
# a catppuccin-mocha ISOLATED tmux server (socket ar-demo). It is a DRY RUN:
# three bare-shell windows (claude / codex / kimi) stand in for restored agent
# panes, a fixed snapshot TSV maps them to resume commands (all fake, under
# /Users/demo/*), and restore.sh runs with AGENT_RESUME_DRYRUN=1 — it only LOGS
# what it WOULD type after the per-CLI allowlist. Nothing is sent, no CLI is
# launched, and CLAUDE_CONFIG_DIR points at a throwaway temp dir.
# Re-record from the repo root with:  vhs docs/demo.tape
Output "docs/demo.gif"
Require tmux

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 1600
Set Height 760
Set Padding 20
Set TypingSpeed 35ms

Hide
Type "bash docs/demo-setup.sh"
Enter
Sleep 3s
Type "clear; tmux -L ar-demo attach -t demo"
Enter
Sleep 2s
Show

Sleep 1500ms
Type "# tmux-agent-resume replays each AI CLI to its exact session after a crash."
Enter
Sleep 1800ms
Type "# the snapshot it recorded on save — pane, tool, mode, cwd, resume command:"
Enter
Type `column -t -s $'\t' "$snap"`
Enter
Sleep 4s

Type "# dry run: log what it WOULD type — sends nothing, launches no CLI."
Enter
Type `AGENT_RESUME_DRYRUN=1 AGENT_RESUME_SNAP_FILE="$snap" AGENT_RESUME_LOG="$log" "$rest"`
Enter
Sleep 1s
Type `cat "$log"`
Enter
Sleep 5s

Hide
Ctrl+B
Type "d"
Sleep 400ms
Type "tmux -L ar-demo kill-server"
Enter
Sleep 500ms
