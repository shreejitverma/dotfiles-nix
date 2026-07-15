# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `homebrew.onActivation.cleanup = "none"` in `nix/host.nix` is intentional. Packages installed manually with `brew` are left alone; do not harden it to `uninstall` or `zap` until the declared lists are the full source of truth for this machine.
- App configs under `files/` are linked into place with `mkOutOfStoreSymlink` so they can be edited without a rebuild. Keep new app configs in `files/` and wire them through `home.file` in `nix/user.nix`; do not copy them into the Nix store.
- `~/.config/nvim` is deliberately NOT managed by this repo. It is a separate git checkout of github.com/shreejitverma/kickstart.nvim; do not add a `home.file` symlink for it or copy an editor config into `files/`.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
