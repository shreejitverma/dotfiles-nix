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

## The agent-first IC toolchain

Beyond the base Mac setup, this machine runs an integrated toolchain for working as a single individual contributor with a crew of coding agents.
Every tool below is a fork of a [kunchenguid](https://github.com/kunchenguid) repo, kept in sync with upstream automatically.
This section documents how it is wired on my system today, and then gives the exact commands to reproduce the whole setup from scratch.

### The tools

| Tool | What it does | Local artifact |
|---|---|---|
| [dotfiles-mac-nix](https://github.com/kunchenguid/dotfiles-mac-nix) | This repo: nix-darwin + Home Manager + Homebrew base system | `rebuild` alias |
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
`files/bin/ic-doctor` is the read-only health check for all six layers; run it whenever something feels off or after changing the setup.

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

### From scratch: the full setup, step by step

These are the exact commands to reproduce this system on a new Mac.
Prerequisite: finish the base setup above (`setup/mac.sh`, then `rebuild`), which provides git, Node via nvm, pnpm, Go, and `gh`.

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

**Step 9: verify everything.**

```bash
ic-doctor
```

`ic-doctor` (in `files/bin`, already on `PATH`) is a read-only check of all six layers: every fork's clone, remotes, branch, and cleanliness; every binary's presence and `--version`; every skill symlink in both directories; the launchd sync agent and its last log line; `gh` plus quota-axi auth; and the cross-tool default chain (`~/AGENTS.md`, codex `AGENTS.md`, and codex skills).
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
- GitHub repo: <https://github.com/kunchenguid/dotfiles-mac-nix>
