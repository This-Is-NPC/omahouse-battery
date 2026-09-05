#!/usr/bin/env bash
set -euo pipefail

# OMAKURE_SCHEMA_START
# {"Name":"omahouse-report","Description":"The day's totals for one account, as JSON (local only)","Tags":["omahouse","read","local-only"],"Fields":[{"Name":"user","Prompt":"Which account, or empty to take the machine's own","Type":"string","Order":1,"Required":false,"Arg":"--user","Default":""},{"Name":"since","Prompt":"The first day to cover, as YYYY-MM-DD, or empty for today","Type":"string","Order":2,"Required":false,"Arg":"--since","Default":""}]}
# OMAKURE_SCHEMA_END

# Exit codes, and the reason there are four rather than two: a Cue brings back
# nothing but this number, so it is the whole vocabulary this script has when it
# is dispatched. `3` is a check that ran and answered "no", which is not an
# error and must not read as one.
#
#   0  it worked, or the answer is yes
#   1  this script or omahouse refused: usage, a bad value, a write that failed
#   2  what was asked about is not there -- no such account, no such profile
#   3  the check ran and the answer is no
readonly EX_OK=0 EX_FAIL=1 EX_MISSING=2 EX_NO=3

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit "${2:-$EX_FAIL}"; }

# -- where a value comes from -------------------------------------------------
#
# Nothing machine-specific is written in this repository. The same Battery is
# installed on every machine, and each one supplies its own facts, in this
# order:
#
#   1. `--flag value` on the command line -- a person, or the HTTP API
#   2. `OMAHOUSE_BATTERY_*` in the node's active Omakure environment
#   3. for the account only: the machine's own profiles, when there is one
#   4. a refusal naming all three, because a dispatched run that guessed would
#      be a guess nobody was there to catch
#
# Layer 2 is what makes a Remote Cue useful at all. A Cue carries no arguments
# and no environment map -- but the node's *own* active environment is merged
# into every run it starts, Cue-origin included, and that environment is the
# node owner's input rather than the Conductor's. Measured: with
# `OMAHOUSE_BATTERY_USER` set in the active environment and no argument passed,
# it reaches the child.
#
# So the Conductor says *what to do* and the machine says *to whom*. Neither can
# say the other's half, which is the property worth having.

# `--flag value` pairs, and nothing cleverer. Omakure hands the declared `Arg`
# values this way, and a person running the file by hand types the same thing --
# which is the contract: a script stays usable outside Omakure.
arg() {
    local want=$1
    shift
    while [[ $# -gt 0 ]]; do
        if [[ $1 == "$want" ]]; then
            [[ $# -ge 2 ]] || return 1
            printf '%s' "$2"
            return 0
        fi
        shift
    done
    return 1
}

# Layers 1 and 2, in that order. `settled NAME FLAG "$@"` prints the value or
# nothing; the caller decides whether nothing is fatal.
settled() {
    local var=$1 flag=$2
    shift 2
    local found
    if found=$(arg "$flag" "$@"); then
        printf '%s' "$found"
        return 0
    fi
    printf '%s' "${!var-}"
}

bin() {
    local b=${OMAHOUSE_BIN:-omahouse}
    command -v "$b" >/dev/null 2>&1 || die "omahouse is not on PATH" "$EX_MISSING"
    printf '%s' "$b"
}

# Layer 3, for the account and for nothing else. A machine with one profile on
# it can name it without being told; a machine with two cannot, and must not
# pick. Every other value is an instruction rather than a fact about the
# machine, so there is nowhere here to read one from.
the_account() {
    local given=$1
    if [[ -n $given ]]; then
        printf '%s' "$given"
        return 0
    fi
    local -a found
    mapfile -t found < <("$(bin)" profile list --json 2>/dev/null \
        | grep -o '"user":"[^"]*"' | sed 's/.*:"//;s/"$//')
    case ${#found[@]} in
        1) printf '%s' "${found[0]}" ;;
        0) die "no account given, and nobody is under rules on this machine. \
Pass --user, or set OMAHOUSE_BATTERY_USER in this node's environment" "$EX_MISSING" ;;
        *) die "no account given, and ${#found[@]} are under rules here (${found[*]}). \
Pass --user, or set OMAHOUSE_BATTERY_USER in this node's environment" ;;
    esac
}

# Privilege only where the file actually needs it. /etc/omahouse belongs to
# root, so a real machine takes the second path; a run with the roots moved by
# their variables owns its own files and must not ask for anything -- which is
# also what makes this Battery testable without root anywhere.
writable_config() {
    local config=${OMAHOUSE_CONFIG_DIR:-/etc/omahouse}
    [[ $EUID -eq 0 ]] && return 0
    [[ -w $config ]] && return 0
    [[ ! -e $config && -w $(dirname "$config") ]] && return 0
    return 1
}

omahouse() {
    local b
    b=$(bin)
    if writable_config; then
        "$b" "$@"
    else
        sudo -n "$b" "$@"
    fi
}


# The same locality as `omahouse-status.sh`, and the same reason.
#
# This is the script worth giving a `Schedule` to. A cron line in the block
# above makes the machine write its own evening report without anybody asking
# for it, which is the shape that works here: the answer never has to cross the
# wire, because it was produced on the side that is allowed to hold it.
user=$(the_account "$(settled OMAHOUSE_BATTERY_USER --user "$@")")
since=$(settled OMAHOUSE_BATTERY_SINCE --since "$@")

# Checked here rather than left to omahouse, only because a dispatched run has
# nowhere to show a refusal: the exit code would say "usage error" and the
# sentence explaining which word was wrong would go nowhere.
[[ -z $since || $since =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
    || die "since is a date like 2026-09-05, not '$since'"

b=$(bin)
set +e
if [[ -n $since ]]; then
    out=$("$b" report "$user" --since "$since" --json)
else
    out=$("$b" report "$user" --json)
fi
code=$?
set -e
printf '%s\n' "$out"
exit "$code"
