# tmux-agent-resume

> 中文說明請見 [docs/zh.md](docs/zh.md)

![platform: macOS](https://img.shields.io/badge/platform-macOS-black)
![tmux ≥ 1.9](https://img.shields.io/badge/tmux-%E2%89%A5%201.9-1BB91F)
![requires tmux-resurrect](https://img.shields.io/badge/requires-tmux--resurrect-blue)

**macOS-only (v1).** The reverse-lookup relies on BSD tool output — `stat -f`,
`date -j`, BSD `ps`, and `lsof` — so this release targets macOS. Linux support
is not there yet; CI runs shellcheck on Linux but the behaviour is only asserted
on macOS. Tested on **tmux next-3.8** (HEAD-9180356), 2026-07.

---

## 1. What is this?

You have an AI coding assistant running in a tmux pane — Claude Code, Codex,
Copilot, and friends — in the middle of a real conversation. Then tmux crashes,
or you reboot, or a watchdog restarts the server. Normally that conversation is
gone: the pane comes back empty, or the CLI relaunches as a blank new session
and everything it knew is lost.

**tmux-agent-resume brings the conversation back.** It works alongside
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) (which already
restores your windows and panes). Just before resurrect saves, this plugin
records which AI CLI is in each pane and how to reattach it to its *exact*
session. Just after resurrect restores, it types the right resume command into
each pane — so your agents pick up where they left off, not from zero.

It supports **8 CLIs**: Claude Code, Codex, Antigravity (`agy`), Copilot,
OpenCode, Kimi, Hermes, and Qwen. Each one hides its session id in a different
place; the plugin knows where to look for each (see
[docs/per-cli-matrix.md](docs/per-cli-matrix.md)).

---

## 2. Quickstart

**Prerequisites:** macOS, **tmux 1.9 or newer** (`tmux -V` to check), and
**tmux-resurrect installed** (it is a peer dependency — this plugin extends it).

Everywhere below, **`prefix`** means your tmux prefix key — **`Ctrl-b`** unless
you changed it. So "press `prefix` then `r`" means: hold Ctrl, tap `b`, let go,
then tap `r`.

### Path A — I don't use a plugin manager (works right now)

Copy-paste these three steps:

```sh
# 1. Download the plugin somewhere permanent
git clone https://github.com/joneshong/tmux-agent-resume ~/.tmux/plugins/tmux-agent-resume

# 2. Tell tmux to load it — appends one line to your config
echo "run-shell ~/.tmux/plugins/tmux-agent-resume/agent-resume.tmux" >> ~/.tmux.conf

# 3. Reload tmux config (inside tmux: press prefix then r, or run this)
tmux source-file ~/.tmux.conf
```

That is enough for **all CLIs except a small extra step for Claude Code** (see
§3 below).

### Path B — I use TPM (the tmux plugin manager)

**If you don't have TPM yet**, install it first:

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

…and make sure the very last line of your `~/.tmux.conf` is:

```tmux
run '~/.tmux/plugins/tpm/tpm'
```

**Then add both plugins.** Put these lines in `~/.tmux.conf` *above* the `run`
line (resurrect first — we chain onto it):

```tmux
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'joneshong/tmux-agent-resume'
```

Reload your config (`prefix` `r`), then press `prefix` `I` (capital i) to have
TPM download them. Done.

---

## 3. One extra step for Claude Code (optional but recommended)

Claude Code is the only CLI whose *current* session id can't be read back from
the outside — it has to be captured live via a SessionStart hook. The plugin
ships that hook and an installer for it:

```sh
bash ~/.tmux/plugins/tmux-agent-resume/hooks/install-claude-hook.sh
```

This idempotently adds one entry to `~/.claude/settings.json` (it preserves any
hooks you already have). To point it at a different config dir, set
`CLAUDE_CONFIG_DIR`. To undo it:

```sh
bash ~/.tmux/plugins/tmux-agent-resume/hooks/install-claude-hook.sh uninstall
```

**Honest degrade:** if you skip this, Claude Code still resumes — just in
*argv mode*: the plugin re-runs the pane's original command. A session that
started fresh (no id in its argv) comes back as a new session; the hook is what
makes Claude reattach to the exact same conversation. Every other CLI works
fully without any hook.

---

## 4. Demo

*Demo GIF coming soon.*

---

## 5. Options

Set any of these in `~/.tmux.conf` **before** the plugin loads (i.e. above the
`run '.../tpm'` line, or above the `run-shell` line):

| Option | Default | What it does |
|--------|---------|--------------|
| `@agent-resume-tools` | `claude codex agy copilot opencode kimi hermes qwen` | Space-separated allowlist of CLIs to snapshot/resume. Remove any you don't want touched. |
| `@agent-resume-dry-run` | `0` | `1` = log what *would* be typed, send nothing. Great for a first look. |
| `@agent-resume-log` | `$TMUX_TMPDIR/tmux-agent-resume-<uid>/agent-resume.log` | Where the plugin writes its activity log. |
| `@agent-resume-snapshot-file` | `~/.tmux/resurrect/agents.tsv` | The sidecar TSV of pane → resume-command, saved next to resurrect's own files. |
| `@agent-resume-map-dir` | `$TMUX_TMPDIR/tmux-agent-resume-<uid>/claude-map` | Where the Claude SessionStart hook writes its pane → session-id map. If you override this, the hook picks it up automatically inside tmux. |

Example:

```tmux
set -g @agent-resume-dry-run 1
set -g @agent-resume-tools 'claude codex qwen'
```

> **Security note.** By design, restore **types resume commands into your panes
> and presses Enter** — that is the whole point. Before anything is typed, every
> command is checked against a strict per-CLI allowlist (`scripts/validate.sh`):
> it must be exactly `[cd <safe-path> &&] <tool> <safe flags>` with no shell
> metacharacters, or it is dropped and logged. Start with `@agent-resume-dry-run 1`
> if you want to watch it first.

---

## 6. Uninstall

```sh
bash ~/.tmux/plugins/tmux-agent-resume/scripts/teardown.sh   # unchain our resurrect hooks (keeps yours)
bash ~/.tmux/plugins/tmux-agent-resume/hooks/install-claude-hook.sh uninstall   # remove the Claude hook
```

Then delete the `@plugin`/`run-shell` lines from `~/.tmux.conf` and remove the
clone. Your own resurrect hook values (if you had any) are preserved.

---

## 7. Troubleshooting / FAQ

**Nothing resumed after a restart — where do I look first?**
Read the log: `cat "$(tmux show-option -gqv @agent-resume-log)"` (or the default
path in the Options table). Every skip says why — busy pane, cwd rejected,
allowlist miss, no snapshot. Set `@agent-resume-dry-run 1` and trigger a
resurrect save+restore to see exactly what it *would* do.

**It skipped a pane that was "busy".** That is intentional. If a pane already
has a process running after restore (resurrect relaunched something, or you took
it over), the plugin will not type over it. It only resumes panes sitting at a
bare shell prompt.

**My Claude session came back as a brand-new conversation.** You almost
certainly skipped the SessionStart hook in §3 — without it, Claude can only be
replayed in argv mode. Install the hook and the *next* crash will reattach to
the exact session.

**Two Kimi sessions in the same folder got mixed up.** Known limitation: Kimi
renames its own process and same-directory instances are indistinguishable from
the outside. The plugin picks the most recently active one. See
[docs/per-cli-matrix.md](docs/per-cli-matrix.md#known-limitations).

**I got "tmux-resurrect not found".** This plugin has no effect on its own — it
chains onto resurrect's save/restore hooks. Install
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and reload.

**Does this run on Linux?** Not in v1. The session reverse-lookup depends on
BSD/macOS tool output. It will not error loudly, but it is unsupported and
unasserted there.

---

## 8. How it works (one paragraph)

`agent-resume.tmux` appends two segments onto tmux-resurrect's
`@resurrect-hook-post-save-all` and `@resurrect-hook-post-restore-all` (chaining,
never clobbering). On save, `scripts/snapshot.sh` walks every pane, identifies
the AI CLI, resolves its live session id, and writes a
`coord ⇥ tool ⇥ mode ⇥ cwd ⇥ resume_cmd` TSV. On restore, `scripts/restore.sh`
reads that TSV and — for panes still at a shell prompt, after allowlist
validation — types the resume command. Details per CLI:
[docs/per-cli-matrix.md](docs/per-cli-matrix.md).

## 9. Requirements & version notes

- **tmux ≥ 1.9.** That is tmux-resurrect's own floor; the tmux features this
  plugin uses are older — `send-keys -l` (tmux 1.7), free-form `@` user options
  (tmux 1.8), `pane_current_command` / `pane_current_path` (tmux 1.8 / 2.1).
  Verified against the official tmux `CHANGES`. Developed and tested on
  **tmux next-3.8**.
- **tmux-resurrect** — peer dependency, must be installed.
- **jq** — only needed by the optional Claude hook installer.
- **macOS** — see the banner at the top.

## Credits / License

The 8-CLI reverse-lookup logic was hardened live across all eight CLIs on macOS
in 2026-07. Built to complement
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and
[tmux-continuum](https://github.com/tmux-plugins/tmux-continuum).

MIT — see [LICENSE](LICENSE).
