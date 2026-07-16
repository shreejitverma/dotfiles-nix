# =============================================================================
# IC Workflow: aliases, functions, and shell options for a top-tier IC.
# Sourced from nix/user.nix (programs.zsh.initContent).
# Plain zsh so it is easy to read, edit, and extend without a nix rebuild.
# Everything that depends on an optional tool is guarded with `command -v`.
# =============================================================================

# -----------------------------------------------------------------------------
# Shell options: sane, fast, low-friction interactive behavior.
# -----------------------------------------------------------------------------
setopt AUTO_CD                 # `foo` runs `cd foo` when foo is a directory
setopt AUTO_PUSHD              # cd pushes onto the directory stack
setopt PUSHD_IGNORE_DUPS       # no duplicate entries on the stack
setopt PUSHD_SILENT            # do not print the stack on every pushd/popd
setopt EXTENDED_GLOB           # powerful globbing (^, #, ~)
setopt GLOB_DOTS               # globs match dotfiles too
setopt NUMERIC_GLOB_SORT       # sort numbered files numerically
setopt INTERACTIVE_COMMENTS    # allow # comments in interactive shell
setopt NO_BEEP                 # silence the bell

# History: large, deduplicated, shared. Atuin layers on top if installed.
HISTSIZE=200000
SAVEHIST=200000
setopt EXTENDED_HISTORY        # record timestamps
setopt HIST_IGNORE_ALL_DUPS    # drop older duplicate commands
setopt HIST_IGNORE_SPACE       # commands starting with space are not recorded
setopt HIST_REDUCE_BLANKS      # trim superfluous whitespace
setopt HIST_VERIFY             # confirm history expansion before running
setopt SHARE_HISTORY           # share history across sessions

# -----------------------------------------------------------------------------
# Navigation
# -----------------------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias -- -='cd -'
alias dl='cd ~/Downloads'
alias dt='cd ~/Desktop'
alias docs='cd ~/Documents'
alias gh-dir='cd ~/github'
alias dot='cd ~/github/dotfiles-mac-nix'
alias nvc='cd ~/.config/nvim'

# -----------------------------------------------------------------------------
# Listing (eza). Falls back gracefully if eza is not yet installed.
# -----------------------------------------------------------------------------
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons=auto'
  alias l='eza -lbF --group-directories-first --icons=auto'
  alias ll='eza -lbGF --git --group-directories-first --icons=auto'
  alias la='eza -labGF --git --group-directories-first --icons=auto'
  alias lA='eza -labhHigUmuSa --time-style=long-iso --git --color-scale --group-directories-first --icons=auto'
  alias lt='eza --tree --level=2 --group-directories-first --icons=auto'
  alias ltt='eza --tree --level=3 --group-directories-first --icons=auto'
  alias lr='eza -lbF --group-directories-first --icons=auto --sort=modified'
  alias ld='eza -lbDF --group-directories-first --icons=auto'   # directories only
else
  alias ll='ls -lhF'
  alias la='ls -lahF'
fi

# -----------------------------------------------------------------------------
# File viewing / search (bat, ripgrep, fd, fzf)
# -----------------------------------------------------------------------------
command -v bat >/dev/null && {
  alias b='bat'
  alias bp='bat --plain --paging=never'
  export BAT_THEME="${BAT_THEME:-TwoDark}"
}
alias grep='grep --color=auto'
command -v rg >/dev/null && alias rgi='rg -i' && alias rgl='rg -l' && alias rgc='rg --count'
command -v fd >/dev/null && alias fda='fd -HI'   # include hidden and ignored

# -----------------------------------------------------------------------------
# Editor
# -----------------------------------------------------------------------------
if command -v nvim >/dev/null; then
  alias v='nvim'
  alias vi='nvim'
  alias vim='nvim'
  export EDITOR='nvim'
  export VISUAL='nvim'
fi
alias e='${EDITOR:-vim}'
alias cl='clear'
alias reload='exec zsh'
alias zshrc='${EDITOR:-vim} ~/github/dotfiles-mac-nix/nix/user.nix'
alias icwf='${EDITOR:-vim} ~/github/dotfiles-mac-nix/files/zsh/ic-workflow.zsh'

# -----------------------------------------------------------------------------
# Git (rich set; complements the short aliases already defined in nix)
# -----------------------------------------------------------------------------
alias g='git'
alias gs='git status -sb'
alias gss='git status'
alias gd='git diff'
alias gds='git diff --staged'
alias gdw='git diff --word-diff'
alias ga='git add'
alias gap='git add -p'
alias gaa='git add -A'
alias gc='git commit -v'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gca='git commit -v --amend'
alias gcan='git commit -v --amend --no-edit'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gsw='git switch'
alias gswc='git switch -c'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gbD='git branch -D'
alias gbm='git branch -m'
alias gl='git log --oneline --graph --decorate -20'
alias gla='git log --oneline --graph --decorate --all'
alias glp='git log -p'
alias gll='git log --stat'
alias glme='git log --author="$(git config user.email)" --oneline -30'
alias gf='git fetch'
alias gfa='git fetch --all --prune'
alias gps='git push'
alias gpsf='git push --force-with-lease'
alias gpsu='git push -u origin HEAD'
alias gpl='git pull'
alias gplr='git pull --rebase'
alias gr='git remote -v'
alias grb='git rebase'
alias grbi='git rebase -i'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'
alias grs='git restore'
alias grss='git restore --staged'
alias gcp='git cherry-pick'
alias gmrg='git merge'
alias gst='git stash'
alias gstp='git stash pop'
alias gstl='git stash list'
alias gsta='git stash apply'
alias gsts='git stash show -p'
alias gundo='git reset --soft HEAD~1'
alias gunstage='git restore --staged'
alias gblame='git blame -w -C -C -C'
alias gtags='git tag --sort=-v:refname'
alias gcount='git rev-list --count HEAD'
alias gdh='git diff HEAD'
command -v lazygit >/dev/null && alias lg='lazygit'

# -----------------------------------------------------------------------------
# GitHub CLI (gh)
# -----------------------------------------------------------------------------
if command -v gh >/dev/null; then
  alias ghs='gh status'
  alias ghpr='gh pr create --fill'
  alias ghprw='gh pr view --web'
  alias ghprv='gh pr view'
  alias ghprl='gh pr list'
  alias ghprc='gh pr checkout'
  alias ghprd='gh pr diff'
  alias ghprr='gh pr review'
  alias ghprm='gh pr merge --squash --delete-branch'
  alias ghil='gh issue list'
  alias ghic='gh issue create'
  alias ghrv='gh repo view --web'
  alias ghrc='gh repo clone'
  alias ghrun='gh run list'
  alias ghwatch='gh run watch'
fi

# -----------------------------------------------------------------------------
# Docker
# -----------------------------------------------------------------------------
if command -v docker >/dev/null; then
  alias d='docker'
  alias dps='docker ps'
  alias dpsa='docker ps -a'
  alias di='docker images'
  alias dex='docker exec -it'
  alias dlog='docker logs -f'
  alias dprune='docker system prune -af --volumes'
  alias dcu='docker compose up -d'
  alias dcd='docker compose down'
  alias dcl='docker compose logs -f'
  alias dcr='docker compose restart'
fi

# -----------------------------------------------------------------------------
# Kubernetes
# -----------------------------------------------------------------------------
if command -v kubectl >/dev/null; then
  alias k='kubectl'
  alias kg='kubectl get'
  alias kgp='kubectl get pods'
  alias kgpw='kubectl get pods -w'
  alias kgs='kubectl get svc'
  alias kgd='kubectl get deploy'
  alias kga='kubectl get all'
  alias kd='kubectl describe'
  alias kl='kubectl logs -f'
  alias kx='kubectl exec -it'
  alias kaf='kubectl apply -f'
  alias kdelf='kubectl delete -f'
  alias kctx='kubectl config use-context'
  alias kns='kubectl config set-context --current --namespace'
fi
command -v k9s >/dev/null && alias k9='k9s'

# -----------------------------------------------------------------------------
# Nix / darwin
# -----------------------------------------------------------------------------
alias nbuild='darwin-rebuild build --flake ~/github/dotfiles-mac-nix#mac'
alias ncheck='nix flake check ~/github/dotfiles-mac-nix'
alias nup='nix flake update --flake ~/github/dotfiles-mac-nix'
alias ngc='nix-collect-garbage -d'
alias nsearch='nix search nixpkgs'
alias nrun='nix run'
alias nshell='nix shell'
alias ngen='darwin-rebuild --list-generations'

# -----------------------------------------------------------------------------
# Languages / build tools
# -----------------------------------------------------------------------------
command -v just >/dev/null && alias j='just' && alias jl='just --list'
alias py='python3'
alias py3='python3'
command -v uv >/dev/null && alias uvr='uv run' && alias uvpip='uv pip' && alias uvs='uv sync'
command -v ruff >/dev/null && alias rf='ruff check' && alias rff='ruff format'
alias venv='python3 -m venv .venv && source .venv/bin/activate'
alias va='source .venv/bin/activate'
alias ni='npm install'
alias nrun-dev='npm run dev'
command -v bun >/dev/null && alias bx='bunx' && alias bi='bun install' && alias br='bun run'
alias cr='cargo run'
alias cb='cargo build'
alias cbr='cargo build --release'
alias ct='cargo test'
alias cch='cargo check'
alias cclip='cargo clippy --all-targets -- -D warnings'
alias gor='go run .'
alias gob='go build ./...'
alias got='go test ./...'
command -v terraform >/dev/null && alias tf='terraform' && alias tfa='terraform apply' && alias tfp='terraform plan'

# -----------------------------------------------------------------------------
# System / macOS / monitoring
# -----------------------------------------------------------------------------
command -v btop >/dev/null && alias top='btop' && alias mem='btop'
command -v dust >/dev/null && alias sizes='dust'
command -v duf  >/dev/null && alias disk='duf'
command -v procs >/dev/null && alias pp='procs'
command -v tokei >/dev/null && alias loc='tokei'
alias ports='lsof -iTCP -sTCP:LISTEN -nP'
alias myip='curl -fsSL https://ifconfig.me; echo'
alias localip='ipconfig getifaddr en0'
alias flushdns='sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'
alias showfiles='defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder'
alias cleands='find . -type f -name .DS_Store -delete -print'
alias path='echo $PATH | tr ":" "\n"'
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias epoch='date +%s'
alias week='date +%V'
alias serve='python3 -m http.server'
alias jsonpp='jq .'
alias h='history'
alias q='exit'
alias c='clear'
alias please='sudo $(fc -ln -1)'

# =============================================================================
# Functions (fzf-powered and general helpers)
# =============================================================================

# Make a directory (and parents) and cd into it.
mkcd() { mkdir -p -- "$1" && cd -- "$1"; }

# Clone a repo and cd into it.
gclone() { git clone "$1" && cd "$(basename "${1%.git}")"; }

# Stage everything and commit with the given message.
gcom() { git add -A && git commit -m "$*"; }

# Stage everything, commit, and push.
gacp() { git add -A && git commit -m "$*" && git push; }

# Jump to the git repo root.
groot() { cd "$(git rev-parse --show-toplevel 2>/dev/null)" || return 1; }

# Timestamped backup copy of a file or directory.
bak() { cp -a -- "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"; }

# Generate a strong random password (default 24 chars).
genpass() { LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*_-' < /dev/urandom | head -c "${1:-24}"; echo; }

# Kill whatever is listening on a TCP port.
killport() { lsof -ti tcp:"$1" | xargs -r kill -9 && echo "killed listeners on :$1"; }

# Universal archive extractor.
extract() {
  local f="$1"
  [ -f "$f" ] || { echo "extract: '$f' is not a file" >&2; return 1; }
  case "$f" in
    *.tar.bz2|*.tbz2) tar xjf "$f" ;;
    *.tar.gz|*.tgz)   tar xzf "$f" ;;
    *.tar.xz)         tar xJf "$f" ;;
    *.tar.zst)        tar --zstd -xf "$f" ;;
    *.tar)            tar xf "$f" ;;
    *.bz2)            bunzip2 "$f" ;;
    *.gz)             gunzip "$f" ;;
    *.xz)             unxz "$f" ;;
    *.zip)            unzip "$f" ;;
    *.rar)            unrar x "$f" ;;
    *.7z)             7z x "$f" ;;
    *.Z)              uncompress "$f" ;;
    *) echo "extract: unknown archive type for '$f'" >&2; return 1 ;;
  esac
}

# Look up a command cheatsheet from cheat.sh.
cheat() { curl -fsSL "cheat.sh/${1:?usage: cheat <command>}"; }

# fzf: ripgrep across the tree, preview matches, open the pick in nvim at the line.
frg() {
  command -v rg >/dev/null && command -v fzf >/dev/null || { echo "frg needs rg and fzf" >&2; return 1; }
  local result file line
  result=$(rg --line-number --no-heading --color=always --smart-case "${*:-}" 2>/dev/null \
    | fzf --ansi --delimiter : \
        --preview 'bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null || cat {1}' \
        --preview-window 'up,60%,border-bottom,+{2}+3/3,~3') || return
  file=${result%%:*}
  line=$(printf '%s' "$result" | cut -d: -f2)
  [ -n "$file" ] && ${EDITOR:-nvim} "+$line" "$file"
}

# fzf: open a file in the editor with a bat preview.
fv() {
  command -v fzf >/dev/null || return 1
  local file
  file=$(fd --type f --hidden --exclude .git 2>/dev/null | \
    fzf --preview 'bat --style=numbers --color=always {} 2>/dev/null || cat {}') || return
  [ -n "$file" ] && ${EDITOR:-nvim} "$file"
}

# fzf: cd into a directory chosen interactively.
fcd() {
  command -v fzf >/dev/null || return 1
  local dir
  dir=$(fd --type d --hidden --exclude .git ${1:+. "$1"} 2>/dev/null | fzf) || return
  [ -n "$dir" ] && cd "$dir"
}

# fzf: switch git branch interactively.
fco() {
  command -v fzf >/dev/null || return 1
  local branch
  branch=$(git branch --all --color=always 2>/dev/null | grep -v HEAD \
    | sed 's/^[* ]*//' | fzf --ansi | sed 's#remotes/[^/]*/##') || return
  [ -n "$branch" ] && { git switch "$branch" 2>/dev/null || git checkout "$branch"; }
}

# fzf: pick processes and kill them (signal optional, default TERM).
fkill() {
  command -v fzf >/dev/null || return 1
  local pids
  pids=$(ps -ef | sed 1d | fzf -m --header='select process(es) to kill' | awk '{print $2}') || return
  [ -n "$pids" ] && echo "$pids" | xargs kill "-${1:-TERM}" && echo "sent ${1:-TERM} to: $(echo $pids | tr '\n' ' ')"
}

# fzf: jump to a project directory under ~/github (or $PROJECTS).
proj() {
  command -v fzf >/dev/null || return 1
  local base="${PROJECTS:-$HOME/github}" dir
  dir=$(fd --type d --max-depth 2 --hidden --exclude .git . "$base" 2>/dev/null \
    | sed "s#$base/##" | fzf --prompt 'project> ') || return
  [ -n "$dir" ] && cd "$base/$dir"
}

# fzf: exec a shell inside a running docker container.
dsh() {
  command -v docker >/dev/null && command -v fzf >/dev/null || return 1
  local cid
  cid=$(docker ps --format '{{.ID}}\t{{.Names}}\t{{.Image}}' | fzf | awk '{print $1}') || return
  [ -n "$cid" ] && docker exec -it "$cid" "${1:-sh}"
}

# =============================================================================
# Integrated forked tooling (clones under ~/github, synced weekly by sync-forks)
# =============================================================================
command -v treehouse   >/dev/null && alias th='treehouse'
command -v no-mistakes >/dev/null && alias nm='no-mistakes'
command -v gnhf        >/dev/null && alias gn='gnhf'
command -v chrome-devtools-axi >/dev/null && alias cda='chrome-devtools-axi'
command -v tasks-axi   >/dev/null && alias ta='tasks-axi'
command -v quota-axi   >/dev/null && alias qa='quota-axi'
alias syncforks='$HOME/github/dotfiles-mac-nix/files/bin/sync-forks'
alias syncforks-dry='$HOME/github/dotfiles-mac-nix/files/bin/sync-forks --dry-run'
alias icdoctor='$HOME/github/dotfiles-mac-nix/files/bin/ic-doctor'

# firstmate is launched from inside its workspace; cd there and optionally
# start an agent: `firstmate` (just cd) or `firstmate claude` (cd + launch).
firstmate() {
  cd "$HOME/github/firstmate" || return 1
  [ "$#" -gt 0 ] && command "$@"
}
alias fm='firstmate'
