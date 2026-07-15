{ config, pkgs, ... }:

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles-mac-nix";
in
{
  home.username = "shreejitverma";
  home.homeDirectory = "/Users/shreejitverma";
  home.stateVersion = "23.11";
  home.language.base = "en_US.UTF-8";

  home.packages = with pkgs; [
    git
    curl
    wget
    jq
    fd
    fastfetch
    ripgrep
    killall
    lazygit
    tree
    bun
    rustup
    zip
    unzip

    # IC workflow CLI tools.
    # eza, zoxide, delta, atuin, bat, fzf are installed by the programs.* modules below.
    just
    dust
    duf
    procs
    sd
    btop
    tokei
    tealdeer
    uv
    ruff
    difftastic

    nerd-fonts.hack
    roboto
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    font-awesome
  ];

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "vim";
  };

  # Keep user-local binaries (e.g. the Claude CLI) and repo scripts on PATH.
  home.sessionPath = [
    "$HOME/.local/bin"
    "${dotfilesDir}/files/bin"
  ];

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = null;
    settings = {
      user = {
        name = "Shreejit Verma";
        email = "shreejitverma@gmail.com";
      };
      core.editor = "vim";
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = true;
      rebase.updateRefs = true;
      init.defaultBranch = "main";
      merge.conflictStyle = "zdiff3";
      diff.algorithm = "histogram";
      diff.colorMoved = "default";
      fetch.prune = true;
      rerere.enabled = true;
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = false;
      syntax-theme = "TwoDark";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      command_timeout = 1000;
      add_newline = false;
      format = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$line_break$character";

      directory.style = "blue";

      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
      };

      git_branch = {
        format = "[$branch]($style)";
        style = "bright-black";
      };

      git_status = {
        format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
        style = "cyan";
        stashed = "≡";
      };

      git_state = {
        format = "\\([$state( $progress_current/$progress_total)]($style)\\) ";
        style = "bright-black";
      };

      cmd_duration = {
        format = "[$duration]($style) ";
        style = "yellow";
      };

      python = {
        format = "[$virtualenv]($style) ";
        style = "bright-black";
      };
    };
  };

  # Modern CLI tools with first-class zsh integration, wired reproducibly.
  programs.eza.enable = true;

  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
      style = "numbers,changes,header";
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    defaultOptions = [ "--height 60%" "--layout=reverse" "--border" "--info=inline" ];
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetOptions = [ "--preview 'bat --style=numbers --color=always {} 2>/dev/null || cat {}'" ];
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
    changeDirWidgetOptions = [ "--preview 'eza --tree --level=2 --color=always {} 2>/dev/null || ls {}'" ];
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    flags = [ "--disable-up-arrow" ];
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ".." = "cd ..";
      m = "git switch main";
      mst = "git switch master";
      pull = "git pull";
      push = "git push";
      pushf = "git push --force";
      add = "git add .";
      amend = "git commit --amend";
      reset = "git reset --soft HEAD^";
      rebasem = "git rebase -i main";
      rebasemst = "git rebase -i master";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
      rebuild = "/run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles-mac-nix#mac";
    };
    initContent = ''
      bindkey '^f' autosuggest-accept

      # IC workflow: exhaustive aliases, functions, and shell options.
      # Kept in the repo so it can be edited without a full rebuild.
      [ -f "${dotfilesDir}/files/zsh/ic-workflow.zsh" ] && source "${dotfilesDir}/files/zsh/ic-workflow.zsh"
    '';
  };

  # Weekly sync of forked tooling (~/github/*) with their upstream parents.
  # Runs Sundays at 10:00. The script merges upstream, pushes your fork, and
  # rebuilds the tools. Logs land in ~/Library/Logs/sync-forks*.log.
  launchd.agents.sync-forks = {
    enable = true;
    config = {
      ProgramArguments = [ "${dotfilesDir}/files/bin/sync-forks" ];
      StartCalendarInterval = [
        { Weekday = 0; Hour = 10; Minute = 0; }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sync-forks.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sync-forks.err.log";
      RunAtLoad = false;
      ProcessType = "Background";
    };
  };

  home.file = {
    ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/wezterm";
    # ~/.config/nvim is deliberately NOT managed here: it is its own git repo
    # (github.com/shreejitverma/kickstart.nvim) checked out in place.
    ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/herdr";
  };
}
