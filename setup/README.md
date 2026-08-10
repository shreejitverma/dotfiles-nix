# Bootstrap

Run `setup/install.sh` **after** cloning this repo and **after** replacing the placeholder values in the Nix files.

Typical flow:

1. Clone the repo
2. Replace placeholder values such as:
   - `yourname`
   - `/Users/yourname` or `/home/yourname`
   - `Your Name`
   - `you@example.com`
3. Run:

```bash
bash setup/install.sh
```

`install.sh` detects macOS, Linux, or WSL, shows what it found, and lets you confirm or override before installing.
It then dispatches to `setup/mac.sh` or `setup/linux.sh`.
Use `--target <darwin|linux|wsl>` to skip detection, `--yes` to skip the prompt, and `--dry-run` to print the plan without installing.

On Windows, run `setup/windows.ps1` from PowerShell instead: Nix has no native Windows build, so that script sets up WSL2 and runs the Linux bootstrap inside it.

What `setup/mac.sh` does:

- checks that you replaced the placeholder values first
- checks that the checkout sits at the `dotfilesDir` path declared in `nix/user.nix`, since everything the activation links (app configs, the `files/bin` PATH entry, the zsh workflow layer, the `sync-forks` agent) is built from that literal and would otherwise dangle silently
- installs Determinate Nix Installer if needed
- installs Homebrew if needed
- applies the `nix-darwin` + Home Manager configuration
- installs `nvm` and a default Node.js version if needed

What `setup/linux.sh` does:

- the same placeholder check, and the same checkout-path check against whichever entry module backs the profile it is activating (`nix/linux-user.nix` or `nix/wsl-user.nix`), which is also what refuses a WSL checkout on `/mnt/c`
- names the shell startup files Home Manager is about to take over, and stops before installing anything if one of them is a symlink Home Manager cannot back up
- installs Determinate Nix if needed, asking for `--init none` wherever systemd is not PID 1
- builds the Home Manager profile from this flake's pinned `flake.lock` and activates it, without `sudo`: nothing outside `$HOME` and the per-user Nix profile is touched
- installs `nvm` and a default Node.js version if needed

These scripts are meant for the **first bootstrap on a new machine**. After that, most ongoing changes should happen by editing the Nix config and running the `rebuild` alias.

Both are designed to complete in a single run: right after installing Nix they source the daemon profile into the current shell and resolve `nix` by absolute path with the experimental features it needs, so you should **not** need to run them twice or open a new shell partway through.

`NIX_DAEMON_PROFILE`, `DARWIN_REBUILD_BIN`, `WSL_OSRELEASE_FILE`, and `WSL_VERSION_FILE` are overridable only so the regression tests can point the scripts at sandboxed paths.
For normal bootstrap usage, leave them unset.

## Testing

These scripts install Nix and activate a real machine, so no suite ever runs one against the host:

```bash
bash tests/mac_setup_test.sh        # setup/mac.sh, stubbed
bash tests/install_dispatch_test.sh # setup/install.sh detection and dispatch, stubbed
bash tests/linux_e2e_docker.sh      # real Linux and WSL install in a container
```

The first two run the real script logic against a PATH-masked sandbox of stub executables, so nothing is installed or activated, and they run anywhere.
See [`tests/README.md`](../tests/README.md) for the scenarios each suite covers and how the sandbox is guarded.
