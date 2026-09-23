# Tests

```bash
bash tests/mac_setup_test.sh        # setup/mac.sh, stubbed
bash tests/install_dispatch_test.sh # setup/install.sh detection and dispatch, stubbed
bash tests/sync_forks_test.sh       # files/bin/sync-forks, sandboxed git fixtures
bash tests/ic_link_test.sh          # files/bin/ic-link per-tool manual wiring, sandboxed HOME
bash tests/ic_doctor_test.sh        # files/bin/ic-doctor auth and cross-tool checks (sections 6 and 7), sandboxed HOME
bash tests/linux_e2e_docker.sh      # real Linux and WSL install in a container
```

All but the last never install anything and run anywhere.
`.github/workflows/ci.yml` runs every suite except `linux_e2e_docker.sh` on macOS for each pull request and each push to `main`, alongside shellcheck at warning level over every bash script in the repo.
`linux_e2e_docker.sh` needs Docker and skips itself when Docker is unavailable.
All six honour `DEBUG_KEEP_SANDBOX=1`, which leaves the scratch directory each one works in (per scenario, for `mac_setup_test.sh`) on disk for inspection after a failing run instead of removing it on exit.

`mac_setup_test.sh` is a regression test for `setup/mac.sh`.
It never runs the script against the real machine, since that script installs Nix and activates a real `nix-darwin` system.
Instead it runs the actual `setup/mac.sh` against a PATH-masked sandbox of stub executables (`curl`, `sh`, `nix`, `darwin-rebuild`, `sudo`, `bash`) that simulate a fresh Mac.
The stubs also make sure the bootstrap uses the canonical `install.determinate.systems` installer URL.
The harness re-homes `NVM_DIR` under the sandboxed `HOME`, clears inherited `BASH_ENV`/`ENV` for the script invocation, and guards all harness/stub write paths so parent traversal or symlink escapes fail before anything is written.
It also self-tests that sandbox guard before running the bootstrap scenarios.

It covers four scenarios:

- a fresh machine, where the script must install Nix, source the daemon profile into the current shell, and activate `nix-darwin` for the first time, all in a single pass with no second-session step
- a fresh machine cloned without a committed `flake.lock`, where the script must generate the lock as the invoking user before the `sudo` activation, so the rebuild never leaves a root-owned `flake.lock` in the working tree
- an already-bootstrapped machine, where the existing `darwin-rebuild switch` fast path is used instead
- a checkout relocated away from the `dotfilesDir` that `nix/user.nix` declares, where the script must exit non-zero naming both paths, before any installer, `sudo`, or activation call is made

The fixture is checked out at the declared `dotfilesDir` under the sandboxed `HOME` for every scenario except the last, which deliberately relocates it.

See `AGENTS.md` for the fresh-machine single-pass contract these tests protect.

## install_dispatch_test.sh

Covers `setup/install.sh`, which ends in `exec` on a real bootstrap and so can no more be run for real than `setup/mac.sh` can.
Two things make it testable:

- `--dry-run` runs the entire decision path (argument parsing, detection, architecture mapping, profile selection, dispatch target) and stops immediately before the `exec`, printing the resolved plan.
- `PATH` is masked down to stub `uname` executables, so the platform under test is chosen by the test rather than inherited from the host.
  Without that, the Linux and WSL cases could only ever be asserted from a Linux machine.

The WSL probes read `$WSL_OSRELEASE_FILE` and `$WSL_VERSION_FILE`, which the test points at fixture files instead of the real `/proc`.
Each WSL signal is asserted to be sufficient on its own: the `osrelease` probe, the `/proc/version` probe, and `$WSL_DISTRO_NAME`.
Architecture assertions check the exact profile suffix, since the whole point of the `-aarch64` profiles is that an ARM machine must not rebuild for x86_64.
An architecture the flake has no output for at all (a `riscv64` stub) must be named and refused before anything dispatches, rather than quietly mapped to the x86_64 profile and left to fail inside `nix build` on a host that by then has Nix on it.
Native Windows is asserted to refuse and exit non-zero rather than dispatch anything.

Standard input is `/dev/null` for every case, so a regression that prompts unconditionally surfaces as a wrong answer rather than a hung suite.

It also covers `setup/linux.sh`'s checkout-path guard, for both the Linux and WSL entry modules, from a fixture placed at a deliberately wrong path.
That guard is what stops a WSL install from running against a `/mnt/c` checkout, whose absolute links would resolve only while the Windows drive is mounted.
`PATH` for those cases leads with stub `curl` and `nix` executables that announce themselves on stderr and fail, so that even if the guard ever regressed the rest of the script has no way to reach a real installer or a real build.
Masking down to `/usr/bin:/bin` would not be enough on its own: a stock macOS or Linux host has a real `curl` sitting there.
The same wrongly-placed fixture is then run with `PATH` masked down to just the three binaries the guard legitimately needs, so `sed` is genuinely absent (and so are `curl` and `nix`).
That is the regression case: the guard used to read the `dotfilesDir` literal by shelling out to `sed`, and a userland without it produced an empty answer and skipped the check entirely.
No `setup/linux.sh` case in this suite is left with a working `curl` or `nix` on its `PATH`, so none can reach a real installer or a real build even if a guard regresses; keep that property when adding a case.

The profile name is asserted to come from the `username` literal in `flake.nix` rather than from a constant in the shell, using a fixture whose flake declares a different user.
`install.sh` must resolve `alice@linux` there, `linux.sh` must reject a stale `shreejitverma@linux` naming the username the flake actually declares, and it must do so before the installer is reached.
The matching accept case, `alice@linux`, is the only case in this suite that clears every guard, so it is asserted to stop at the stub `nix` on its first real invocation, before any build or activation.
That is why the stub `nix` matters rather than leaving the stub `curl` to stop the run by accident: with a real `nix` anywhere on `PATH` the installer branch is skipped and the next step is a genuine build against the fixture.

It covers `setup/linux.sh`'s shell startup-file pre-flight the same way, from a fixture that does sit at the declared path so the checkout guard passes and this one is what stops the run.
A symlinked `~/.bashrc` must abort with the path and the `mv` command named, before the build and before the installer; a regular `~/.profile` must only be announced with the `.backup` name it will get.
`PATH` there leads with the same stub `curl` and `nix`, so reaching the Determinate installer or a build surfaces as an assertion failure rather than as a real download.

## linux_e2e_docker.sh

The dispatch test proves the installer decides correctly; this proves the decision works.
It stages the working tree (not `HEAD`, so uncommitted changes are covered), runs the real `setup/install.sh` inside a Linux container, and asserts on the environment that comes out: that the binaries resolve, that `rebuild` drives `home-manager` rather than `darwin-rebuild` and names the right per-architecture profile, and that `.zshrc` orders the tool integrations before `ic-workflow.zsh` and `ic-workflow.zsh` before `zsh-syntax-highlighting`.

It runs both profiles and asserts they genuinely differ: Linux enables the systemd sync timer and gets the desktop layer, while WSL leaves the timer disabled, omits the desktop layer, and adds the Windows interop aliases.

Two deliberate gaps:

- The Determinate installer is not exercised, because the image already has Nix, so the `if ! command -v nix` branch of `setup/linux.sh` is skipped.
  That branch is verified the same way `setup/mac.sh`'s is: by stubs, never against a real host.
- `setup/windows.ps1` is not covered at all.
  It needs Windows and PowerShell, neither of which exists on the machines this suite runs on.

Verification inside the container deliberately runs without `set -e`.
The image is minimal, and under `-e` one missing utility aborts the script and makes every later probe report as a config failure instead of a missing tool.

## sync_forks_test.sh

End-to-end regression test for `files/bin/sync-forks`, the manifest-driven daily fork sync.
It runs the real script against sandboxed `$HOME` directories containing real git repositories wired to local bare `origin` and `upstream` remotes, so every fetch, `--ff-only` merge, and push is a genuine git operation asserted through resulting ref state.
Nothing reaches the network or the real machine: the PATH the script builds for itself (`ic_default_path`) leads with the sandbox's `~/.local/bin`, where stub `gh`, `osascript`, and `notify-send` executables record their invocations instead of calling GitHub or posting notifications.
The stubs and the install-command fixtures deliberately read stdin, so dropping the `</dev/null` redirects inside the manifest while-read loop surfaces as later manifest entries being slurped off the pipe and never processed.

It covers: a behind fork fast-forwarded, pushed, and reinstalled; an up-to-date fork whose install command must not re-run and whose stale local `user.email`/`user.name` overrides are stripped; a diverged fork reported and left byte-for-byte untouched (locally, on the fork remote, and by `gh repo sync`, which must not be called for it); an ahead-only fork reported and never published (no push, no `gh repo sync`); dirty-tree, wrong-branch, uncloned, and `sync: false` entries; a transient fetch failure retried once and recovering into a normal sync with no failure notification, while a persistently unreachable remote fails the repo after exactly two attempts (a PATH-leading `git` wrapper fails `fetch` while a per-repo countdown is positive, and a stub `sleep` records the requested 30-second pause and returns immediately); the parsed sync-eligible entry count being logged, with a manifest that parses to zero entries (format drift) exiting non-zero and notifying instead of reading as a clean run; 30-day log rotation; a missing `upstream` remote failing the repo rather than reading as up to date; failure notifications outranking diverged ones; a host with no manifest exiting 0 quietly; `--dry-run` reporting drift while mutating nothing, never notifying, and judging identity as if the local override it reports were already stripped; a stray global identity failing the repo before any sync; and `ic-workflow.zsh` sourcing the generated fleet aliases file when present and sourcing cleanly when absent.

The fleet manifest, `gh` behaviour, and desktop notifications are the suite's stub boundary; the launchd schedule and systemd timer that trigger the script are nix module config, outside this suite's scope and not asserted by any automated check.

## ic_link_test.sh

Runs the real `files/bin/ic-link` against fake `$HOME` directories under one scratch sandbox and asserts the resulting link state with `readlink`, never the script's source.
Nothing is stubbed: `ic-link` only creates symlinks under `$HOME`, so re-homing it is the whole isolation.
Each scenario seeds a fake `~/github/agents` with `AGENTS.md` (the tool-neutral build), `CLAUDE.md`, `GEMINI.md`, `GROK.md`, and two agent definitions, unless the scenario is about one of them being absent.
It also seeds a `grok/config.toml` there, which the real agents repo deliberately does not version: it is a stray that `ic-link` must ignore, so seeding it is what proves the file is skipped by rule rather than only because no copy happens to exist.

It covers:

- `~/.grok` absent, where `ic-link` must not create it (the Grok installer owns that directory)
- `~/.grok` present without `hooks/` or `config.toml`, where neither may be created (firstmate owns the hook files, Grok owns its config)
- the full layer, where `~/AGENTS.md` must point at the tool-neutral `agents/AGENTS.md` rather than Claude's manual, `~/.grok/AGENTS.md` must point at `GROK.md`, every `grok/agents/*.md` must be linked, the skill mirrors must use the same relative target as the Claude and Codex mirrors, an existing hook file must survive with nothing added beside it, and a Grok-written regular `~/.grok/config.toml` must keep its content and must not become a symlink even with a stray copy sitting in the agents repo
- an agents repo cloned without the tool-neutral `AGENTS.md` generated, where `ic-link` must refuse to repoint `~/AGENTS.md` at Claude's manual, warn naming `bin/build-manuals`, and leave a preexisting `~/AGENTS.md` untouched: silently handing Codex Claude-only rules is the fault this wiring exists to remove, and `ic-doctor` FAILs that state, so `ic-link` must not create it
- no agents repo at all, where the previous Claude target still stands, since there is no neutral manual to point at and a dangling link would leave Codex reading nothing
- `~/.gemini` absent, where `ic-link` must not create it (the Gemini installer owns that directory)
- `~/.gemini` present, where `~/.gemini/AGENTS.md` must point at `GEMINI.md` while `~/.gemini/GEMINI.md`, Gemini's own memory file, stays a real file with its content untouched
- an agents repo without `GEMINI.md`, where no `~/.gemini/AGENTS.md` link may be created at all rather than falling back to another tool's manual
- an agents repo without `GROK.md`, where `ic-link` must exit 0, warn, leave a preexisting `~/.grok/AGENTS.md` in place, and never fall back to Claude's file
- every skill under `files/skills` in the invoking checkout, which must link into the declared `dotfilesDir` (not the invoking tree) and be mirrored for Claude and Grok; the list comes from `setup/lib/skills.sh`, the same helper `ic-link` uses, so the scenario needs no edit when a skill is added
- a real directory where a skill link belongs (as `npx skills` leaves one), which `ic-link` must warn about and leave untouched rather than creating a link inside it
- Claude subagents and rules in the agents repo, each linked one file at a time into `~/.claude/agents` and `~/.claude/rules`, keeping a subagent Claude itself wrote there, and never replacing a hand-written rule file with a link

## ic_doctor_test.sh

Runs the real `files/bin/ic-doctor` against fake `$HOME` directories and asserts only section 6 (auth, cut between the `[6/7]` and `[7/7]` headers) and section 7 (cut from the `[7/7]` header).
The other sections still run against the fake `HOME` and the host, and may FAIL there; that is expected and not asserted.
There are two stubs, both planted inside the fake `HOME` on the PATH `ic-doctor` builds for itself (`ic_default_path`): a fake `grok` executable that prints a version line, at `~/.local/bin/grok` or `~/go/bin/grok`, and a fake `quota-axi` at `~/.local/bin/quota-axi` that prints either a readable quota row or attention lines only, so section 6 needs no live provider.
That PATH also includes host directories outside the fake `HOME`, so a real `grok` installed somewhere like `/opt/homebrew/bin` on the host would show up as a second copy; the suite does not mask that.

It covers:

- a `quota-axi` quota row carrying a numeric percentage: the section 6 claude quota read reports `ok`
- attention lines alone, whose third field is a word such as `stale` or `headroom_unknown`: `warn`, and never `ok`; this pair holds the regression where the check grepped for `,fresh,`, which only the `--full` output emits, so it warned on every healthy run
- `~/AGENTS.md` linked to the tool-neutral `agents/AGENTS.md`: `ok`, with no FAIL on the cross-tool chain, and the `Default development system` routing section verified in that file rather than only in Claude's, since it is what Codex now loads; a neutral manual that has lost the section is a FAIL beside a still-`ok` `CLAUDE.md`
- `~/AGENTS.md` resolving to Claude's manual while a neutral build exists: FAIL naming that specific fault, since one tool reading another tool's manual is what the per-tool build exists to remove
- the agents repo cloned but its `AGENTS.md` never generated: FAIL naming `bin/build-manuals`, never an `ok` for the Claude fallback, which matches how a missing `GROK.md` or `GEMINI.md` source already FAILs
- no agents repo at all: the Claude fallback is the only target there is, so it is `ok`
- that same fallback target with no `~/.claude/CLAUDE.md` behind it: FAIL, since a dangling `~/AGENTS.md` means Codex reads nothing, and the remedy follows what is actually missing rather than always naming `ic-link`, which is the command that produced the dangling link: `clone ~/github/agents` with no repo, `bin/build-manuals` with the repo cloned but no neutral `AGENTS.md` generated (a present `CLAUDE.md` is not a substitute, since `ic-link` cannot build the manual this link needs), and `ic-link` alone once that manual exists to point at
- `~/.grok` absent: one skip warning and no Grok FAIL
- a healthy install: the binary, the `GROK.md` link, the "Default development system" section, the skill mirrors, and the agent definitions all `ok`, with a Grok-owned regular `~/.grok/config.toml` never mentioned and the Claude personal-layer check unaffected by `~/.grok`
- `grok` resolving outside `~/.local/bin`, and a second `grok` on PATH: both FAIL, the latter naming the copy to keep and the `npm uninstall` that drops the other
- `~/.grok/AGENTS.md` pointing at Claude's file: exactly one FAIL line, naming the actual target; the same FAIL must still appear, as its own line beside the missing-source FAIL, when `GROK.md` is absent (the state a machine wired by this branch's first commits is in until `GROK.md` is added), and when `~/github/agents` is not cloned at all
- `~/.grok/AGENTS.md` as a regular file: FAIL, since only a link to `GROK.md` is Grok's versioned manual
- a version line with an unrecognised channel label: accepted, since the official binary is identified by location alone
- an agent definition renamed in the agents repo: FAIL naming the unlinked file, then `ok` once linked, with no fixed list of expected names; the old link the rename leaves dangling is a separate FAIL naming it and the `rm` that clears it (`ic-link` never deletes inside `~/.grok`), and a dangling link that never pointed into the agents repo is ignored
- Grok installed with `~/github/agents` not cloned: exactly one Grok warning, the skill mirrors still checked, and no Grok FAIL
- an agents repo with `GROK.md` but no `grok/agents`, which is all the README asks for: exactly one warning naming the absent source and no Grok FAIL, since agent definitions are optional and `ic-link` skips them the same way
- an agents repo lacking `GROK.md` and `grok/agents`: the missing `GROK.md` is a FAIL naming the source to add rather than a bare `run: ic-link`, which would be a no-op there; the missing `grok/agents` is only a warning, but the links that removal leaves dangling are all named in their own FAIL line, since the dangling scan does not depend on how many definitions the repo still has
- `~/.gemini` absent: one skip warning and no Gemini FAIL
- healthy Gemini wiring: `~/.gemini/AGENTS.md` linked to `GEMINI.md`, `context.fileName` listing `AGENTS.md`, and the `Default development system` routing section in `GEMINI.md` are all `ok`, with no Gemini FAIL
- a `GEMINI.md` that has lost that routing section: FAIL, with the link itself still `ok`, since Gemini is a tool that really loads its manual and all four manuals are verified alike
- `~/.gemini/GEMINI.md` made a symlink: FAIL, since that is Gemini's own memory file, written by `/memory add`, and must stay a real file
- `~/.gemini/AGENTS.md` not linked: FAIL naming the source it should point at
- `~/.gemini/AGENTS.md` pointing at Claude's manual: exactly one FAIL line, naming the actual target; the same FAIL must still appear when `~/github/agents` is not cloned at all, which is the state every hand-made link is in and the one the repo guard used to hide, and there it is the only Gemini FAIL, printed beside the repo-absent warning, whose wording says what was not checked rather than claiming no manual is linked, which would contradict it. Its remedy names the clone to do first, since `bin/build-manuals` is not on disk until the repo is there
- an agents repo without `GEMINI.md`: exactly one Gemini FAIL, naming the missing source rather than blaming the link
- `context.fileName` not listing `AGENTS.md` while a manual is linked: FAIL naming the hand step that fixes it, since the link alone never loads; `ic-doctor` checks that setting because `settings.json` is Gemini's file to own and `ic-link` never writes it, so this is the one state every `ic-link`-wired machine starts in
- Gemini installed with `~/github/agents` not cloned, both with a settings file that has no `AGENTS.md` entry and with no settings file at all (the two states a fresh Gemini install is actually in): exactly one Gemini warning and no Gemini FAIL, since `ic-link` deliberately links nothing there and a check about the linked manual never loading would contradict the warning above it; the same holds for a cloned repo with no `GEMINI.md`, which yields only the missing-source FAIL naming `bin/build-manuals`, since that manual is generated and must not be hand-written
- a hand-made `~/.gemini/AGENTS.md` pointing at the manual an uncloned repo would provide: a warning naming that dangling target, and exactly one Gemini line. The repo-absent warning is always emitted, so Gemini can never be the one tool that says nothing at all about a broken manual link; it reports what was not checked rather than asserting a link state, so it does not contradict a mislink FAIL above it
- Claude subagents and rules linked from the agents repo: `ok` per kind with the count; a versioned rule that is not linked is a FAIL naming it, a hand-written real file in its place is its own FAIL naming the merge, remove, and `ic-link` remedy rather than the bare `ic-link` one that would never fix it, with no `ok` line for that kind beside it, and a `~/.claude/agents` link left dangling by a removed source is a FAIL naming the link and the `rm` that clears it, while a dangling link that never pointed into the agents repo is ignored
- `claude/settings.json` running `claude/hooks/guard.py`: `ok` when the script exists and `python3` is on `PATH`, FAIL when the script is missing, since every Bash and edit call would then hit a hook error
- a stub `bin/build-manuals` in the agents repo that exits non-zero with a size-ceiling warning followed by its real stale-manual message: FAIL quoting the stale-manual line, not the first line; exiting zero: `ok`
