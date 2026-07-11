#!/usr/bin/env bash
# validate.sh — per-CLI resume-command allowlist (injection hardening).
#
# THREAT MODEL: restore.sh types a reconstructed resume command into a pane with
# `send-keys` followed by Enter. That is a shell command line — any unquoted
# shell metacharacter in it would execute. The snapshot side already extracts
# ids with narrow regexes, but the .tsv on disk is an untrusted boundary (a
# tampered row, a hostile session id embedded in a filename, a crafted argv).
# So restore.sh runs EVERY assembled payload through ar_validate first; a
# payload that does not match its tool's anchored template is dropped, logged,
# and never sent. Fail-closed: unknown tool or non-match => reject.
#
# INVARIANT the templates enforce: the payload is exactly
#     [cd <metachar-free-absolute-path> && ] <tool> <safe flags/values>
# with ZERO shell metacharacters (no ; & | $ ` ( ) < > newline, no quotes).
# Values are restricted to a metachar-free token class, so even a hostile id
# cannot break out of the argument position.
#
# This generalizes the SPEC's illustrative claude template
#   ^cd [^;&|]+ && claude( --[A-Za-z-]+)*( --resume <uuid>)?$
# into one anchored regex per CLI (below), and is intentionally NARROW: a
# command that does not fit the template is skipped rather than sent.
#
# Standalone (for unit tests):  validate.sh <tool> '<command>'
#   exit 0 = allowed, exit 1 = rejected.

# --- regex fragments (POSIX ERE; BSD/macOS bash 3.2 `[[ =~ ]]` compatible) ---
AR_UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
# value token: letters/digits and a curated set of path/id-safe punctuation.
# Deliberately excludes every shell metacharacter and all whitespace.
AR_TOK='[A-Za-z0-9._/@:,+%=_~-]+'
# absolute cwd inside the optional `cd ... &&` prefix. restore.sh pre-validates
# cwd to this same character set before %q (which is then a no-op), so what
# reaches here is metachar-free.
AR_CWD='/[A-Za-z0-9._/@:,+_~-]*'
# a single flag: one or two dashes, then a name, optionally = or space + value.
AR_OPT=' -{1,2}[A-Za-z0-9][A-Za-z0-9-]*'
AR_OPTV=' -{1,2}[A-Za-z0-9][A-Za-z0-9-]*[= ]'"$AR_TOK"
# zero or more flags
AR_OPTS='('"$AR_OPT"'|'"$AR_OPTV"')*'
# optional cd prefix
AR_CD='(cd '"$AR_CWD"' && )?'

# ar_template <tool> -> echoes the anchored ERE for that tool, or nothing.
ar_template() {
    case "$1" in
        claude)   printf '^%sclaude%s$'   "$AR_CD" "$AR_OPTS" ;;
        codex)    printf '^%scodex( resume %s)?%s$' "$AR_CD" "$AR_UUID" "$AR_OPTS" ;;
        agy)      printf '^%sagy%s$'       "$AR_CD" "$AR_OPTS" ;;
        copilot)  printf '^%scopilot%s$'   "$AR_CD" "$AR_OPTS" ;;
        opencode) printf '^%sopencode%s$'  "$AR_CD" "$AR_OPTS" ;;
        kimi)     printf '^%skimi( -r session_%s)?$' "$AR_CD" "$AR_UUID" ;;
        hermes)   printf '^%shermes%s$'    "$AR_CD" "$AR_OPTS" ;;
        qwen)     printf '^%sqwen%s$'      "$AR_CD" "$AR_OPTS" ;;
        *)        return 1 ;;
    esac
}

# ar_validate <tool> <full-command-string>
# 0 = payload matches the tool's anchored allowlist, 1 = reject.
ar_validate() {
    local tool="$1" cmd="$2" re
    re="$(ar_template "$tool")" || return 1
    [ -n "$re" ] || return 1
    # unquoted RHS: bash treats it as a regex (quoting would match literally).
    [[ "$cmd" =~ $re ]] || return 1
    return 0
}

# standalone entry point for tests
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ "$#" -ne 2 ]; then
        printf 'usage: %s <tool> <command>\n' "$(basename "$0")" >&2
        exit 2
    fi
    if ar_validate "$1" "$2"; then exit 0; else exit 1; fi
fi
