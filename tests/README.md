# Tests

```bash
bash tests/mac_setup_test.sh        # setup/mac.sh, stubbed
bash tests/install_dispatch_test.sh # setup/install.sh detection and dispatch, stubbed
bash tests/linux_e2e_docker.sh      # real Linux and WSL install in a container
```

The first two never install anything and run anywhere.
The third needs Docker and skips itself when Docker is unavailable.
All three honour `DEBUG_KEEP_SANDBOX=1`, which leaves the scratch directory each one works in (per scenario, for `mac_setup_test.sh`) on disk for inspection after a failing run instead of removing it on exit.

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
