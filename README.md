# omahouse-battery

An [Omakure](https://github.com/This-Is-NPC/omakure) Battery for
[omahouse](https://github.com/This-Is-NPC/omahouse): house rules for the
accounts on an Omarchy machine, driven from another machine.

Every script here is a thin wrapper over one `omahouse` verb. None of them
reimplements a decision. The rules, the arithmetic and the refusals live in
omahouse, and a second place that decided any of them would be a second answer
to the same question — which is how two machines come to disagree about a child
nobody was watching.

**Nothing in this repository names a person, a program, a site or a machine.**
The same eleven scripts install unchanged everywhere; each machine supplies its
own facts. That is what makes this shareable, and it is the whole design.

## Where a value comes from

In this order, for every parameter:

| | Source | For |
|---|---|---|
| 1 | `--flag value` | A person at the machine, or its HTTP API |
| 2 | `OMAHOUSE_BATTERY_*` in the node's active Omakure environment | A dispatched Remote Cue |
| 3 | The machine's own profiles — **the account only**, and only when there is exactly one | Anything, when the machine can name itself |
| 4 | A refusal naming all three | Everything else |

Layer 2 is what makes a Remote Cue useful at all. A Cue carries no arguments and
no environment map — but the node's *own* active environment is merged into
every run it starts, Cue-origin included, and that environment is the node
owner's input rather than the Conductor's.

So the Conductor says **what to do** and the machine says **to whom**. Neither
can say the other's half, and that is the property worth having.

```bash
omakure env create house \
    OMAHOUSE_BATTERY_USER=<the account under rules> \
    OMAHOUSE_BATTERY_PROFILE_SOURCE=/etc/omahouse/profiles.intended.json
omakure env activate house
```

Layer 3 exists because a machine with one profile can name it without being
told. A machine with two cannot, and refuses rather than picking — a dispatched
run that guessed would be a guess nobody was there to catch.

### The variables

| Variable | Flag | Used by |
|---|---|---|
| `OMAHOUSE_BATTERY_USER` | `--user` | all but `health` |
| `OMAHOUSE_BATTERY_APP` | `--app` | `allow`, `deny` |
| `OMAHOUSE_BATTERY_LIMIT` | `--limit` | `allow` |
| `OMAHOUSE_BATTERY_KIND` | `--kind` | `limit` |
| `OMAHOUSE_BATTERY_TARGET` | `--target` | `limit` |
| `OMAHOUSE_BATTERY_TIME` | `--time` | `limit` |
| `OMAHOUSE_BATTERY_BUDGET` | `--budget` | `grant` |
| `OMAHOUSE_BATTERY_MINUTES` | `--minutes` | `grant` |
| `OMAHOUSE_BATTERY_VERDICT` | `--verdict` | `web-rule` |
| `OMAHOUSE_BATTERY_DOMAIN` | `--domain` | `web-rule` |
| `OMAHOUSE_BATTERY_STATE` | `--state` | `enforce` |
| `OMAHOUSE_BATTERY_PROFILE_SOURCE` | `--source` | `profile-apply`, `drift` |
| `OMAHOUSE_BATTERY_SINCE` | `--since` | `report` |
| `OMAHOUSE_BATTERY_STALE_AFTER` | `--stale-after` | `health` |

omahouse's own roots — `OMAHOUSE_CONFIG_DIR`, `OMAHOUSE_STATE_DIR`,
`OMAHOUSE_CHROMIUM_POLICY_DIR` — are read too, and `OMAHOUSE_BIN` picks the
binary. The `_BATTERY_` infix keeps this Battery's parameters from ever
colliding with a variable omahouse itself grows.

### The four defaults that stay

`minutes=10`, `kind=session`, `verdict=block`, `state=off`, `stale-after=300`.
None names anything about a machine; each is a judgement that travels. `state`
defaults to `off` and `verdict` to `block` on purpose: a dispatched run uses its
default, so a stale Battery version or a Cue that reached the wrong machine
lands on the side that takes something away rather than opening something.

## Three families, and the line is not a preference

Omakure's Remote Cue carries no arguments and brings back **nothing but an exit
code**. Its Health Plane forbids script stdout, usernames, process lists and
user activity at any depth, in any encoding. That is a deliberate property of
Omakure and a good one, and it decides everything below.

**The seven that act** — `grant`, `allow`, `deny`, `limit`, `web-rule`,
`enforce`, `profile-apply`. Their whole answer is success or failure, which is
what a `cue_ack` and a `run-completed` Signal carry. Dispatch these.

**The two that ask** — `status`, `report`. What they print is exactly the class
that may not travel. Run them from the machine's own CLI or its authenticated
HTTP API. `report` is the one worth giving a `Schedule` to: the machine writes
its own evening report, and the answer never has to cross a wire it is not
allowed to cross.

**The two that ask in a shape that fits an exit code** — `health`, `drift`. *Is
the daemon up and counting?* and *is this machine running the profiles it is
supposed to be?* The only remote questions this design allows.

## The intended profiles

`profile-apply` and `drift` work against a file **this repository does not
carry**: `OMAHOUSE_BATTERY_PROFILE_SOURCE`, or
`/etc/omahouse/profiles.intended.json` by default. The path is a convention this
Battery names; the content belongs to whoever runs the fleet, delivered by a
signed Baseline or placed by an operator, and never read from a message.

`profile-apply` parses it with omahouse's own reader, in a staging directory,
before anything lands — so a file omahouse would refuse never becomes a daemon
that will not start. `drift` compares bytes, so the intended file should be what
omahouse wrote rather than something hand-formatted.

## Install

```bash
omakure battery add https://github.com/<you>/omahouse-battery.git \
    --ref main --name omahouse
omakure battery sync omahouse
omakure battery scripts omahouse
omakure battery install omahouse omahouse.grant
```

Install materialises one script into the trusted scripts workspace. It is a
local act: never a peer's, never a Cue's.

**Scripts land at the workspace root, and they have to.** A Cue names a script
by its file name and `cue_dispatch.script` admits no `/`, so a script installed
into a subdirectory cannot be dispatched at all. That is why this repository is
flat.

## Before a Cue will run one

Two gates, both on the receiving node and both in its own config — nothing in a
message contributes to either:

```toml
[trust]
remote_cue_batteries = ["omahouse"]
```

or name individual scripts in `remote_cue_scripts`. A script merely present in
the workspace is not dispatchable.

## Privilege

omahouse's reading verbs need none. Its writing verbs need root, because
`/etc/omahouse/profiles.json` is a root daemon's file.

Each script asks only where the file actually needs it: if the config directory
is writable it runs directly, otherwise it goes through `sudo -n` — never a
prompt, because nobody is at the keyboard of a dispatched run. Give the node's
account a `sudo` or polkit rule for `omahouse`, or run the node service as root
and accept what that means.

Nothing here declares a `secret` field. A script that did would be rejected at
the Cue gate rather than run without it.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | It worked, or the answer is yes |
| `1` | Refused: usage, a bad value, or a write that failed |
| `2` | What was asked about is not there — no such account, no omahouse |
| `3` | The check ran and the answer is no |

`3` is a check that answered *no*. It is not an error and must not be read as
one: a dispatched run brings back this number and nothing else, so the
difference between "it broke" and "it says no" has to live here.

## Running one by hand

Every script parses its own `--flag value` pairs and works with no Omakure
anywhere:

```bash
./omahouse-grant.sh --user <account> --budget chromium --minutes 15
./omahouse-drift.sh --source /etc/omahouse/profiles.intended.json
```
