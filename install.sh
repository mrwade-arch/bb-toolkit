#!/usr/bin/env bash
# =============================================================================
# Bug Bounty Toolkit Installer for Arch Linux
# Version: 1.0.0
# =============================================================================
# One-liner install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USER/bb-toolkit/main/install.sh)
#
# Or after downloading:
#   chmod +x install.sh && ./install.sh
#
# Options:
#   ./install.sh            — Full install
#   ./install.sh --update   — Update all tools
#   ./install.sh --uninstall — Remove everything
# =============================================================================

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Config ───────────────────────────────────────────────────────────────────
BB_HOME="$HOME/bugbounty"
BB_CONFIG="$HOME/.bugbounty"
BB_BIN="$HOME/.local/bin"
BB_TOOLS_JSON="$(dirname "$(realpath "$0")")/tools.json"
LOG_FILE="/tmp/bb-install-$(date +%Y%m%d_%H%M%S).log"
INSTALL_MODE="install"   # install | update | uninstall

# Track install failures
FAILED_TOOLS=()
SKIPPED_TOOLS=()
INSTALLED_TOOLS=()

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[*]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE" >&2; }
step()    { echo -e "\n${BLUE}${BOLD}═══ $* ═══${NC}\n" | tee -a "$LOG_FILE"; }
prompt()  { echo -e "${MAGENTA}[?]${NC} $*"; }
skip()    { echo -e "${YELLOW}[→]${NC} Already installed: $* (skipping)" | tee -a "$LOG_FILE"; }

banner() {
  clear
  echo -e "${MAGENTA}"
  cat <<'EOF'
  ██████╗ ██╗   ██╗ ██████╗     ██████╗  ██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗
  ██╔══██╗██║   ██║██╔════╝     ██╔══██╗██╔═══██╗██║   ██║████╗  ██║╚══██╔══╝╚██╗ ██╔╝
  ██████╔╝██║   ██║██║  ███╗    ██████╔╝██║   ██║██║   ██║██╔██╗ ██║   ██║    ╚████╔╝
  ██╔══██╗██║   ██║██║   ██║    ██╔══██╗██║   ██║██║   ██║██║╚██╗██║   ██║     ╚██╔╝
  ██████╔╝╚██████╔╝╚██████╔╝    ██████╔╝╚██████╔╝╚██████╔╝██║ ╚████║   ██║      ██║
  ╚═════╝  ╚═════╝  ╚═════╝     ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝      ╚═╝

          ████████╗ ██████╗  ██████╗ ██╗     ██╗  ██╗██╗████████╗
          ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██║ ██╔╝██║╚══██╔══╝
             ██║   ██║   ██║██║   ██║██║     █████╔╝ ██║   ██║
             ██║   ██║   ██║██║   ██║██║     ██╔═██╗ ██║   ██║
             ██║   ╚██████╔╝╚██████╔╝███████╗██║  ██╗██║   ██║
             ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝   ╚═╝
EOF
  echo -e "${NC}"
  echo -e "${BOLD}  Arch Linux Bug Bounty Toolkit | v1.0.0${NC}"
  echo -e "${RED}  ⚠  For authorized security testing only${NC}"
  echo ""
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)    INSTALL_MODE="update"; shift ;;
    --uninstall) INSTALL_MODE="uninstall"; shift ;;
    -h|--help)
      echo "Usage: $0 [--update | --uninstall]"
      exit 0
      ;;
    *) shift ;;
  esac
done

# ─── Pre-flight Checks ────────────────────────────────────────────────────────
preflight_checks() {
  step "Pre-flight Checks"

  # Must not be root
  if [[ $EUID -eq 0 ]]; then
    error "Do NOT run this installer as root."
    error "Run as your regular user. sudo will be used internally where needed."
    exit 1
  fi
  success "Running as user: $USER"

  # Must be Arch Linux
  if ! grep -qi "arch" /etc/os-release 2>/dev/null; then
    warn "This installer is designed for Arch Linux."
    prompt "Continue on this non-Arch system? (yes/no)"
    read -r REPLY
    [[ "${REPLY,,}" != "yes" ]] && exit 0
  else
    success "Arch Linux detected"
  fi

  # Check internet
  if ! curl -fsS --max-time 5 https://archlinux.org > /dev/null 2>&1; then
    error "No internet connection detected. Please check your connection."
    exit 1
  fi
  success "Internet connection: OK"

  # Check for sudo
  if ! command -v sudo &>/dev/null; then
    error "sudo is not installed. Please install it first: pacman -S sudo"
    exit 1
  fi
  success "sudo: available"

  # Check for zsh
  if ! command -v zsh &>/dev/null; then
    warn "zsh not found. Installing..."
    sudo pacman -S --noconfirm zsh
  fi
  success "zsh: available"
}

# ─── AUR Helper Setup ─────────────────────────────────────────────────────────
setup_aur_helper() {
  step "AUR Helper Setup"

  AUR_HELPER=""

  if command -v yay &>/dev/null; then
    AUR_HELPER="yay"
    skip "yay (AUR helper)"
    return 0
  fi

  if command -v paru &>/dev/null; then
    AUR_HELPER="paru"
    skip "paru (AUR helper)"
    return 0
  fi

  info "No AUR helper found. Options:"
  echo "  1) Install yay (recommended — most popular)"
  echo "  2) Install paru (Rust-based, faster)"
  echo "  3) Skip (AUR packages won't be installed)"
  prompt "Your choice [1/2/3]:"
  read -r AUR_CHOICE

  case "${AUR_CHOICE}" in
    1|"")
      info "Installing yay..."
      sudo pacman -S --needed --noconfirm base-devel git
      local tmp_dir
      tmp_dir=$(mktemp -d)
      git clone https://aur.archlinux.org/yay.git "$tmp_dir/yay" 2>/dev/null
      (cd "$tmp_dir/yay" && makepkg -si --noconfirm)
      rm -rf "$tmp_dir"
      AUR_HELPER="yay"
      success "yay installed"
      ;;
    2)
      info "Installing paru..."
      sudo pacman -S --needed --noconfirm base-devel git
      local tmp_dir
      tmp_dir=$(mktemp -d)
      git clone https://aur.archlinux.org/paru.git "$tmp_dir/paru" 2>/dev/null
      (cd "$tmp_dir/paru" && makepkg -si --noconfirm)
      rm -rf "$tmp_dir"
      AUR_HELPER="paru"
      success "paru installed"
      ;;
    3)
      warn "Skipping AUR helper. Some tools won't be installed."
      AUR_HELPER=""
      ;;
  esac
}

# ─── System Update ────────────────────────────────────────────────────────────
system_update() {
  step "System Package Update"
  info "Running pacman -Syu (this may take a few minutes)..."
  sudo pacman -Syu --noconfirm 2>&1 | tail -5
  success "System updated"
}

# ─── BlackArch Repo (Optional) ────────────────────────────────────────────────
setup_blackarch() {
  step "BlackArch Repository (Optional)"

  if grep -q "\[blackarch\]" /etc/pacman.conf 2>/dev/null; then
    skip "BlackArch repository (already configured)"
    return 0
  fi

  echo ""
  echo -e "${BOLD}BlackArch is an Arch Linux overlay repository with 2800+ security tools.${NC}"
  echo "Adding it gives access to extra pen-testing tools via pacman."
  echo "Official source: https://blackarch.org/strap.sh"
  echo ""
  prompt "Add BlackArch repository? (yes/no) [no]:"
  read -r BA_REPLY

  if [[ "${BA_REPLY,,}" == "yes" ]]; then
    info "Adding BlackArch repository..."
    if curl -fsSL https://blackarch.org/strap.sh | sha1sum -c - 2>/dev/null || true; then
      curl -fsSL https://blackarch.org/strap.sh -o /tmp/blackarch-strap.sh
      chmod +x /tmp/blackarch-strap.sh
      sudo /tmp/blackarch-strap.sh
      rm -f /tmp/blackarch-strap.sh
      success "BlackArch repository added"
    else
      warn "BlackArch strap.sh checksum failed — skipping for security"
    fi
  else
    info "Skipping BlackArch repository"
  fi
}

# ─── Install Base Packages ────────────────────────────────────────────────────
install_pacman_packages() {
  step "Installing Base Packages (pacman)"

  if ! command -v jq &>/dev/null; then
    # Install jq first so we can parse tools.json
    sudo pacman -S --needed --noconfirm jq
  fi

  if [[ ! -f "$BB_TOOLS_JSON" ]]; then
    warn "tools.json not found at $BB_TOOLS_JSON"
    warn "Falling back to hardcoded package list"
    PACMAN_PKGS="go python python-pipx git curl wget jq nmap masscan ffuf sqlmap nikto chromium whatweb dirb bind whois traceroute unzip parallel base-devel"
    sudo pacman -S --needed --noconfirm $PACMAN_PKGS
    return
  fi

  local packages
  packages=$(jq -r '.pacman_packages[].package' "$BB_TOOLS_JSON" 2>/dev/null | tr '\n' ' ')

  info "Installing: $packages"
  sudo pacman -S --needed --noconfirm $packages 2>&1 | \
    grep -E "installing|is up to date|error" || true

  success "Base packages installed"
}

# ─── Install AUR Packages ─────────────────────────────────────────────────────
install_aur_packages() {
  step "Installing AUR Packages"

  if [[ -z "${AUR_HELPER:-}" ]]; then
    warn "No AUR helper configured — skipping AUR packages"
    return 0
  fi

  if [[ ! -f "$BB_TOOLS_JSON" ]]; then
    warn "tools.json not found — skipping AUR packages"
    return
  fi

  while IFS= read -r pkg; do
    local name
    name=$(echo "$pkg" | jq -r '.name')
    local package
    package=$(echo "$pkg" | jq -r '.package')

    if $AUR_HELPER -Q "$package" &>/dev/null 2>&1; then
      skip "$name ($package)"
      SKIPPED_TOOLS+=("$name")
    else
      info "Installing $name from AUR..."
      if $AUR_HELPER -S --needed --noconfirm "$package" 2>&1 | tail -3; then
        success "$name installed"
        INSTALLED_TOOLS+=("$name")
      else
        warn "Failed to install $name from AUR"
        FAILED_TOOLS+=("$name")
      fi
    fi
  done < <(jq -c '.aur_packages[]' "$BB_TOOLS_JSON" 2>/dev/null)
}

# ─── Go Environment Setup ─────────────────────────────────────────────────────
setup_go_env() {
  step "Go Environment Setup"

  if ! command -v go &>/dev/null; then
    error "Go is not installed. Something went wrong with pacman install."
    exit 1
  fi

  GO_VERSION=$(go version | awk '{print $3}')
  success "Go version: $GO_VERSION"

  export GOPATH="$HOME/go"
  export GOBIN="$HOME/go/bin"
  export PATH="$GOBIN:$PATH"

  mkdir -p "$GOBIN"

  # Ensure PATH is in .zshrc already / will be handled by aliases.zsh
  success "GOPATH=$GOPATH, GOBIN=$GOBIN"
}

# ─── Install Go Tools ─────────────────────────────────────────────────────────
install_go_tools() {
  step "Installing Go Tools"

  if [[ ! -f "$BB_TOOLS_JSON" ]]; then
    warn "tools.json not found — skipping Go tools"
    return
  fi

  while IFS= read -r tool; do
    local name
    name=$(echo "$tool" | jq -r '.name')
    local install_cmd
    install_cmd=$(echo "$tool" | jq -r '.install')

    local binary_name="${name%%@*}"
    binary_name="${binary_name##*/}"

    if [[ "$INSTALL_MODE" == "install" ]] && command -v "$binary_name" &>/dev/null; then
      skip "$name"
      SKIPPED_TOOLS+=("$name")
      continue
    fi

    info "Installing $name..."
    if eval "$install_cmd" >> "$LOG_FILE" 2>&1; then
      success "$name installed → $GOBIN/$binary_name"
      INSTALLED_TOOLS+=("$name")
    else
      warn "Failed to install $name"
      FAILED_TOOLS+=("$name")
    fi
  done < <(jq -c '.go_tools[]' "$BB_TOOLS_JSON" 2>/dev/null)
}

# ─── Python pipx Tools ────────────────────────────────────────────────────────
install_pipx_tools() {
  step "Installing Python Tools (pipx)"

  if ! command -v pipx &>/dev/null; then
    warn "pipx not found — attempting install"
    python3 -m pip install --user pipx 2>/dev/null || \
      sudo pacman -S --needed --noconfirm python-pipx
  fi

  # Ensure pipx bin in PATH
  pipx ensurepath >> "$LOG_FILE" 2>&1 || true
  export PATH="$HOME/.local/bin:$PATH"

  if [[ ! -f "$BB_TOOLS_JSON" ]]; then
    warn "tools.json not found — skipping pipx tools"
    return
  fi

  while IFS= read -r tool; do
    local name
    name=$(echo "$tool" | jq -r '.name')
    local package
    package=$(echo "$tool" | jq -r '.package')

    if [[ "$INSTALL_MODE" == "install" ]] && pipx list 2>/dev/null | grep -q "$name"; then
      skip "$name (pipx)"
      SKIPPED_TOOLS+=("$name")
      continue
    fi

    info "Installing $name via pipx..."
    if pipx install "$package" >> "$LOG_FILE" 2>&1 || \
       pipx install "$package" --force >> "$LOG_FILE" 2>&1; then
      success "$name installed"
      INSTALLED_TOOLS+=("$name")
    else
      warn "Failed to install $name via pipx"
      FAILED_TOOLS+=("$name")
    fi
  done < <(jq -c '.pipx_tools[]' "$BB_TOOLS_JSON" 2>/dev/null)
}

# ─── ProjectDiscovery Tool Manager ───────────────────────────────────────────
install_pdtm() {
  step "ProjectDiscovery Tool Manager (pdtm)"

  if ! command -v pdtm &>/dev/null; then
    info "Installing pdtm..."
    go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest >> "$LOG_FILE" 2>&1 || {
      warn "pdtm install failed"
      return
    }
  fi

  success "pdtm available"
  info "Installing ProjectDiscovery tools via pdtm..."
  pdtm -install-all -ua 2>&1 | tee -a "$LOG_FILE" | grep -E "installed|updated|failed|error" || true
  success "ProjectDiscovery suite updated via pdtm"
}

# ─── Nuclei Templates ─────────────────────────────────────────────────────────
setup_nuclei_templates() {
  step "Nuclei Templates"

  if ! command -v nuclei &>/dev/null; then
    warn "nuclei not found — skipping template setup"
    return
  fi

  info "Updating nuclei templates (official)..."
  nuclei -update-templates >> "$LOG_FILE" 2>&1 || warn "Template update failed"

  # Custom templates directory
  mkdir -p "$BB_CONFIG/nuclei-templates"

  # Clone community templates
  COMMUNITY_TEMPLATES=(
    "https://github.com/projectdiscovery/fuzzing-templates"
    "https://github.com/geeknik/the-nuclei-templates"
  )

  for template_repo in "${COMMUNITY_TEMPLATES[@]}"; do
    local repo_name
    repo_name=$(basename "$template_repo")
    local dest="$BB_CONFIG/nuclei-templates/$repo_name"

    if [[ -d "$dest" ]]; then
      info "Updating community templates: $repo_name"
      git -C "$dest" pull --quiet 2>/dev/null || true
    else
      info "Cloning community templates: $repo_name"
      git clone --depth 1 "$template_repo" "$dest" >> "$LOG_FILE" 2>&1 || \
        warn "Failed to clone $template_repo"
    fi
  done

  success "Nuclei templates ready"
}

# ─── gf Patterns ─────────────────────────────────────────────────────────────
setup_gf_patterns() {
  step "gf Patterns"

  if ! command -v gf &>/dev/null; then
    warn "gf not found — skipping pattern setup"
    return
  fi

  GF_PATTERNS_DIR="$HOME/.gf"
  mkdir -p "$GF_PATTERNS_DIR"

  # 1s0han gf-patterns (the go-to community patterns)
  local patterns_dir="/tmp/gf-patterns-$$"
  git clone --depth 1 https://github.com/1ndianl33t/Gf-Patterns "$patterns_dir" >> "$LOG_FILE" 2>&1 || true

  if [[ -d "$patterns_dir" ]]; then
    cp "$patterns_dir/"*.json "$GF_PATTERNS_DIR/" 2>/dev/null || true
    rm -rf "$patterns_dir"
    success "gf patterns installed → $GF_PATTERNS_DIR"
  else
    warn "Failed to clone gf patterns"
  fi

  # tomnomnom's example patterns
  local tn_dir="/tmp/gf-tn-$$"
  git clone --depth 1 https://github.com/tomnomnom/gf "$tn_dir" >> "$LOG_FILE" 2>&1 || true
  if [[ -d "$tn_dir/examples" ]]; then
    cp "$tn_dir/examples/"*.json "$GF_PATTERNS_DIR/" 2>/dev/null || true
    rm -rf "$tn_dir"
  fi
}

# ─── Wordlists ────────────────────────────────────────────────────────────────
install_wordlists() {
  step "Wordlists"

  mkdir -p "$HOME/wordlists"

  # SecLists
  if [[ -d "$HOME/wordlists/SecLists" ]]; then
    info "SecLists already present"
    prompt "Update SecLists? (yes/no) [no]:"
    read -r SL_UPDATE
    if [[ "${SL_UPDATE,,}" == "yes" ]]; then
      git -C "$HOME/wordlists/SecLists" pull --quiet
      success "SecLists updated"
    else
      skip "SecLists"
    fi
  else
    prompt "Install SecLists? (~1.8GB) (yes/no) [yes]:"
    read -r SL_INSTALL
    if [[ "${SL_INSTALL,,}" != "no" ]]; then
      info "Cloning SecLists (this may take a few minutes)..."
      git clone --depth 1 https://github.com/danielmiessler/SecLists \
        "$HOME/wordlists/SecLists" >> "$LOG_FILE" 2>&1
      success "SecLists installed → ~/wordlists/SecLists"
    else
      info "Skipping SecLists"
    fi
  fi
}

# ─── Directory Structure ──────────────────────────────────────────────────────
setup_directories() {
  step "Directory Structure"

  mkdir -p "$BB_HOME"/{notes,wordlists,reports,templates}
  mkdir -p "$BB_CONFIG"/{nuclei-templates,configs}
  mkdir -p "$BB_BIN"

  success "Directories created:"
  success "  ~/bugbounty/          — Main workspace"
  success "  ~/.bugbounty/         — Config & custom templates"
  success "  ~/.local/bin/         — Custom scripts"
}

# ─── Install Custom Scripts ───────────────────────────────────────────────────
install_custom_scripts() {
  step "Installing Custom Scripts"

  local script_dir
  script_dir="$(dirname "$(realpath "$0")")"

  for script in bb-recon bb-scan bb-idor; do
    local src="${script_dir}/${script}"
    local dest="${BB_BIN}/${script}"

    if [[ -f "$src" ]]; then
      cp "$src" "$dest"
      chmod +x "$dest"
      success "Installed: $dest"
    else
      warn "$script not found in $(dirname "$0") — skipping"
    fi
  done
}

# ─── Shell Integration ────────────────────────────────────────────────────────
setup_shell() {
  step "Shell Integration (zsh)"

  # Install aliases
  local aliases_src
  aliases_src="$(dirname "$(realpath "$0")")/aliases.zsh"

  if [[ -f "$aliases_src" ]]; then
    cp "$aliases_src" "$BB_CONFIG/aliases.zsh"
    success "aliases.zsh installed → $BB_CONFIG/aliases.zsh"
  else
    warn "aliases.zsh not found — shell shortcuts won't be set up"
    return
  fi

  local ZSHRC="$HOME/.zshrc"
  local SOURCE_LINE="source \"\$HOME/.bugbounty/aliases.zsh\""

  if grep -qF "bb-toolkit" "$ZSHRC" 2>/dev/null || \
     grep -qF "aliases.zsh" "$ZSHRC" 2>/dev/null; then
    skip "~/.zshrc already sourcing aliases"
    return
  fi

  # Backup .zshrc before modifying
  if [[ -f "$ZSHRC" ]]; then
    cp "$ZSHRC" "${ZSHRC}.bb-backup-$(date +%Y%m%d_%H%M%S)"
    success "~/.zshrc backed up"
  fi

  cat >> "$ZSHRC" <<ZSHRC_BLOCK

# ─── Bug Bounty Toolkit ──────────────────────────────────────────────────────
${SOURCE_LINE}
ZSHRC_BLOCK

  success "Added to ~/.zshrc: source ~/.bugbounty/aliases.zsh"
}

# ─── Post-Install Verification ───────────────────────────────────────────────
verify_installation() {
  step "Post-Install Verification"

  # Refresh PATH
  export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"

  local CRITICAL_TOOLS=(
    subfinder httpx nuclei katana dnsx naabu
    ffuf gobuster nmap curl jq git go python3
    bb-recon bb-scan bb-idor
  )

  local OPTIONAL_TOOLS=(
    dalfox gf waybackurls gau anew unfurl qsreplace
    amass gowitness sqlmap nikto masscan whatweb arjun uro
  )

  local pass=0
  local fail=0
  local opt_pass=0

  echo ""
  echo -e "${BOLD}  Critical Tools:${NC}"
  for tool in "${CRITICAL_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
      local ver
      ver=$("$tool" -version 2>&1 | head -1 | grep -oP '[\d]+\.[\d]+[\.\d]*' | head -1 || echo "ok")
      printf "  ${GREEN}✓${NC}  %-22s %s\n" "$tool" "$ver"
      pass=$((pass + 1))
    else
      printf "  ${RED}✗${NC}  %-22s %s\n" "$tool" "NOT FOUND"
      fail=$((fail + 1))
    fi
  done

  echo ""
  echo -e "${BOLD}  Optional Tools:${NC}"
  for tool in "${OPTIONAL_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
      printf "  ${GREEN}✓${NC}  %-22s %s\n" "$tool" "ok"
      opt_pass=$((opt_pass + 1))
    else
      printf "  ${YELLOW}○${NC}  %-22s %s\n" "$tool" "not installed"
    fi
  done

  echo ""
  echo -e "${BOLD}  Failed Installs:${NC}"
  if [[ ${#FAILED_TOOLS[@]} -eq 0 ]]; then
    echo -e "  ${GREEN}None ✓${NC}"
  else
    for t in "${FAILED_TOOLS[@]}"; do
      echo -e "  ${RED}✗ $t${NC}"
    done
  fi

  echo ""
  echo -e "  Critical: ${GREEN}${pass}${NC} / $((pass + fail)) | Optional: ${GREEN}${opt_pass}${NC} / ${#OPTIONAL_TOOLS[@]}"
  echo ""

  return $fail
}

# ─── Generate README ──────────────────────────────────────────────────────────
generate_readme() {
  step "Generating README.md"

  cat > "$BB_HOME/README.md" <<'README_EOF'
# 🔒 Bug Bounty Toolkit

> **LEGAL NOTICE: This toolkit is for authorized security testing ONLY.**
> Only use against targets you have explicit, written permission to test.
> Unauthorized use is illegal and may result in criminal prosecution.

## One-Line Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USER/bb-toolkit/main/install.sh)
```

## What's Included

| Script | Purpose |
|--------|---------|
| `bb-recon` | Full recon pipeline (subdomain → live hosts → URLs → vulns → screenshots) |
| `bb-scan` | Multithreaded vulnerability scanner (nuclei + nmap + dalfox + ffuf) |
| `bb-idor` | Automated IDOR tester with baseline diffing and rate limiting |

## Quick Start

```bash
# Reload your shell first
source ~/.zshrc

# 1. Initialize a workspace
bb-init example.com

# 2. Run full recon
bb-recon example.com

# 3. Scan live hosts for vulnerabilities
bb-scan -l ~/bugbounty/example.com/hosts/live.txt

# 4. Test for IDOR
bb-idor -u "https://api.example.com/users/{ID}" \
        -H "Authorization: Bearer YOUR_TOKEN" \
        --start 1 --end 200
```

## Directory Structure

```
~/bugbounty/
├── example.com/
│   ├── 20250601_120000/      ← timestamped recon run
│   │   ├── subdomains/
│   │   │   ├── all.txt       ← all unique subdomains
│   │   │   └── resolved.txt  ← DNS-resolved
│   │   ├── hosts/
│   │   │   ├── live.txt      ← live HTTP/HTTPS hosts
│   │   │   └── live.json     ← httpx JSON (tech/title/status)
│   │   ├── urls/
│   │   │   ├── all.txt       ← all collected URLs
│   │   │   └── interesting.txt ← gf-filtered URLs
│   │   ├── vulns/
│   │   │   ├── nuclei.txt    ← findings
│   │   │   └── nuclei.json   ← machine-readable
│   │   ├── screenshots/      ← gowitness PNGs
│   │   └── reports/
│   │       └── summary.md    ← human-readable summary
│   └── notes/
│       └── scope.txt
~/.bugbounty/
│   ├── aliases.zsh           ← shell shortcuts
│   └── nuclei-templates/     ← custom/community templates
~/wordlists/
│   └── SecLists/             ← DanielMiessler SecLists
```

## Custom Aliases

After sourcing `~/.bugbounty/aliases.zsh`, you get:

```bash
# Navigation
bb                   # cd ~/bugbounty
bb-init example.com  # create workspace

# One-liners
subs example.com             # quick subdomain enum
livecheck subdomains.txt     # probe live hosts
scan https://example.com     # quick nuclei scan
wayback example.com          # collect + filter wayback URLs
quickrecon example.com       # mini full-stack recon

# Tool shortcuts
sf-passive, hx-probe, nuc-crit, gb-dir, kat-fast ...

# Updates
bb-update            # update all tools
bb-versions          # show installed versions
```

## bb-recon Usage

```bash
bb-recon example.com
bb-recon -t 100 -r 200 example.com     # faster
bb-recon --passive example.com         # passive only (safer)
bb-recon -s critical,high example.com  # only high severity nuclei
bb-recon --no-screenshots example.com  # skip gowitness

# Environment variables
BB_RECON_THREADS=100 bb-recon example.com
BB_NUCLEI_SEVERITY=critical bb-recon example.com
GITHUB_TOKEN=ghp_xxx bb-recon example.com   # github subdomain search
```

## bb-scan Usage

```bash
bb-scan -u https://example.com
bb-scan -l hosts.txt -s critical,high
bb-scan -l hosts.txt -m passive          # passive templates only
bb-scan -l hosts.txt -m fuzz            # + directory fuzzing
bb-scan -l hosts.txt --tags cve         # only CVE templates
bb-scan -l hosts.txt --scope scope.txt  # enforce scope
```

## bb-idor Usage

```bash
# Numeric sequential IDOR
bb-idor -u "https://api.example.com/user/{ID}/orders" \
        -H "Authorization: Bearer TOKEN" \
        --start 1 --end 500

# With custom ID list + cookie auth
bb-idor -u "https://example.com/invoice" \
        -p invoice_id \
        --ids known_ids.txt \
        -c "session=abc123"

# POST-based IDOR
bb-idor -u "https://api.example.com/view" \
        --method POST \
        --data '{"resource_id": "{ID}"}' \
        -H "Authorization: Bearer TOKEN" \
        --start 100 --end 300

# Batch test from recon output
bb-idor -l ~/bugbounty/example.com/urls/interesting.txt \
        -H "Authorization: Bearer TOKEN" \
        --start 1 --end 200

# UUID testing
bb-idor -u "https://api.example.com/documents/{ID}" \
        -H "Authorization: Bearer TOKEN" \
        --uuids --ids known_doc_ids.txt
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BB_HOME` | `~/bugbounty` | Base workspace |
| `BB_RECON_THREADS` | `50` | bb-recon thread count |
| `BB_RECON_RATE` | `150` | bb-recon HTTP rate/s |
| `BB_NUCLEI_RATE` | `50` | Nuclei rate/s |
| `BB_NUCLEI_SEVERITY` | `critical,high,medium` | Severity filter |
| `BB_SCREENSHOTS` | `true` | Enable screenshots |
| `BB_SCAN_THREADS` | `25` | bb-scan threads |
| `BB_SCAN_RATE` | `50` | bb-scan rate/s |
| `BB_IDOR_THREADS` | `10` | bb-idor threads |
| `BB_IDOR_RATE` | `20` | bb-idor rate/s |
| `GITHUB_TOKEN` | (unset) | GitHub API token for subdomain search |
| `CHAOS_KEY` | (unset) | ProjectDiscovery chaos API key |

## Update & Maintenance

```bash
# Update everything
bb-update
./install.sh --update

# Update nuclei templates only
nuclei -update-templates
nuc-update

# Uninstall
./install.sh --uninstall
```

## Safety & Ethics

- ✅ **Always verify scope** before scanning anything
- ✅ **Rate limiting** is built into every script — don't remove it
- ✅ **Ask permission** — check the bug bounty program's rules
- ✅ **Report responsibly** — don't disclose publicly before fix
- ✅ **Never exfiltrate** real user data as part of a PoC
- ✅ **Avoid destructive tests** — don't test SQLi with `DROP TABLE`
- ❌ **Never use** these tools without explicit written authorization
- ❌ **Never scan** government/critical infrastructure
- ❌ **Never store or share** private user data found during testing

## Tools Installed

| Category | Tools |
|----------|-------|
| Recon | subfinder, amass, assetfinder, shuffledns, dnsx |
| HTTP | httpx, katana, waybackurls, gau, hakrawler |
| Vuln Scan | nuclei, nikto |
| XSS | dalfox |
| Fuzzing | ffuf, gobuster, dirb |
| Port Scan | nmap, masscan, naabu |
| OSINT | gf, unfurl, qsreplace, anew, arjun |
| Screenshots | gowitness |
| Secrets | trufflehog |
| OOB | interactsh-client |
| ASN/CIDR | asnmap, mapcidr, cdncheck |
| Notify | notify |

---

*Generated by bb-toolkit installer. Authorized testing only.*
README_EOF

  success "README.md → $BB_HOME/README.md"
}

# ─── Uninstall ────────────────────────────────────────────────────────────────
do_uninstall() {
  step "Uninstalling Bug Bounty Toolkit"

  echo -e "${RED}${BOLD}This will remove:${NC}"
  echo "  - Custom scripts (bb-recon, bb-scan, bb-idor) from ~/.local/bin/"
  echo "  - ~/.bugbounty/ config directory"
  echo "  - The source line from ~/.zshrc"
  echo ""
  echo -e "${YELLOW}This will NOT remove:${NC}"
  echo "  - System packages (nuclei, nmap, etc.)"
  echo "  - ~/bugbounty/ workspace (your data is safe)"
  echo "  - ~/go/bin/ tools"
  echo "  - ~/wordlists/"
  echo ""
  prompt "Confirm uninstall? (yes/no):"
  read -r CONFIRM
  [[ "${CONFIRM,,}" != "yes" ]] && { info "Aborted."; exit 0; }

  # Remove custom scripts
  for script in bb-recon bb-scan bb-idor; do
    [[ -f "$BB_BIN/$script" ]] && rm -f "$BB_BIN/$script" && success "Removed: $BB_BIN/$script"
  done

  # Remove config
  if [[ -d "$BB_CONFIG" ]]; then
    rm -rf "$BB_CONFIG"
    success "Removed: $BB_CONFIG"
  fi

  # Remove zshrc line
  if [[ -f "$HOME/.zshrc" ]]; then
    cp "$HOME/.zshrc" "$HOME/.zshrc.bb-uninstall-backup"
    sed -i '/Bug Bounty Toolkit/d' "$HOME/.zshrc"
    sed -i '/aliases.zsh/d' "$HOME/.zshrc"
    success "Cleaned ~/.zshrc"
  fi

  success "Uninstall complete. Your ~/bugbounty/ workspace was preserved."
  exit 0
}

# ─── Update Mode ──────────────────────────────────────────────────────────────
do_update() {
  step "Updating Bug Bounty Toolkit"

  # Refresh PATH
  export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"

  info "Updating Go tools..."
  INSTALL_MODE="update"
  install_go_tools

  info "Updating pdtm suite..."
  if command -v pdtm &>/dev/null; then
    pdtm -up 2>&1 | grep -E "updated|failed" || true
  fi

  info "Updating nuclei templates..."
  nuclei -update-templates 2>/dev/null || true

  info "Updating gf patterns..."
  if [[ -d "$HOME/.gf" ]]; then
    git -C "/tmp/gf-patterns-update" pull 2>/dev/null || true
  fi
  setup_gf_patterns

  info "Updating custom scripts..."
  install_custom_scripts

  success "Update complete!"
  verify_installation
  exit 0
}

# ─── Success Message ──────────────────────────────────────────────────────────
print_success() {
  echo ""
  echo -e "${GREEN}${BOLD}"
  cat <<'EOF'
  ╔══════════════════════════════════════════════════════════════╗
  ║          INSTALLATION COMPLETE — HAPPY HACKING! 🎉          ║
  ╚══════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
  echo -e "${BOLD}  Next Steps:${NC}"
  echo ""
  echo -e "  ${CYAN}1.${NC} Reload your shell:"
  echo -e "     ${BOLD}source ~/.zshrc${NC}"
  echo ""
  echo -e "  ${CYAN}2.${NC} Verify all tools:"
  echo -e "     ${BOLD}bb-versions${NC}"
  echo ""
  echo -e "  ${CYAN}3.${NC} Initialize a workspace:"
  echo -e "     ${BOLD}bb-init example.com${NC}"
  echo ""
  echo -e "  ${CYAN}4.${NC} Run your first recon:"
  echo -e "     ${BOLD}bb-recon example.com${NC}"
  echo ""
  echo -e "  ${CYAN}5.${NC} Read the docs:"
  echo -e "     ${BOLD}cat ~/bugbounty/README.md${NC}"
  echo ""
  echo -e "${YELLOW}  ⚠  REMINDER: Only test targets you are authorized to test!${NC}"
  echo -e "${YELLOW}     Always check program scope before running any tool.${NC}"
  echo ""
  echo -e "  Install log: ${LOG_FILE}"
  echo ""
}

# ─── Optional Demo ────────────────────────────────────────────────────────────
offer_demo() {
  echo ""
  prompt "Run a quick demo recon against scanme.nmap.org (authorized test target)? (yes/no) [no]:"
  read -r DEMO_REPLY

  if [[ "${DEMO_REPLY,,}" == "yes" ]]; then
    info "Running demo recon against scanme.nmap.org..."
    warn "This is a publicly authorized test target maintained by nmap.org"
    export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
    bb-recon --passive scanme.nmap.org || true
  else
    info "Skipping demo"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  touch "$LOG_FILE"
  banner

  case "$INSTALL_MODE" in
    uninstall) do_uninstall ;;
    update)    do_update ;;
  esac

  echo -e "${BOLD}  Mode:    Full Installation${NC}"
  echo -e "${BOLD}  User:    $USER${NC}"
  echo -e "${BOLD}  Home:    $HOME${NC}"
  echo -e "${BOLD}  Log:     $LOG_FILE${NC}"
  echo ""

  preflight_checks
  setup_aur_helper
  system_update
  setup_blackarch
  install_pacman_packages
  install_aur_packages
  setup_go_env
  install_go_tools
  install_pipx_tools
  install_pdtm
  setup_nuclei_templates
  setup_gf_patterns
  install_wordlists
  setup_directories
  install_custom_scripts
  setup_shell
  generate_readme

  echo ""
  verify_installation
  print_success
  offer_demo
}

main "$@"
