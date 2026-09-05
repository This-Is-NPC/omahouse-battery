#!/usr/bin/env bash
set -euo pipefail

# OMAKURE_SCHEMA_START
# {"Name":"omahouse-profile-apply","Description":"Write the intended profiles.json this machine holds, after it parses","Tags":["omahouse","write","cue","fleet"],"Fields":[{"Name":"source","Prompt":"Path to the intended profiles.json","Type":"string","Order":1,"Required":false,"Arg":"--source","Default":""},{"Name":"dry-run","Prompt":"Check that it parses and write nothing","Type":"bool","Order":2,"Required":false,"Arg":"--dry-run","Default":"false"}]}
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


# The rules this machine should be running, and they are **not** in this
# repository.
#
# That was the first shape and it was wrong: a Battery with one household's
# profile baked into it is a Battery that works on one machine. The same
# scripts install everywhere, so what differs per machine has to arrive per
# machine. The path is a convention this Battery names; the content belongs to
# whoever runs the fleet, delivered by a signed Baseline or placed by an
# operator, and never read from a message.
source=$(settled OMAHOUSE_BATTERY_PROFILE_SOURCE --source "$@")
source=${source:-${OMAHOUSE_CONFIG_DIR:-/etc/omahouse}/profiles.intended.json}

dry=$(settled OMAHOUSE_BATTERY_DRY_RUN --dry-run "$@")
dry=${dry:-false}
b=$(bin)

[[ -e $source ]] || die "no intended profiles at $source. \
Place one there, or point --source / OMAHOUSE_BATTERY_PROFILE_SOURCE somewhere else" "$EX_MISSING"
[[ -s $source ]] || die "$source is empty"

# It parses before it lands, and omahouse's own reader is what decides that.
# There is no second parser here and there must not be one: a script that
# accepted a shape omahouse would refuse is a script that stops a daemon at the
# next restart, on a machine nobody is sitting at.
#
# Unprivileged, in a directory of ours, with the root moved by the variable the
# end to end suite already uses. Nothing about this step can touch /etc.
staging=$(mktemp -d "${TMPDIR:-/tmp}/omahouse-apply.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
cp -- "$source" "$staging/profiles.json"

if ! OMAHOUSE_CONFIG_DIR="$staging" "$b" profile list --json >/dev/null 2>&1; then
    OMAHOUSE_CONFIG_DIR="$staging" "$b" profile list >&2 || true
    die "the intended profiles do not parse; nothing was written"
fi

if [[ $dry == true ]]; then
    printf '%s parses, and --dry-run wrote nothing\n' "$source"
    exit "$EX_OK"
fi

target=${OMAHOUSE_CONFIG_DIR:-/etc/omahouse}/profiles.json

# Written the way omahouse writes: a temporary file beside the target and then a
# rename, so a reader in the moment this takes sees the whole of the old file or
# the whole of the new one and never half of either.
if writable_config; then
    install -D -m 0644 "$staging/profiles.json" "${target}.omahouse-battery.tmp"
    mv -f "${target}.omahouse-battery.tmp" "$target"
else
    sudo -n install -D -m 0644 "$staging/profiles.json" "${target}.omahouse-battery.tmp"
    sudo -n mv -f "${target}.omahouse-battery.tmp" "$target"
fi

# The daemon rereads the file every cycle, so there is nothing to restart and
# nothing to signal. Said out loud because the absence of a reload step is the
# kind of thing somebody adds back later out of habit.
printf 'wrote %s from %s; the daemon picks it up on its next cycle\n' "$target" "$source"
