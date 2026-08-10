<#
.SYNOPSIS
  Bootstrap this setup on Windows by way of WSL2.

.DESCRIPTION
  Nix has no native Windows support, so there is no such thing as installing
  this configuration on Windows proper. What this script does instead is make
  WSL2 ready and then run the normal Linux bootstrap inside it:

    1. verify or enable WSL2
    2. install a distro if none is present
    3. clone this repo *inside* the distro's own filesystem
    4. run setup/install.sh --target wsl in there

  Step 3 matters. The repo must live at ~/github/dotfiles-nix inside the distro,
  not on /mnt/c. The config links files out of the checkout by absolute path, so
  a Windows-side checkout would leave every one of those links pointing at a
  path that only resolves while the drive is mounted; it is also markedly slower
  across the 9p filesystem boundary. setup/linux.sh enforces this with the same
  checkout-path guard setup/mac.sh uses, so a /mnt/c checkout is refused rather
  than silently half-installed.

.PARAMETER Distro
  Distro to use or install. Defaults to Ubuntu.

.PARAMETER RepoUrl
  Repository to clone inside WSL.

.PARAMETER DryRun
  Print what would happen without changing anything.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup\windows.ps1

.NOTES
  Enabling the WSL feature may require a reboot; the script says so and stops
  rather than pretending the install finished.
#>

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu',
  [string]$RepoUrl = 'https://github.com/shreejitverma/dotfiles-nix.git',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Host "warning: $Message" -ForegroundColor Yellow }

function Test-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($DryRun) {
  Write-Host 'dry-run: no changes will be made.'
}

# --- 1. Is WSL present at all? -----------------------------------------------

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
  if (-not (Test-Administrator)) {
    throw 'WSL is not installed and enabling it needs an elevated shell. Re-run this script from an Administrator PowerShell.'
  }
  Write-Step 'Enabling WSL2 and installing a distro (this may require a reboot)'
  if (-not $DryRun) {
    wsl.exe --install -d $Distro
    Write-Host ''
    Write-Host 'WSL was just enabled. Reboot Windows, then re-run this script to finish the setup.' -ForegroundColor Green
  }
  exit 0
}

# --- 2. Make sure a usable distro exists -------------------------------------

# `wsl --list --quiet` emits UTF-16 with NUL bytes; strip them or every
# comparison below silently fails to match.
$installed = @()
if (-not $DryRun) {
  $raw = (wsl.exe --list --quiet) 2>$null
  if ($LASTEXITCODE -eq 0 -and $raw) {
    $installed = $raw -split "`r?`n" | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -ne '' }
  }
}

if ($installed.Count -eq 0) {
  Write-Step "No WSL distro found; installing $Distro"
  if (-not $DryRun) {
    wsl.exe --install -d $Distro
    Write-Host ''
    Write-Host "$Distro was installed. Open it once to create your user account, then re-run this script." -ForegroundColor Green
  }
  exit 0
}

if ($installed -notcontains $Distro) {
  Write-Warn "Distro '$Distro' is not installed. Found: $($installed -join ', ')"
  Write-Warn "Using '$($installed[0])' instead. Pass -Distro to choose a different one."
  $Distro = $installed[0]
}

Write-Step "Using WSL distro: $Distro"

# Confirm it is WSL2. WSL1 has no real kernel and the Nix daemon does not work
# there, so installing would fail later and less clearly than it does here.
if (-not $DryRun) {
  $verbose = (wsl.exe --list --verbose) 2>$null
  if ($verbose) {
    $clean = ($verbose -replace "`0", '')
    $line = $clean -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($Distro) } | Select-Object -First 1
    if ($line -and $line -notmatch '\s2\s*$') {
      throw "Distro '$Distro' is not running under WSL2. Convert it first: wsl --set-version $Distro 2"
    }
  }
}

# --- 3. Clone inside the distro and run the Linux bootstrap ------------------

# Single-quoted here-string: PowerShell must not expand any of this. $RepoUrl is
# injected afterwards so the URL cannot be mangled by PowerShell's parser.
$bootstrap = @'
set -euo pipefail
if ! command -v git >/dev/null 2>&1; then
  echo "==> installing git"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq git curl
  else
    echo "git is not installed and this distro is not apt-based. Install git and curl, then re-run." >&2
    exit 1
  fi
fi
mkdir -p "$HOME/github"
if [ ! -d "$HOME/github/dotfiles-nix/.git" ]; then
  echo "==> cloning into $HOME/github/dotfiles-nix"
  git clone --depth=1 "__REPO_URL__" "$HOME/github/dotfiles-nix"
fi
cd "$HOME/github/dotfiles-nix"
exec bash setup/install.sh --target wsl --yes
'@

$bootstrap = $bootstrap.Replace('__REPO_URL__', $RepoUrl)
# WSL reads the script over stdin as a Linux file; CRLF would break the shebang
# handling and the here-doc, so normalise line endings before handing it over.
$bootstrap = $bootstrap.Replace("`r`n", "`n")

Write-Step "Running the Linux bootstrap inside $Distro"

if ($DryRun) {
  Write-Host '--- would run inside WSL ---'
  Write-Host $bootstrap
  Write-Host '--- end ---'
  exit 0
}

$bootstrap | wsl.exe -d $Distro -- bash -s
if ($LASTEXITCODE -ne 0) {
  throw "The WSL bootstrap failed with exit code $LASTEXITCODE."
}

Write-Host ''
Write-Host "Done. Open $Distro and restart your shell to pick up the new environment." -ForegroundColor Green
