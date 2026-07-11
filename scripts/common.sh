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
