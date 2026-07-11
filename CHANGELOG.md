# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-11

First release. macOS-only. A sidecar for
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) that reattaches
AI CLI conversations to their exact sessions after a tmux crash/restart.

### Requirements

- **tmux ≥ 1.9** — tmux-resurrect's own floor. The tmux features used here are
  older: `send-keys -l` (1.7), free-form `@` user options (1.8),
  `pane_current_command` / `pane_current_path` (1.8 / 2.1), all confirmed
  against the official tmux `CHANGES`. Developed and tested on **tmux next-3.8**
  (HEAD-9180356).
- **tmux-resurrect** installed (peer dependency).
- **macOS** — reverse-lookup depends on BSD `stat -f` / `date -j` / `ps` / `lsof`.
- **jq** — only for the optional Claude hook installer.

### Added

- 8-CLI session reverse-lookup and resume: Claude Code, Codex, Antigravity
  (`agy`), Copilot, OpenCode, Kimi, Hermes, Qwen. `gemini` removed (discontinued
  2026-06-18). Per-CLI method, resume command, cwd binding, and known limits are
  documented in `docs/per-cli-matrix.md`.
- `agent-resume.tmux` entry point that **chains** onto
  `@resurrect-hook-post-save-all` / `@resurrect-hook-post-restore-all` without
  clobbering an existing value, idempotent across reloads; warns (non-fatal) if
  tmux-resurrect is not found.
- `scripts/snapshot.sh` (post-save-all) and `scripts/restore.sh`
  (post-restore-all), generalized from a battle-tested implementation: private
  cache dir, atomic mkdir lock, busy-pane guard, cd-prefix, `timeout`/`gtimeout`
  fallback for stock macOS.
- `scripts/validate.sh` — per-CLI anchored allowlist. Restore never types a
  payload that is not exactly `[cd <safe-path> &&] <tool> <safe flags>`;
  non-matching payloads are dropped and logged (injection hardening).
- `hooks/claude-session-map.sh` — Claude SessionStart hook, and
  `hooks/install-claude-hook.sh` — idempotent installer/uninstaller that only
  ever touches `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` and preserves existing hooks.
- Options: `@agent-resume-tools`, `@agent-resume-dry-run`, `@agent-resume-log`,
  `@agent-resume-snapshot-file`, `@agent-resume-map-dir` (each overridable by the
  matching `AGENT_RESUME_*` env var for testing).
- `scripts/teardown.sh` — unchains only our hook segment, preserving the user's.
- Tests on an isolated tmux socket: `tests/smoke.sh` (hook chain, empty
  snapshot, busy-skip, injection reject, dry-run, teardown),
  `tests/validate_test.sh` (allowlist unit tests incl. ≥6 injection samples),
  `tests/hook_install_test.sh` (installer idempotency/chaining/uninstall).
- `.github/workflows/ci.yml` — shellcheck + portable unit tests on Linux, full
  smoke on macOS.

[0.1.0]: https://github.com/joneshong/tmux-agent-resume/releases/tag/v0.1.0
