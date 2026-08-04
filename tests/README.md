# Tests

Run all tests with:

```bash
bash tests/mac_setup_test.sh
```

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
