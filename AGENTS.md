# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

## Deliberate decisions - do NOT silently revert them

- `homebrew.onActivation.cleanup = "none"` in `nix/host.nix` is intentional. Packages installed manually with `brew` are left alone; do not harden it to `uninstall` or `zap` until the declared lists are the full source of truth for this machine.
- App configs under `files/` are linked into place with `mkOutOfStoreSymlink` so they can be edited without a rebuild. Keep new app configs in `files/` and wire them through `home.file` in `nix/user.nix`; do not copy them into the Nix store.
- `~/.config/nvim` is deliberately NOT managed by this repo. It is a separate git checkout of github.com/shreejitverma/kickstart.nvim; do not add a `home.file` symlink for it or copy an editor config into `files/`.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.
- `setup/mac.sh` generates `flake.lock` as the invoking user before the `sudo` activation, so the rebuild never leaves a root-owned lock file inside the repo. Keep that block ahead of the activation step.

## Upstream sync

This repo is a fork of `kunchenguid/dotfiles-mac-nix`, wired as the `upstream` remote.
Sync with `git fetch upstream && git merge upstream/main`, keeping the fork-specific layers above intact when resolving conflicts.
Upstream has marked itself superseded by `kunchenguid/dotfiles`, a different repo that is not this fork's parent, so that notice is deliberately not carried into this README.

## setup/mac.sh: never run it for real

`setup/mac.sh` installs Nix (via the Determinate installer) and runs a real `nix-darwin` system activation (`darwin-rebuild switch` / `sudo nix run ... switch`). Never execute it, the real Determinate installer, `darwin-rebuild switch`, `sudo nix run ...`, the Homebrew installer, or the nvm installer against a dev machine or CI host - these mutate the host permanently. All validation of this script must go through `tests/mac_setup_test.sh`, which runs the actual script with PATH masked to stub executables so nothing real is ever installed or activated.

## Fresh-machine single-pass contract

`setup/mac.sh` must bootstrap a brand-new Mac in one run, with no "run it again in a new shell" step. After the Determinate installer runs, the script sources the Nix daemon profile (`NIX_DAEMON_PROFILE`, defaults to `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`) into the current shell so `nix` is usable immediately, then activates nix-darwin for the first time via `sudo <absolute nix path> --extra-experimental-features "nix-command flakes" run nix-darwin/master#darwin-rebuild -- switch --flake ...` (absolute path because `sudo` doesn't inherit the newly-sourced PATH). `NIX_DAEMON_PROFILE` and `DARWIN_REBUILD_BIN` are both overridable via environment variables (defaulting to the real canonical paths) specifically so tests can point them at a sandbox instead of the real filesystem. Any future edit to this bootstrap logic must preserve: single-pass success on a fresh machine, and the existing already-installed fast path (`$DARWIN_REBUILD_BIN switch`) staying untouched.

## Testing setup/mac.sh

Run `bash tests/mac_setup_test.sh`. It simulates a fresh Mac by copying the repo into a scratch fixture (placeholders pre-replaced), building stub `curl`/`sh`/`nix`/`darwin-rebuild`/`sudo`/`bash` executables that record invocations and fake just enough side effects (a profile script, a `nix` binary) for the script to progress, then running the real `setup/mac.sh` against that PATH-masked sandbox. It covers the fresh-machine path (single-pass activation), a fresh machine with no committed `flake.lock` (user-owned lock generation ordered ahead of the `sudo` activation), and the already-installed fast path. It never touches the real network, Nix store, Homebrew, sudo, or system state. Set `DEBUG_KEEP_SANDBOX=1` to keep the scratch sandbox around for inspection after a failing run.

Each scenario sandboxes `HOME`, re-homes `NVM_DIR` under that temp root, and unsets inherited `BASH_ENV`/`ENV` before invoking `setup/mac.sh` (an inherited absolute `NVM_DIR` from hm-session-vars would otherwise leak stub writes).
Harness and stub writes call `assert_path_under_sandbox` / `guard_write_path` so a future leak through parent traversal, symlink escape, or another absolute write path fails the test instead of mutating the host.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
