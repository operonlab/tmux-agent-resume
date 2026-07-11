# Per-CLI reverse-lookup matrix

How `snapshot.sh` figures out, for each supported AI CLI, **which session is
live in a pane** and **the exact command that resumes it**, plus the quirks that
make each one hard. This is the battle-tested core (8 CLIs, live on macOS,
2026-07). `gemini` was dropped when it was discontinued on 2026-06-18.

The process name is not trustworthy: `kimi` renames itself to `kimi-code`,
`hermes` runs as `python3`, `qwen` runs as `node`. Detection therefore combines
a basename allowlist with argv path matching (see the `awk` block in
`snapshot.sh`).

| CLI | reverse-lookup method | resume command | cwd binding | verified version |
|-----|----------------------|----------------|-------------|------------------|
| **claude** | `$MAP_DIR/<pane_id>` written by the SessionStart hook = the current session id (exact). Stale-map guard: map epoch must be ≥ agent start time. | `claude … --resume <uuid>` | **hard** — transcript slug is bound to the session's starting cwd (taken from the map, not `pane_current_path`) | Claude Code |
| **codex** | `lsof` the open `rollout-*-<uuid>.jsonl` the process holds | `codex resume <uuid>` | none | 0.144.1 |
| **agy** | `lsof` the `brain/<uuid>` dir an active conversation holds (fresh agents hold none; multiple = picker → keep argv) | `agy --conversation <uuid>` | none | (antigravity) |
| **copilot** | log filename embeds the pid (`process-<epochms>-<pid>.log`); last `Workspace initialized` id | `copilot --resume=<uuid>` | none (chdirs back itself) | 1.0.70 |
| **opencode** | argv `-s ses_xxx` → replay as-is; else, **single instance only**, newest `session.id` from the shared log | `opencode -s ses_xxx` | none | 1.17.18 |
| **kimi** | argv destroyed by self-rename → rebuilt; `session_index.jsonl` filtered by `workDir == cwd`, newest `state.json` | `kimi -r session_<uuid>` | **hard** — resume rejects a wrong dir | 0.23.5 |
| **hermes** | argv `--resume` replays; else id timestamp `YYYYMMDD_HHMMSS_<hex>` ≈ process start, reverse-looked-up from `agent.log` | `hermes … --resume <id>` | none (chdirs back itself) | (hermes) |
| **qwen** | official runtime sidecar `<sid>.runtime.json` `{pid,session_id,work_dir}`; pid verified against a qwen on this pane tty | `qwen --resume <sid>` | **hard** — resume rejects a wrong `work_dir` | 0.19.8 |

## Fallback: argv replay (`mode=argv`)

When no live session id can be resolved, the pane's original argv is replayed
verbatim. This is honest but lossy:

- a **fresh** agent started without a session id resumes as a brand-new session
  (context lost);
- an argv that carried a `--resume <id>` which has since gone stale (e.g. after
  `/clear`) replays that stale id.

Replaying the argv at least preserves the process's lineage; once the SessionStart
map catches up, the exact-session path takes over.

## Known limitations

- **kimi, same cwd, multiple instances** — indistinguishable. The snapshot takes
  the most recently active session for that `workDir`; a second kimi in the same
  directory may resume into the wrong one.
- **opencode, fresh, multiple instances** — the shared log has no per-pid
  attribution, so a fresh opencode (no `-s` in argv) is only resolved when it is
  the **single** opencode process on the machine; otherwise argv is kept.
- **claude** — the resume needs both the session's cwd (the transcript project
  slug is derived from it) and the transcript file to still exist; if either is
  gone the row falls back to argv (logged as a warning).
- **gemini** — discontinued 2026-06-18; not supported.
- **cwd with spaces / shell metacharacters** — restore skips the row rather than
  risk a quoting bug (see the allowlist in `scripts/validate.sh`).

## The injection allowlist

Every payload restore is about to type is first matched against a per-CLI
anchored regex (`scripts/validate.sh`). The invariant enforced is: the payload
is exactly `[cd <metachar-free-abs-path> && ] <tool> <safe flags/values>` with
zero shell metacharacters. A payload that does not fit is dropped and logged,
never sent. See the header of `scripts/validate.sh` for the full threat model.
