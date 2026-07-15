# dotfiles-mac-nix

This repo is the public, reusable core of my Mac setup.

It is built with [Nix](https://nixos.org/), [`nix-darwin`](https://github.com/nix-darwin/nix-darwin), [Home Manager](https://github.com/nix-community/home-manager), and declarative [Homebrew](https://brew.sh/). The goal is to give macOS developers a reproducible base they can fork and adapt without inheriting someone else's entire private dotfiles repo.

If you want the longer explanation, see the [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web).

## What this repo does

It gives you a structured starting point for managing a Mac setup in code:

- bootstrap a fresh Mac with `setup/mac.sh`
- configure macOS defaults with `nix-darwin`
- manage user packages and shell behavior with Home Manager
- install GUI apps and macOS-native tools declaratively with Homebrew
- keep selected app config in the repo and link it into place

App configs kept in the repo and linked into place include [WezTerm](https://wezfurlong.org/wezterm/) and herdr. Neovim config is deliberately not managed here; it lives in its own repo, [kickstart.nvim](https://github.com/shreejitverma/kickstart.nvim), checked out at `~/.config/nvim`.

## What is intentionally not included

This repo does **not** try to mirror my entire machine.

I left out things that are too personal to make a good public repo, including:

- secrets and tokens
- private automation

The goal is to provide a reusable foundation that you can make your own.

## Repo structure

- `setup/mac.sh` — bootstrap a fresh Mac
- `flake.nix` — top-level Nix wiring
- `nix/host.nix` — machine-level macOS config (nix-darwin)
- `nix/user.nix` — user environment: packages, shell, git, fonts, dotfiles (Home Manager)
- `files/.config/wezterm/wezterm.lua` — WezTerm config linked into place
- `files/.config/herdr/config.toml` — herdr config linked into place
- `files/bin/` — personal scripts kept on `PATH`
- `files/zsh/ic-workflow.zsh` — IC workflow shell config sourced by zsh
- `AGENTS.md` — repo-specific notes for coding agents
- `blog.md` — local copy of the [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web)

## How to use it

### 1. Clone the repo

```bash
git clone git@github.com:kunchenguid/dotfiles-mac-nix.git ~/github/dotfiles-mac-nix
cd ~/github/dotfiles-mac-nix
```

### 2. Replace the placeholders

Update values like:

- `yourname`
- `/Users/yourname`
- `Your Name`
- `you@example.com`

If you are on an Intel Mac, change the system target in `flake.nix` from:

```nix
system = "aarch64-darwin";
```

to:

```nix
system = "x86_64-darwin";
```

### 3. Run the bootstrap script on a fresh Mac

This repo is primarily set up for Apple Silicon Macs. If you are on Intel, make the architecture change above before you run the bootstrap script.

```bash
bash setup/mac.sh
```

The script will:

- install [Determinate Nix Installer](https://determinate.systems/nix-installer/) if needed
- install [Homebrew](https://brew.sh/) if needed
- apply the `nix-darwin` + Home Manager config
- install [`nvm`](https://github.com/nvm-sh/nvm) and a default Node.js version if needed

## How I manage changes later

After the initial bootstrap, the usual workflow is:

1. edit the Nix config
2. run:

```bash
rebuild
```

This alias is included in the shell config and expands to the repo path used in this guide:

```bash
/run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles-mac-nix#mac
```

## Where to add new tools

My rough rule of thumb:

- use **Home Manager / Nix** for reproducible baseline CLI tools, fonts, shell utilities, and user environment packages
- use **Homebrew** for GUI apps and macOS-native tools that fit naturally there
- use **ecosystem-specific package managers** like `npm` when that is the right abstraction for the tool

A good setup does not force every tool through one package manager. It just makes the ownership of each layer clear.

## Why this setup looks like this

I wanted a setup that was:

- reproducible on a new Mac
- structured enough to maintain
- pragmatic about macOS
- publishable without oversharing the rest of my workflow

That is why this repo focuses on the reusable core.

## Related

- Long-form write-up: [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web)
- GitHub repo: <https://github.com/kunchenguid/dotfiles-mac-nix>
