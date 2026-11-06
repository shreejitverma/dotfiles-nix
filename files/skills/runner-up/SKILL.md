---
name: runner-up
description: Operate and reason about runner-up, the self-hosted GitHub Actions runner coordinator on this machine fleet - read its status, finished-job resource readings and setup checks, size pools from evidence, write runs-on lines for its pools, and request a borrowed macOS VM or a place drain. Use when a task mentions runner-up, self-hosted runners, runner pools, slow or queued GitHub Actions jobs, Actions minutes cost, macOS CI on own hardware, or a fresh macOS VM for a check.
---

# runner-up

runner-up (`~/github/runner-up`, fork of `kunchenguid/runner-up`) runs GitHub Actions jobs on the owner's own machines.
One coordinator on Linux or macOS holds a runner scale set session per repository and pool, and starts a one-job runner in a fresh place for each job: a Docker container or KVM VM on Linux, a tart clone or Apple container guest on a Mac, a job account or Hyper-V VM on Windows, or the machine itself (a host place).
It reaches each machine's agent over SSH and stores no token: it asks `gh auth token` per session.
The binary is built from the fleet clone into `~/go/bin/runner-up` by the daily fork sync; never install it with `curl | sh`, `go install`, or Nix, which would put a second copy on `PATH`.
The upstream README is the authoritative reference: read the section you need in `~/github/runner-up/README.md` before acting, since the behavior is young and changes between releases.

## 0. Find out what exists before anything else

```sh
runner-up status        # places, running reservations, resting machines, waiting work, borrows, drains
```

`status` exits 2 with `no setup file at <path>` when no coordinator has been set up on this machine.
Report that plainly as "runner-up is installed but no setup exists here, so this machine serves no self-hosted runners", and stop there unless the user asks to set one up.
Never infer that a repository's jobs run self-hosted from the binary being present; only a setup listing that repository, plus a running coordinator, makes that true.
What a machine's setup serves, and why, is recorded in the `runner-up` entry's `notes` in `~/github/.fleet/manifest.yaml`; read it before reasoning about which repositories or jobs runner-up carries.

On a Mac managed by dotfiles-nix the coordinator is the launchd agent `org.nix-community.home.runner-up`, which runs `~/go/bin/runner-up serve` only while the setup file exists:

```sh
launchctl print gui/$(id -u)/org.nix-community.home.runner-up | grep -E 'state|pid'   # running or not
tail -n 50 ~/Library/Logs/runner-up.log                                               # coordinator log
~/github/.fleet/bin/install-runner-up.sh --check                                      # build, setup and coordinator health
```

Never start a second coordinator by hand while that agent runs; a second coordinator for the same pool only waits for the first.
A repository can route jobs to a pool through a repository variable rather than a hard-coded label (cryozen uses `CRYOZEN_MACOS_RUNNER`); deleting that variable sends those jobs back to hosted runners, which is the switch to suggest when the coordinator's machine will be asleep or away, not editing the setup or the workflow.
The setup file defaults to `~/Library/Application Support/runner-up/config.json` on macOS and `~/.config/runner-up/config.json` on Linux; `--config FILE` names another, and every command but `agent`, `fork-guard`, `setup`, `service` and `version` takes it.

## 1. Commands by risk

Read-only, safe to run whenever they help:

| Command | Answers |
|---|---|
| `runner-up status` | what each place is doing and what waits, with why |
| `runner-up usage` | finished jobs' sampled peak cores and memory beside each pool's size |
| `runner-up check-config` | whether the setup is valid, and how each machine's budget is shared and in which priority order places are tried |
| `runner-up agent probe` | this machine's cores, memory, and which providers work (docker, kvm, tart, host, container) |
| `runner-up version` | the running build (`v0.1.12-1-g<sha>` style from the fleet build) |

Changes state, so run only when the user asked for that specific outcome in this session:

| Command | Effect |
|---|---|
| `runner-up init`, `runner-up machine add` | write the setup file; `init` also checks the sign-in can create runners, and `machine add` copies runner-up onto the machine over SSH |
| `runner-up serve` | runs the coordinator, which registers scale sets on GitHub |
| `runner-up update` | downloads the setup's `release` and points `stateDir/program/current` at it |
| `runner-up borrow ...` | reserves a tart place for a command (experimental) |
| `runner-up drain ...` | pauses named places until named jobs ran there (experimental) |
| editing the setup file | a running coordinator applies a valid edit about a second after it settles, with no restart |

Never run `runner-up setup` or `runner-up service`: they are Windows administrator commands.
Anything with `sudo`, any install of tart, Apple's container tool, or a macOS image (about 30 GB), and any change to a launchd or systemd service needs the user's explicit go-ahead first.

## 2. Writing workflows for a served repository

Only after `status` shows the repository and its pools:

- Ask for a pool by its label: `runs-on: <pool-label>`, exactly as the setup's `pools` list names it.
  A label no running coordinator serves leaves the job queued at GitHub until it times out; it does not fall back to hosted runners.
- Pools are job kinds: GitHub may hand a runner any job of its pool, so every job in one pool must fit one size.
  Give jobs with different needs separate pools rather than one oversized pool.
- Size workers from `RUNNER_UP_CORES` and `RUNNER_UP_MEMORY_MB`, never from `nproc`: these describe the job's reservation, and on a host place the operating system does not enforce it.
- Jobs from forks' pull requests, and `workflow_run` follow-ons of them, are refused by the fork guard unless `allowForkPullRequests` is set; do not set it to make a check pass.
- A tart job starts from the image every time, and nothing it changes is kept; tools must be baked into the image or installed per job.

## 3. Sizing from evidence

Use `runner-up usage` after several representative runs of a pool on the same machine and provider.
Readings are advisory samples once a second: host readings cover the runner's process group (RSS can double-count shared pages), tart readings cover the whole guest.
An `unavailable` or `incomplete` reading is missing evidence, never zero use; Docker, KVM, Apple container and Windows places do not produce readings yet.
Propose a new pool size with headroom over the observed peaks, and say how many runs it rests on; runner-up never changes a size by itself, and neither should an agent without the user agreeing.

## 4. Borrowing a fresh macOS VM (experimental)

When a check needs a clean macOS environment and the setup has a tart pool, a borrow waits in the same line as jobs instead of bypassing it:

```sh
runner-up borrow --pool <tart-pool> --label "<why>" --minutes 30 -- sh -c '
  set -eu
  tart clone <local-image> "$BORROWED_VM"
  tart set "$BORROWED_VM" --cpu "$BORROWED_CPUS" --memory "$BORROWED_MEMORY_MB"
  exec tart run --no-graphics "$BORROWED_VM"
'
```

- The command runs on the coordinator's machine; for a remote Mac it must reach that Mac itself.
- It never builds or pulls an image, and it does not start the VM: the command does, under the reserved `BORROWED_VM` name, which runner-up deletes afterwards.
- A Mac runs at most two macOS VMs at once, counting ones runner-up did not start.
- Exit codes: the command's own status, `124` for the time limit (`max(1 hour, --minutes)`), `130` for cancellation, `1` for a supervisor or cleanup failure.

## 5. Diagnosing a stuck or slow job

1. `runner-up status`: is the job waiting, and why (no free place, waiting for room, machine resting, place drained)?
2. A resting machine means its agent could not be reached over SSH; check `ssh -o BatchMode=yes <user>@<machine> true` and say what failed, rather than editing the setup.
3. `runner-up check-config`: a pool size that never fits, or places on no pool, is refused here with the reason.
4. Order across repositories and pools is exact; within one pool of one repository GitHub picks which job a runner takes, so order there is only close.

## 6. Invariants never to break

- A runner's registration travels only on standard input or a VM serial port; never write it to a file, argument, image, environment, or log.
- Never put a token in the setup file; it must never hold one.
- A running job is never the price of a change: do not stop the coordinator's place runners, kill a job's VM, or remove a place to make a change apply sooner.
- One update path for a coordinator: either the fleet build in `~/go/bin` is what the supervisor starts, or the setup names a `release` and the supervisor starts `stateDir/program/current`; never both.
