#!/usr/bin/env bash
# =============================================================================
# Bug Bounty Toolkit — Uninstaller
# =============================================================================
# Removes custom scripts, configs, and shell integration.
# Does NOT remove: pacman packages, Go tools, wordlists, or your bb workspace.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }

BB_BIN="$HOME/.local/bin"
BB_CONFIG="$HOME/.bugbounty"
BB_HOME="$HOME/bugbounty"

echo -e "${RED}${BOLD}Bug Bounty Toolkit — Uninstaller${NC}"
echo ""
echo -e "${BOLD}This will remove:${NC}"
echo "  ✗  $BB_BIN/bb-recon"
echo "  ✗  $BB_BIN/bb-scan"
echo "  ✗  $BB_BIN/bb-idor"
echo "  ✗  $BB_CONFIG/ (aliases, templates, configs)"
echo "  ✗  Bug bounty lines from ~/.zshrc"
echo ""
echo -e "${BOLD}This will NOT remove:${NC}"
echo "  ✓  $BB_HOME/ (your workspace data)"
echo "  ✓  ~/go/bin/ (Go tools)"
echo "  ✓  ~/wordlists/ (SecLists etc.)"
echo "  ✓  System packages (nuclei, nmap, etc.)"
echo "  ✓  Nuclei templates (~/.config/nuclei/)"
echo ""
echo -ne "${YELLOW}Are you sure? Type 'yes' to confirm: ${NC}"
read -r CONFIRM

[[ "${CONFIRM,,}" != "yes" ]] && { echo "Aborted."; exit 0; }
echo ""

# Remove custom scripts
for script in bb-recon bb-scan bb-idor; do
  if [[ -f "$BB_BIN/$script" ]]; then
    rm -f "$BB_BIN/$script"
    success "Removed: $BB_BIN/$script"
  else
    info "Not found (already removed?): $BB_BIN/$script"
  fi
done

# Remove config directory
if [[ -d "$BB_CONFIG" ]]; then
  # Backup aliases first
  if [[ -f "$BB_CONFIG/aliases.zsh" ]]; then
    cp "$BB_CONFIG/aliases.zsh" "/tmp/bb-aliases-backup-$(date +%Y%m%d).zsh"
    info "Aliases backed up to /tmp/bb-aliases-backup-$(date +%Y%m%d).zsh"
  fi
  rm -rf "$BB_CONFIG"
  success "Removed: $BB_CONFIG"
fi

# Clean up ~/.zshrc
if [[ -f "$HOME/.zshrc" ]]; then
  ZSHRC_BACKUP="$HOME/.zshrc.bb-uninstall-$(date +%Y%m%d_%H%M%S)"
  cp "$HOME/.zshrc" "$ZSHRC_BACKUP"
  success "~/.zshrc backed up to: $ZSHRC_BACKUP"

  # Remove bug bounty lines
  sed -i '/Bug Bounty Toolkit/d' "$HOME/.zshrc"
  sed -i '/\.bugbounty\/aliases\.zsh/d' "$HOME/.zshrc"
  sed -i '/bb-toolkit/d' "$HOME/.zshrc"

  # Remove trailing blank lines that we added
  sed -i '/^$/N;/^\n$/d' "$HOME/.zshrc" 2>/dev/null || true

  success "Cleaned ~/.zshrc"
fi

echo ""
echo -e "${GREEN}${BOLD}Uninstall complete!${NC}"
echo ""
echo -e "  Your workspace is preserved at: ${BOLD}$BB_HOME${NC}"
echo ""

# Optionally remove go tools
echo -ne "${YELLOW}Remove Go-installed tools from ~/go/bin/? (yes/no) [no]: ${NC}"
read -r GO_REPLY

if [[ "${GO_REPLY,,}" == "yes" ]]; then
  GO_TOOLS=(subfinder httpx nuclei katana dnsx naabu pdtm interactsh-client
             notify chaos hakrawler waybackurls qsreplace gf assetfinder anew
             unfurl dalfox shuffledns mapcidr asnmap tlsx cdncheck gotator
             github-subdomains)
  for tool in "${GO_TOOLS[@]}"; do
    if [[ -f "$HOME/go/bin/$tool" ]]; then
      rm -f "$HOME/go/bin/$tool"
      echo "  Removed: ~/go/bin/$tool"
    fi
  done
  success "Go tools removed"
fi

# Optionally remove pipx tools
echo -ne "${YELLOW}Remove pipx-installed tools (arjun, uro, trufflehog)? (yes/no) [no]: ${NC}"
read -r PIPX_REPLY

if [[ "${PIPX_REPLY,,}" == "yes" ]]; then
  for pkg in arjun uro trufflehog; do
    pipx uninstall "$pkg" 2>/dev/null && echo "  Removed: $pkg" || true
  done
  success "pipx tools removed"
fi

echo ""
echo "To remove system packages (nmap, ffuf, etc.), run:"
echo "  sudo pacman -Rs nuclei nmap masscan ffuf sqlmap nikto gobuster"
echo ""
