#!/usr/bin/env bash
# common.sh — shared config + cache helpers for tmux-agent-resume.
# Sourced by scripts/snapshot.sh and scripts/restore.sh. Defines functions
# only; sets no shell options so it never pollutes the caller (both callers are
# tmux-resurrect hooks and must not run under `set -e`).
#
# Config precedence for every option:  environment variable > tmux option > default.
# The env layer exists so the test harness can pin an isolated socket / temp
# paths; day to day, users set the @agent-resume-* tmux options.

# Per-user private cache/state root. Everything runtime (log, lock, claude map,
# snapshot scratch) lives here. Refuses a pre-planted symlink (a classic
# /tmp squat) and creates the dir 0700. Echoes the path, or nothing on failure.
ar_cache_dir() {
    local base dir
    base="${TMUX_TMPDIR:-/tmp}"
    dir="$base/tmux-agent-resume-$(id -u)"
    # never follow a symlink planted where our dir should be
    [ -L "$dir" ] && return 1
    mkdir -p "$dir" 2>/dev/null || true
    chmod 700 "$dir" 2>/dev/null || true
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
    printf '%s' "$dir"
}

# ar_opt <ENV_VAR> <@tmux-option> <default>
# Resolve one configurable value. Env var wins (for tests), then the tmux
# user option, then the built-in default.
ar_opt() {
    local ev="$1" opt="$2" def="$3" v
    v="${!ev:-}"
    if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
    v="$(tmux show-option -gqv "$opt" 2>/dev/null || true)"
    if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
    printf '%s' "$def"
}

# ar_tool_enabled <tool> <space-separated-enabled-list>
# 0 if the tool is in the enabled set, 1 otherwise.
ar_tool_enabled() {
    case " $2 " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# --- portable primitives (macOS BSD vs Linux GNU) --------------------------
# The reverse-lookups in snapshot.sh use tools whose flags differ by platform;
# on the wrong platform they emit nothing and the resume id is silently dropped.
# Branch on the OS (AR_OS overridable for tests) so both work. Callers must LOG
# loudly when a probe still comes back empty rather than degrade in silence.

# ar_mtime <path> -> epoch mtime, or 0 on any failure (never empty).
ar_mtime() {
    local m
    if [ "${AR_OS:-$(uname)}" = Darwin ]; then m="$(stat -f %m "$1" 2>/dev/null)"
    else m="$(stat -c %Y "$1" 2>/dev/null)"; fi
    printf '%s' "${m:-0}"
}

# ar_epoch_from_stamp <YYYYMMDD_HHMMSS> -> epoch, empty on failure.
ar_epoch_from_stamp() {
    local s="$1" d t
    if [ "${AR_OS:-$(uname)}" = Darwin ]; then
        date -j -f '%Y%m%d_%H%M%S' "$s" +%s 2>/dev/null
    else
        d="${s%_*}"; t="${s#*_}"   # 20260711 / 120000 -> GNU date wants ISO
        date -d "${d:0:4}-${d:4:2}-${d:6:2} ${t:0:2}:${t:2:2}:${t:4:2}" +%s 2>/dev/null
    fi
}

# ar_proc_cwd <pid> -> working directory of the process, empty on failure.
ar_proc_cwd() {
    if [ "${AR_OS:-$(uname)}" = Darwin ]; then
        lsof -a -d cwd -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
    else
        readlink "/proc/$1/cwd" 2>/dev/null
    fi
}

# --- snapshot rotation (mirrors tmux-resurrect save_all/remove_old_backups) -
# A single agents.tsv.prev meant one poisoned snapshot plus its successor
# evicted the last good state. Instead keep timestamped copies: skip the write
# when nothing changed, repoint the `last` symlink (SNAP_FILE) at the newest,
# keep the newest AGENT_RESUME_KEEP (>=5) and prune those beyond it older than
# AGENT_RESUME_KEEP_DAYS (30).

# ar_files_differ <a> <b> : true (0) when they differ or <b> is absent.
ar_files_differ() {
    ! cmp -s "$1" "$2"
}

# ar_rotate_snapshots <snap_file> <tmpfile>
# <snap_file> is the `last` symlink path; timestamped copies live beside it.
ar_rotate_snapshots() {
    local snap="$1" tmp="$2" dir base prefix ext keep days ts target i old f
    dir="$(dirname "$snap")"; base="$(basename "$snap")"
    prefix="${base%.*}"; ext="${base##*.}"
    keep="${AGENT_RESUME_KEEP:-5}"; days="${AGENT_RESUME_KEEP_DAYS:-30}"
    mkdir -p "$dir" 2>/dev/null || true
    # dedup: identical to the current snapshot -> drop the new write
    if [ -f "$snap" ] && ! ar_files_differ "$tmp" "$snap"; then
        rm -f "$tmp" 2>/dev/null; return 0
    fi
    ts="$(date +%Y%m%dT%H%M%S)"; target="$dir/${prefix}.${ts}.${ext}"; i=0
    while [ -e "$target" ]; do i=$(( i + 1 )); target="$dir/${prefix}.${ts}_${i}.${ext}"; done
    mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp"; return 1; }
    ln -sfn "$(basename "$target")" "$snap" 2>/dev/null \
        || ln -sf "$(basename "$target")" "$snap" 2>/dev/null
    # prune: beyond the newest $keep, delete those older than $days days
    old="$(ls -t "$dir/${prefix}."*."${ext}" 2>/dev/null | tail -n +"$(( keep + 1 ))")"
    [ -n "$old" ] && printf '%s\n' "$old" | while IFS= read -r f; do
        [ -n "$f" ] && find "$f" -type f -mtime "+${days}" -exec rm -f {} \; 2>/dev/null
    done
    return 0
}
