# dotfiles-nix

This repo is the public, reusable core of my development setup, on macOS, Linux, and WSL.

It is built with [Nix](https://nixos.org/), [`nix-darwin`](https://github.com/nix-darwin/nix-darwin), [Home Manager](https://github.com/nix-community/home-manager), and declarative [Homebrew](https://brew.sh/). The goal is to give developers a reproducible base they can fork and adapt without inheriting someone else's entire private dotfiles repo.

If you want the longer explanation, see the [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web).

## What this repo does

It gives you a structured starting point for managing a development setup in code:

- bootstrap a machine with one command, `setup/install.sh`, which detects macOS, Linux, or WSL
- configure macOS defaults with `nix-darwin`
- manage user packages and shell behavior with Home Manager, identically on every platform
- install GUI apps and macOS-native tools declaratively with Homebrew
- keep selected app config in the repo and link it into place

The same shell, prompt, git config, and CLI toolchain follow you across all three platforms.
What differs is how deep the configuration reaches: on macOS it owns the whole machine, and on Linux and WSL it owns your user environment and leaves the distro alone.
Windows itself is not a target, because Nix has no native Windows build; the supported path there is WSL2.

App configs kept in the repo and linked into place include [WezTerm](https://wezfurlong.org/wezterm/) and herdr. Neovim config is deliberately not managed here; it lives in its own repo, [kickstart.nvim](https://github.com/shreejitverma/kickstart.nvim), checked out at `~/.config/nvim`.

## What is intentionally not included

This repo does **not** try to mirror my entire machine.

I left out things that are too personal to make a good public repo, including:

- secrets and tokens
- private automation

The goal is to provide a reusable foundation that you can make your own.

## Repo structure

- `setup/install.sh` - detect the platform and run the right bootstrap (start here)
- `setup/mac.sh` - bootstrap a fresh Mac
- `setup/linux.sh` - bootstrap a Linux or WSL machine
- `setup/windows.ps1` - enable WSL2 on Windows, then run the Linux bootstrap inside it
- `setup/lib/platform.sh` - shared platform detection, sourced by the installer and `files/bin`
- `setup/README.md` - bootstrap usage and testing notes
- `flake.nix` - top-level Nix wiring
- `nix/host.nix` - machine-level macOS config (nix-darwin)
- `nix/user.nix`, `nix/linux-user.nix`, `nix/wsl-user.nix` - per-platform Home Manager entry points
- `nix/home/` - the layers those entry points compose: `common.nix` (cross-platform), `desktop.nix` (fonts and linked app configs), `darwin.nix`, `linux.nix`, `wsl.nix`
- `files/.config/wezterm/wezterm.lua` - WezTerm config linked into place
- `files/.config/herdr/config.toml` - herdr config linked into place
- `files/bin/` - personal scripts kept on `PATH`, including `sync-forks` (weekly fork sync), `ic-link` (symlink farm), and `ic-doctor` (health check)
- `files/skills/` - agent skills owned by this repo (currently `ship`)
- `files/zsh/ic-workflow.zsh` - IC workflow shell config sourced by zsh
- `tests/` - regression tests for the bootstrap scripts and the Linux end-to-end install
- `AGENTS.md` - repo-specific notes for coding agents (`CLAUDE.md` is a symlink to it)
- `blog.md` - local copy of the [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web)

## How to use it

### 1. Clone the repo

```bash
git clone git@github.com:shreejitverma/dotfiles-nix.git ~/github/dotfiles-nix
cd ~/github/dotfiles-nix
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

### 3. Run the bootstrap

One command on every platform:

```bash
bash setup/install.sh
```

It detects whether the machine is macOS, Linux, or WSL, shows you what it found, and lets you confirm or pick a different target before anything is installed.
Non-interactively (a pipe, CI) it uses the detected target without prompting rather than hanging.

```bash
bash setup/install.sh --dry-run          # print the plan, install nothing
bash setup/install.sh --target wsl --yes # skip detection and the prompt
```

#### What each platform gets

| Platform | Activated with | Owns |
|---|---|---|
| macOS | `nix-darwin` + Home Manager | the whole machine: macOS defaults, Homebrew casks, launchd agents |
| Linux | standalone Home Manager | the user environment only |
| WSL | standalone Home Manager | the user environment, minus the desktop layer |

The asymmetry is not an oversight.
`nix-darwin` has no equivalent for an existing Linux distro, so on Linux and WSL this repo manages your packages, shell, git, and prompt, and leaves the kernel, services, display server, and distro packages alone.

#### Windows

Nix has no native Windows build, so there is nothing to install on Windows proper.
The supported path is WSL2:

```powershell
powershell -ExecutionPolicy Bypass -File setup\windows.ps1
```

That enables WSL2, installs a distro if you have none, clones this repo **inside** the distro, and runs `setup/install.sh --target wsl` there.
The clone has to live inside the distro rather than on `/mnt/c`: the config links files out of the checkout by absolute path, and a Windows-side checkout would leave those links resolving only while the drive is mounted, over a much slower filesystem boundary.
`setup/linux.sh` refuses such a checkout outright rather than half-installing.

If you already run WSL2, skip the PowerShell script and just run `bash setup/install.sh` inside your distro.

#### What the platform scripts do

- macOS (`setup/mac.sh`): installs [Determinate Nix](https://determinate.systems/nix-installer/) and [Homebrew](https://brew.sh/) if needed, applies `nix-darwin` + Home Manager, installs [`nvm`](https://github.com/nvm-sh/nvm) and a default Node.js.
  On a fresh machine this completes in one run: after the installer, the script sources the Nix daemon profile into the current shell and uses an absolute `nix` path for the first activation, so no second shell or second run is needed.
- Linux and WSL (`setup/linux.sh`): installs Determinate Nix if needed, builds the matching Home Manager profile out of this flake, and activates it.
  It builds the activation package from the pinned `flake.lock` rather than running `nix run home-manager/master`, so the Home Manager doing the activation is the one this repo pins instead of whatever is current upstream.
  Where systemd is not PID 1 (WSL without `systemd=true`, containers, non-systemd distros) it installs Nix with `--init none`, because the default Linux plan registers the daemon as a systemd service.

The `NIX_DAEMON_PROFILE`, `DARWIN_REBUILD_BIN`, `WSL_OSRELEASE_FILE`, and `WSL_VERSION_FILE` environment variables exist only so the regression tests can point the scripts at sandboxed paths.
Normal use should leave them unset.

## How I manage changes later

After the initial bootstrap, the usual workflow is:

1. edit the Nix config
2. run:

```bash
rebuild
```

The alias is included in the shell config, and each platform's profile defines it to mean the right thing:

```bash
# macOS
/run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles-nix#mac
# Linux and WSL
home-manager switch --flake ~/github/dotfiles-nix#<user>@<linux|wsl>[-aarch64]
```

`up` updates the whole machine: it refreshes the flake inputs, activates them the right way for the platform, and then updates Homebrew, rustup, and the tldr cache when those are present.

Note that `up` runs `nix flake update` first, so it bumps the pinned inputs.
To apply a change without moving the pins, use `rebuild`.

## Testing

```bash
bash tests/mac_setup_test.sh        # setup/mac.sh, against stubs
bash tests/install_dispatch_test.sh # platform detection and dispatch, against stubs
bash tests/linux_e2e_docker.sh      # real Linux and WSL install in a container
```

Do not run `setup/mac.sh`, `setup/linux.sh`, or `setup/install.sh` against a development or CI machine just to test them.
The first two suites above run the real script logic against a sandbox of stub executables, so nothing is ever installed or activated, and they run anywhere.
The third needs Docker and skips itself without it; it performs a genuine Nix build and Home Manager activation inside a container, then asserts on the environment that results.

Two gaps are deliberate and documented: the Determinate installer branch of `setup/linux.sh` is not exercised (the container image already ships Nix), and `setup/windows.ps1` is not covered at all, since it needs Windows and PowerShell.
See [`tests/README.md`](tests/README.md) for the scenarios each suite covers and how the sandbox is guarded.

## Where to add new tools

My rough rule of thumb:

- use **Home Manager / Nix** for reproducible baseline CLI tools, fonts, shell utilities, and user environment packages
- use **Homebrew** for GUI apps and macOS-native tools that fit naturally there
- use **ecosystem-specific package managers** like `npm` when that is the right abstraction for the tool

Where a tool goes in `nix/home/` decides which platforms get it:

| Add it to | Reaches |
|---|---|
| `nix/home/common.nix` | macOS, Linux, and WSL |
| `nix/home/desktop.nix` | macOS and Linux; skipped on WSL, which has no display server |
| `nix/home/darwin.nix`, `linux.nix`, `wsl.nix` | that platform only |
| `nix/host.nix` (Homebrew, macOS defaults) | macOS only, by nature |

Default to `common.nix`. Only reach for a platform file when the option genuinely does not exist elsewhere, such as `launchd` on macOS or `systemd.user` on Linux.

A good setup does not force every tool through one package manager. It just makes the ownership of each layer clear.
The [complete software inventory](#complete-software-inventory) below records which layer owns every installed piece of software.

## Why this setup looks like this

I wanted a setup that was:

- reproducible on a new Mac
- structured enough to maintain
- pragmatic about macOS
- publishable without oversharing the rest of my workflow

That is why this repo focuses on the reusable core.

## The agent-first IC toolchain

Beyond the base setup, this machine runs an integrated toolchain for working as a single individual contributor with a crew of coding agents.
Every tool below is a fork of a [kunchenguid](https://github.com/kunchenguid) repo, kept in sync with upstream automatically.
This section documents how it is wired on my system today, and then gives the exact commands to reproduce the whole setup from scratch.

### The tools

| Tool | What it does | Local artifact |
|---|---|---|
| [dotfiles-nix](https://github.com/shreejitverma/dotfiles-nix) | This repo: nix-darwin + Home Manager + Homebrew base system | `rebuild` alias |
| [axi](https://github.com/kunchenguid/axi) | The 10 AXI principles for agent-ergonomic CLIs, plus the SDK and skill | skill only |
| [gh-axi](https://github.com/kunchenguid/gh-axi) | GitHub (issues, PRs, CI, releases, Projects) through an agent-ergonomic CLI | `gh-axi` |
| [tasks-axi](https://github.com/kunchenguid/tasks-axi) | Task and backlog manager for the current workspace, agent-driven | `tasks-axi` |
| [chrome-devtools-axi](https://github.com/kunchenguid/chrome-devtools-axi) | Real Chrome control for agents: navigate, click, inspect, screenshot, audit | `chrome-devtools-axi` |
| [lavish-axi](https://github.com/kunchenguid/lavish-axi) | Rich annotatable HTML artifacts from agent output, with a feedback loop | `lavish-axi` |
| [quota-axi](https://github.com/kunchenguid/quota-axi) | Reports local LLM subscription quota windows so agents can pace spend | `quota-axi` |
| [no-mistakes](https://github.com/kunchenguid/no-mistakes) | `git push no-mistakes`: review, tests, lint, docs, PR, and CI gate before code ships | `no-mistakes` |
| [treehouse](https://github.com/kunchenguid/treehouse) | Git worktrees without managing worktrees; one worktree per stream of work | `treehouse` |
| [firstmate](https://github.com/kunchenguid/firstmate) | Talk to one agent, ship with a crew; agent-of-agents workspace | shell function |
| [gnhf](https://github.com/kunchenguid/gnhf) | "Good night, have fun": supervised overnight agent coding runs | `gnhf` |
| [wheelhouse](https://github.com/kunchenguid/wheelhouse) | Cross-repo "what needs my decision" queue on GitHub Issues + Actions | runs on GitHub |

### How it is integrated on this machine

The design has six layers, and each one is owned by exactly one mechanism.

**1. Forks under `~/github`.**
Every tool is cloned from my fork with the parent repo as `upstream`:

```text
origin   -> https://github.com/shreejitverma/<repo>.git
upstream -> https://github.com/kunchenguid/<repo>.git
```

This is what makes "merge and keep my changes" the default posture: local commits (like wheelhouse's `Configure fleet for shreejitverma`) survive every upstream sync.

**2. Binaries.**
Go tools are built with `make` and installed to `~/.local/bin`:

- `no-mistakes` from `~/github/no-mistakes` (`make build`, binary at `bin/no-mistakes`)
- `treehouse` from `~/github/treehouse` (`make build`, binary at `./treehouse`)

Node tools are built with `pnpm` and put on `PATH` with `npm link`, so the linked binary in `/opt/homebrew/bin` always runs the current build of the clone:

- `chrome-devtools-axi`, `gh-axi`, `gnhf`, `lavish-axi`, `quota-axi`, `tasks-axi`

`firstmate` is pure shell and is entered through the `firstmate` function in `files/zsh/ic-workflow.zsh`.
`axi` ships no daily-use binary; it contributes its skill and SDK source.
`wheelhouse` runs entirely on GitHub Actions inside the fork; nothing is built locally.

**3. Agent skills.**
Skills live in the clones and are symlinked twice, so every agent runtime sees the same live copy and a rebuild of a clone updates the skill in place:

```text
~/.agents/skills/<name>  -> ~/github/<repo>/skills/<name>
~/.claude/skills/<name>  -> ../../.agents/skills/<name>
```

A skill's name does not have to match its repo: `lavish` comes from `lavish-axi`, `stow` (sweep a session for durable knowledge before a context reset) comes from `firstmate`, and `axi` lives under `.agents/skills` inside its repo.
One skill is owned by this repo rather than a tool fork: `ship` (`files/skills/ship`), which encodes the end-to-end quality loop below as an invocable skill.

**4. Weekly sync.**
`files/bin/sync-forks` fetches upstream for every repo in its `REPOS` list, merges `upstream/main` into `main` (keeping local changes; conflicts abort and notify instead of clobbering), pushes the fork, and rebuilds the affected binaries.
A launchd agent defined in `nix/user.nix` runs it every Sunday at 10:00, logging to `~/Library/Logs/sync-forks*.log`.
`syncforks` and `syncforks-dry` run it by hand.

**5. Shell ergonomics.**
`files/zsh/ic-workflow.zsh` wires the tools into the shell: `th` (treehouse), `nm` (no-mistakes), `gn` (gnhf), `cda` (chrome-devtools-axi), `ta` (tasks-axi), `qa` (quota-axi), `fm` (firstmate), `syncforks`, and `icdoctor`.
`files/bin/ic-doctor` is the read-only health check for the whole system; run it whenever something feels off or after changing the setup.

**6. Cross-tool defaults.**
`~/.claude/CLAUDE.md` is the single source of truth for agent instructions, and its "Default development system" section makes this toolchain the default for every development request.
Other tools reach the same instructions and skills through symlinks:

```text
~/AGENTS.md               -> .claude/CLAUDE.md
~/.codex/AGENTS.md        -> ~/AGENTS.md
~/.codex/skills/<name>    -> ../../.agents/skills/<name>
```

So Claude Code, Codex, and anything else that reads `AGENTS.md` all see one set of rules and one set of skills.
Cursor is not installed on this machine; when it is, point its User Rules at `~/AGENTS.md` (or symlink a project's `.cursor/rules` to it) to join the same system.

The personal layer itself is version controlled in a **private** repo, `~/github/agents`, so nothing exists only as loose files in the home directory:

```text
~/.claude/CLAUDE.md      -> ~/github/agents/CLAUDE.md
~/OPINIONS.md            -> ~/github/agents/OPINIONS.md
~/VOICE.md               -> ~/github/agents/VOICE.md
~/.claude/settings.json  -> ~/github/agents/claude/settings.json
```

Edits made through the symlinks land in the repo; commit and push there as usual.
`files/bin/ic-link` is the idempotent script that creates this entire farm (skills, mirrors, instruction chain, personal layer), and `ic-doctor` verifies it.

### Complete software inventory

Every piece of software on this system belongs to exactly one owner.
This is the full map; if something is installed and not listed here, it is unmanaged and should be adopted into a layer.

| Layer | Owner | What it installs |
|---|---|---|
| OS toolchain | Apple | Xcode Command Line Tools: `git` (pre-Nix), `make`, `clang` (`xcode-select --install`) |
| Bootstrap | `setup/install.sh` -> `setup/mac.sh` | Determinate Nix, Homebrew, nvm + Node LTS (fallback; the primary Node is Homebrew's) |
| System config | `nix/host.nix` | `starship`; brew formulas `autoconf`, `herdr`; casks `wezterm`, `amethyst`, `opensuperwhisper`; macOS defaults (incl. OpenSuperWhisper Cmd+` record hotkey) |
| User packages | `nix/user.nix` `home.packages` | `git curl wget jq fd fastfetch ripgrep killall lazygit tree bun rustup zip unzip just dust duf procs sd btop tokei tealdeer uv ruff difftastic` + fonts (Hack Nerd Font, Roboto, Noto, Font Awesome) |
| User programs | `nix/user.nix` `programs.*` | `git`+`delta`, `starship`, `bat`, `fzf`, `zoxide`, `atuin`, `direnv`, `zsh`, `eza` |
| Manual Homebrew | `brew` (not yet declared in nix) | formulas `node`, `go`, `gh`; casks `google-chrome` (required by chrome-devtools-axi), `codex` |
| npm globals | `npm install -g` | `pnpm` (build tool for all Node forks) |
| Native installers | vendor scripts | `claude` (Claude Code, `curl -fsSL https://claude.ai/install.sh \| bash`) |
| Go builds | `sync-forks` / manual | `no-mistakes`, `treehouse` into `~/.local/bin` |
| npm links | `sync-forks` / manual | `chrome-devtools-axi`, `gh-axi`, `gnhf`, `lavish-axi`, `quota-axi`, `tasks-axi` |
| Skills installer | `npx skills` | third-party skills: `deploy-to-vercel`, `find-skills`, `vercel-*`, `web-design-guidelines`, `writing-guidelines` |
| Symlink farm | `ic-link` | all skill, instruction-chain, and personal-layer links |

Known gap, on purpose: the "Manual Homebrew" row is not yet declared in `nix/host.nix`.
Moving those five entries into `homebrew.brews`/`homebrew.casks` would make them declarative; until then, this table is their record.

### From scratch: the full setup, step by step

These are the exact commands to reproduce this system on a new Mac.
Nothing is assumed beyond a fresh macOS install with an admin account.
The IC toolchain below is macOS-first: the base Nix layer installs on Linux and WSL too, but several tools in this section come from Homebrew casks and have no Linux equivalent here yet.

**Step 0: prerequisites and base system.**

```bash
xcode-select --install          # Apple CLT: git, make, clang (accept the GUI prompt)
git clone https://github.com/<you>/dotfiles-nix.git ~/github/dotfiles-nix
cd ~/github/dotfiles-nix
bash setup/install.sh           # detects macOS; installs Nix, Homebrew, nix-darwin + Home Manager, nvm + Node LTS
exec zsh                        # pick up the new environment
```

On Linux or WSL the same first command applies, and `setup/install.sh` dispatches to the Home Manager path instead.
On Windows, run `powershell -ExecutionPolicy Bypass -File setup\windows.ps1` first; it prepares WSL2 and runs the Linux bootstrap inside it.

Then the runtimes and apps the toolchain needs, which the base config does not install:

```bash
brew install node go gh         # Node (primary), Go, GitHub CLI
brew install --cask google-chrome   # required by chrome-devtools-axi
npm install -g pnpm             # build tool for all the Node forks
```

And the AI coding tools themselves:

```bash
curl -fsSL https://claude.ai/install.sh | bash   # Claude Code -> ~/.local/bin/claude
brew install --cask codex                        # Codex CLI
```

**Step 1: authenticate GitHub.**

```bash
gh auth login
```

**Step 2: fork and clone every tool with an upstream remote.**

```bash
mkdir -p ~/github ~/.local/bin ~/.agents/skills ~/.claude/skills
cd ~/github
me=$(gh api user -q .login)
for repo in axi chrome-devtools-axi firstmate gh-axi gnhf lavish-axi \
            no-mistakes quota-axi tasks-axi treehouse wheelhouse; do
  gh repo fork "kunchenguid/$repo" --clone=false
  git clone "https://github.com/$me/$repo.git"
  git -C "$repo" remote add upstream "https://github.com/kunchenguid/$repo.git"
  git -C "$repo" fetch upstream
done
```

**Step 3: build the Go tools into `~/.local/bin`.**

```bash
cd ~/github/no-mistakes && make build && install -m755 bin/no-mistakes ~/.local/bin/no-mistakes
cd ~/github/treehouse   && make build && install -m755 treehouse       ~/.local/bin/treehouse
```

**Step 4: build and link the Node tools.**

```bash
for repo in chrome-devtools-axi gh-axi gnhf lavish-axi quota-axi tasks-axi; do
  cd ~/github/$repo
  pnpm install --frozen-lockfile
  pnpm run build
  npm link
done
```

**Step 5: clone the private personal layer.**
The agent operating manual (`CLAUDE.md` with its "Default development system" section), `OPINIONS.md`, `VOICE.md`, and Claude settings live in a private repo so they are version controlled without being published:

```bash
git clone https://github.com/<you>/agents.git ~/github/agents
```

If you are reproducing this setup for yourself, create that private repo first with your own `CLAUDE.md`; this repo's `files/skills/ship/SKILL.md` and the layer descriptions above tell you what it needs to contain.

**Step 6: wire every symlink with one command.**

```bash
ic-link
```

`ic-link` (in `files/bin`, on `PATH`) is the idempotent, versioned recipe for the whole farm: skill links into `~/.agents/skills`, mirrors into `~/.claude/skills` and `~/.codex/skills`, the `~/AGENTS.md` and `~/.codex/AGENTS.md` chain, and the personal-layer links from `~/github/agents` (skipped with a note if that repo is absent).
Rerun it any time; it repairs stale links in place.

**Step 7: enable the weekly sync.**
The script and the launchd agent are already in this repo, so applying the config is enough:

```bash
rebuild
syncforks-dry   # verify: every repo should report how far behind upstream it is
```

**Step 8: one-time per-tool setup.**

quota-axi needs macOS Keychain access once to read live Claude quota (click "Always Allow"):

```bash
quota-axi --allow-keychain-prompt auth
```

wheelhouse is configured on GitHub, not locally: commit your fleet of repos to your fork, enable Actions on it, and add the secrets its README lists.
That fleet-config commit is exactly the kind of local change `sync-forks` preserves.

firstmate runs from inside its workspace; the shell function handles that:

```bash
fm claude   # cd ~/github/firstmate and launch an agent with the crew
```

Optional ambient context: some tools can inject their state at agent session start (for Claude Code, Codex, and OpenCode) instead of waiting to be asked.
Not currently enabled here; enable per tool with:

```bash
tasks-axi setup hooks             # backlog as ambient session context
chrome-devtools-axi setup hooks   # browser bridge ambient context
```

Since `~/.claude/settings.json` is a symlink into the private agents repo, the hook edits land there; commit them.

Optional third-party skills come from the [skills](https://github.com/vercel-labs/skills) installer, not from ic-link:

```bash
npx skills add <owner>/<repo> --skill <name> -g   # -g = all projects (~/.claude/skills)
```

**Step 9: verify everything.**

```bash
ic-doctor
```

`ic-doctor` (in `files/bin`, already on `PATH`) is a read-only check with seven sections: this checkout's path against the `dotfilesDir` declared in `nix/user.nix`, plus the app-config symlinks and shell hook that path feeds; every fork's clone, remotes, branch, and cleanliness; every binary's presence and `--version`; every skill symlink in both directories; the launchd sync agent and its last log line; `gh` plus quota-axi auth; and the cross-tool default chain (`~/AGENTS.md`, codex `AGENTS.md`, and codex skills).
It exits non-zero if anything needs attention, and every failure line names the command that fixes it.
A healthy system ends with `ic-doctor: all checks passed`.

### Maintenance: adding a new tool to the rotation

The checklist when adopting the next tool, so it inherits all five layers:

1. Fork, clone, and set the `upstream` remote (Step 2 pattern).
2. Build and put it on `PATH`: `pnpm install --frozen-lockfile && pnpm run build && npm link` for Node tools, or `make build && install -m755 <bin> ~/.local/bin/<bin>` for Go tools.
3. Add its skill to `files/bin/ic-link` (both the canonical link and the `ALL_SKILLS` mirror list) and run `ic-link`.
4. Add the repo to `REPOS` and a rebuild case to `rebuild_tool()` in `files/bin/sync-forks`.
5. Add it to the `FORKS`, `BINARIES`, and `SKILLS` lists in `files/bin/ic-doctor`.
6. Optionally add a short alias in `files/zsh/ic-workflow.zsh`.
7. Run `syncforks-dry` and `ic-doctor` to confirm, then commit the dotfiles change.

### Troubleshooting

- **A Node tool's build fails under `npm install`.**
  These repos use pnpm; `npm install` against a pnpm `node_modules` fails with errors like `Cannot read properties of null (reading 'matches')`.
  Always use `pnpm install --frozen-lockfile`.
- **A binary is on `PATH` but `--version` fails.**
  The npm link points at a clone whose `dist/` is stale or missing; rebuild the clone (`pnpm run build`) or relink (`npm link`).
- **``Cmd+` `` moves window focus instead of, or as well as, toggling OpenSuperWhisper recording.**
  ``Cmd+` `` is also macOS's default "Move focus to next window" shortcut; the record hotkey declared in `nix/host.nix` deliberately overlaps it and leaves the system binding untouched.
  If the overlap ever conflicts, disable the system shortcut manually in System Settings > Keyboard > Keyboard Shortcuts > Keyboard.
  The hotkey preference is applied by `rebuild`; restart OpenSuperWhisper after changing it.
- **`Ctrl-R` opens atuin's history search, not fzf's.**
  That is deliberate: both `programs.fzf` and `programs.atuin` want `Ctrl-R`, and `nix/user.nix` cedes it to atuin with `programs.fzf.historyWidget.command = ""`.
  fzf keeps `Ctrl-T` (files) and `Alt-C` (directories).
  To flip the ownership, drop that line and add `"--disable-ctrl-r"` to `programs.atuin.flags`.
- **The installer picked the wrong platform, or you want a different one.**
  Run `bash setup/install.sh --dry-run` to see what it detected and what it would do, then `--target <darwin|linux|wsl>` to override it.
  WSL is detected from `$WSL_DISTRO_NAME`, `$WSL_INTEROP`, `/proc/sys/kernel/osrelease`, or `/proc/version`; any one of them is enough.
- **`Could not find suitable profile directory` during a Linux or WSL install.**
  Home Manager will not activate without a per-user Nix profile directory, and it does not exist for a user who has never run a `nix` command.
  `setup/linux.sh` creates it, so this only appears if you activated by hand; run `mkdir -p ~/.local/state/nix/profiles` and retry.
- **The Nix installer fails on WSL or in a container complaining about systemd.**
  The Determinate installer's default Linux plan registers the daemon as a systemd service, which cannot work where systemd is not PID 1.
  `setup/linux.sh` detects that and installs with `--init none` instead. WSL only runs systemd if you enable it explicitly in `/etc/wsl.conf`.
- **The weekly fork sync never runs on WSL.**
  That is deliberate: the timer is shipped disabled there because systemd is off by default.
  Run `syncforks` by hand, or enable systemd in `/etc/wsl.conf` and switch to the Linux profile behaviour.
- **`setup/linux.sh` refuses a checkout under `/mnt/c`.**
  Also deliberate. The config links files out of the checkout by absolute path, so a Windows-side checkout resolves only while the drive is mounted, and is much slower over the filesystem boundary.
  Clone inside the distro at `~/github/dotfiles-nix`.
- **quota-axi shows `auth_required` for claude.**
  Keychain access has not been granted; run `quota-axi --allow-keychain-prompt auth` and click "Always Allow".
- **sync-forks skipped a repo.**
  It skips anything with uncommitted changes or a non-`main` branch by design; commit or stash, switch to `main`, and rerun `syncforks`.
- **sync-forks reported a conflict.**
  It aborted the merge and left the repo untouched; resolve by hand with `git merge upstream/main` in that clone, keeping your changes.
- **Where are the sync logs?**
  `~/Library/Logs/sync-forks.log` (script log) plus `sync-forks.out.log` and `sync-forks.err.log` (launchd streams).
- **A skill or instruction symlink is missing or points somewhere stale.**
  Run `ic-link`; it recreates the entire farm idempotently.
- **Everything else.**
  Run `ic-doctor`; each FAIL line names the fix.

### How the pieces work together day to day

The point of the stack is that each tool owns one phase of the loop.
The `ship` skill encodes the whole loop, so any agent in any tool can be told `/ship` and run it end to end.

- Start the day with `quota-axi` to see how much agent headroom the session and week have left, and check the wheelhouse queue on GitHub for decisions other people are waiting on.
- Pull the next piece of work with `tasks-axi ready`, and open an isolated worktree for it with `th` so streams of work never collide.
- Do the work with agents that carry the axi skills: `gh-axi` for everything GitHub, `cda` for anything that needs a real browser, `lavish` when a plan or review is easier to judge as a rich artifact.
- Ship through `nm` (no-mistakes), which runs review, tests, lint, docs, push, PR, and CI as one gate, so nothing reaches the remote unvalidated.
- Before ending a long agent session, invoke the `stow` skill so preferences, project facts, and unfinished next steps land on disk instead of dying with the context window.
- Before bed, hand the backlog to `gn` (gnhf) for a supervised overnight run, and read the results over coffee.
- Sunday at 10:00, `sync-forks` merges upstream improvements into every fork, keeps local changes, pushes, and rebuilds, so the whole toolchain stays current without a thought.

## Related

- Long-form write-up: [blog post](https://open.substack.com/pub/kunchenguid/p/how-i-built-a-reproducible-mac-setup?utm_campaign=post-expanded-share&utm_medium=web)
- GitHub repo: <https://github.com/shreejitverma/dotfiles-nix>
- Forked from [kunchenguid/dotfiles-mac-nix](https://github.com/kunchenguid/dotfiles-mac-nix), wired here as the `upstream` remote. Sync with `git fetch upstream && git merge upstream/main`.
