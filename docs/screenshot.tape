# tmux-agent-resume — hero screenshot: the family two-row pill cockpit plus the
# restore snapshot table and the dry-run "would type" log, the plugin's money shot.
#   Record from the repo root with:  cd tmux-agent-resume && vhs docs/screenshot.tape
#
# Fully isolated & anonymous: docs/demo-setup.sh stages an identity-free
# Starship-clone shell (user "dev") + the family catppuccin-mocha cockpit on an
# ISOLATED tmux server (socket ar-demo) — your real tmux is never touched.
# DRY RUN only: restore.sh runs with AGENT_RESUME_DRYRUN=1, so it only LOGS what
# it WOULD type after the per-CLI allowlist — nothing is sent, no AI CLI launches.
Output "/tmp/tmux-agent-resume-hero.gif"
Require tmux

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 2496
Set Height 620
Set Padding 20
Set TypingSpeed 1ms

Hide
Type "bash docs/demo-setup.sh"
Enter
Sleep 3s
Type "clear; tmux -L ar-demo attach -t demo"
Enter
Sleep 2s
Type "# tmux-agent-resume replays each AI CLI to its exact session after a crash."
Enter
Type "# the snapshot it recorded on save — pane, tool, mode, cwd, resume command:"
Enter
Type `column -t -s $'\t' "$snap"`
Enter
Sleep 500ms
Type "# dry run: log what it WOULD type — sends nothing, launches no CLI."
Enter
Type `AGENT_RESUME_DRYRUN=1 AGENT_RESUME_SNAP_FILE="$snap" AGENT_RESUME_LOG="$log" "$rest"`
Enter
Sleep 400ms
Type `cat "$log"`
Enter
Sleep 900ms
Show
Sleep 300ms
Screenshot "docs/screenshot.png"
Sleep 200ms

Hide
Ctrl+B
Type "d"
Sleep 400ms
Type "tmux -L ar-demo kill-server"
Enter
Sleep 400ms
