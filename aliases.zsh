# =============================================================================
# Bug Bounty Toolkit — Shell Aliases & Functions
# Source this from ~/.zshrc:  source ~/.bugbounty/aliases.zsh
# =============================================================================

# ─── PATH Setup ───────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
export BB_HOME="$HOME/bugbounty"

# Go environment
export GOPATH="$HOME/go"
export GOBIN="$HOME/go/bin"

# ─── Core Navigation ──────────────────────────────────────────────────────────
alias bb='cd $BB_HOME'
alias bbl='ls -la $BB_HOME'
alias bbcd='cd $BB_HOME'

# ─── Tool Shortcuts ───────────────────────────────────────────────────────────

# subfinder shortcuts
alias sf='subfinder'
alias sf-passive='subfinder -all -silent'
alias sf-fast='subfinder -silent -t 100'

# httpx shortcuts  
alias hx='httpx'
alias hx-probe='httpx -silent -status-code -title -tech-detect'
alias hx-fast='httpx -silent -threads 200 -rate-limit 300'
alias hx-urls='httpx -silent -status-code -content-length -title -location -follow-redirects'

# nuclei shortcuts
alias nuc='nuclei'
alias nuc-crit='nuclei -severity critical,high -silent'
alias nuc-update='nuclei -update-templates'
alias nuc-list='nuclei -tl'

# ffuf shortcuts
alias fuf='ffuf'
alias fuf-dir='ffuf -mc 200,301,302,403 -t 50'
alias fuf-vhost='ffuf -w ~/wordlists/SecLists/Discovery/DNS/subdomains-top1million-5000.txt -H "Host: FUZZ.TARGET"'

# nmap shortcuts
alias nm='nmap'
alias nm-quick='nmap -T4 --open -F'
alias nm-full='nmap -T4 --open -p- -sV'
alias nm-vuln='nmap -T4 --open -sV --script vuln'
alias nm-safe='nmap -T4 --open -sV --script "not (brute or dos or exploit or external or fuzzer)"'

# gobuster shortcuts
alias gb='gobuster'
alias gb-dir='gobuster dir -t 50 -q'
alias gb-dns='gobuster dns -t 30 -q'
alias gb-vhost='gobuster vhost -t 30 -q'

# dalfox shortcuts
alias dfx='dalfox'
alias dfx-pipe='dalfox pipe'

# amass shortcuts
alias am-passive='amass enum -passive -d'
alias am-active='amass enum -active -d'

# gau shortcuts
alias gau-subs='gau --subs'

# katana shortcuts
alias kat='katana -depth 3 -jc -jsl'
alias kat-fast='katana -depth 2 -c 50 -rl 100'

# sqlmap shortcuts (be VERY careful)
alias sqli-test='sqlmap --batch --level 2 --risk 2'

# nikto shortcuts
alias nik='nikto -C all'

# ─── Custom Pipeline Functions ────────────────────────────────────────────────

# Quick subdomain check
subs() {
  local domain="$1"
  if [[ -z "$domain" ]]; then
    echo "Usage: subs <domain>"
    return 1
  fi
  echo "[*] Running passive subdomain enum for: $domain"
  subfinder -d "$domain" -all -silent | sort -u | tee "/tmp/subs_${domain}.txt"
  echo "[✓] $(wc -l < "/tmp/subs_${domain}.txt") subdomains → /tmp/subs_${domain}.txt"
}

# Quick live host check from subdomain list
livecheck() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo "Usage: livecheck <file_or_domain>"
    return 1
  fi
  if [[ -f "$input" ]]; then
    cat "$input" | httpx -silent -status-code -title -tech-detect -rate-limit 100
  else
    echo "$input" | httpx -silent -status-code -title -tech-detect
  fi
}

# Quick nuclei scan
scan() {
  local target="$1"
  local severity="${2:-critical,high}"
  if [[ -z "$target" ]]; then
    echo "Usage: scan <url_or_file> [severity]"
    return 1
  fi
  if [[ -f "$target" ]]; then
    nuclei -l "$target" -severity "$severity" -rl 50 -c 25
  else
    nuclei -u "$target" -severity "$severity" -rl 50 -c 25
  fi
}

# Wayback URL collection + interesting filter
wayback() {
  local domain="$1"
  if [[ -z "$domain" ]]; then
    echo "Usage: wayback <domain>"
    return 1
  fi
  local out="/tmp/wayback_${domain}.txt"
  echo "[*] Fetching Wayback URLs for: $domain"
  echo "$domain" | waybackurls | sort -u | tee "$out"
  echo "[✓] $(wc -l < "$out") URLs → $out"

  if command -v gf &>/dev/null; then
    echo ""
    echo "[*] Filtering interesting patterns..."
    for pat in xss sqli ssrf redirect lfi idor; do
      local count
      count=$(gf "$pat" < "$out" 2>/dev/null | wc -l)
      [[ $count -gt 0 ]] && echo "  $pat: $count URLs"
    done
  fi
}

# GAU + dedup pipeline
geturls() {
  local domain="$1"
  if [[ -z "$domain" ]]; then
    echo "Usage: geturls <domain>"
    return 1
  fi
  local out="/tmp/geturls_${domain}.txt"
  echo "[*] Collecting URLs for: $domain"
  {
    echo "$domain" | waybackurls 2>/dev/null
    echo "$domain" | gau --subs 2>/dev/null
  } | sort -u | tee "$out"
  echo "[✓] $(wc -l < "$out") unique URLs → $out"
}

# Full quick recon (lighter than bb-recon)
quickrecon() {
  local domain="$1"
  if [[ -z "$domain" ]]; then
    echo "Usage: quickrecon <domain>"
    return 1
  fi
  local out_dir="$BB_HOME/${domain}/quick_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$out_dir"

  echo "[*] Quick recon: $domain → $out_dir"

  echo "[1/4] Subdomains..."
  subfinder -d "$domain" -all -silent | sort -u | tee "$out_dir/subdomains.txt"

  echo "[2/4] Live hosts..."
  cat "$out_dir/subdomains.txt" | httpx -silent -status-code -title -rate-limit 100 | tee "$out_dir/live.txt"

  echo "[3/4] URLs..."
  echo "$domain" | waybackurls 2>/dev/null | sort -u > "$out_dir/urls.txt"

  echo "[4/4] Quick nuclei scan..."
  cut -d' ' -f1 "$out_dir/live.txt" | nuclei -severity critical,high -rl 30 -silent | tee "$out_dir/findings.txt"

  echo "[✓] Done → $out_dir"
}

# Show what technologies a URL is running
techcheck() {
  local target="$1"
  [[ -z "$target" ]] && { echo "Usage: techcheck <url>"; return 1; }
  httpx -u "$target" -silent -status-code -title -tech-detect -content-length -follow-redirects
  whatweb "$target" 2>/dev/null || true
}

# Extract all parameters from URLs for testing
getparams() {
  local input="$1"
  [[ -z "$input" ]] && { echo "Usage: getparams <url_file>"; return 1; }
  cat "$input" | grep "?" | unfurl --unique keys 2>/dev/null | sort -u
}

# Count findings by severity in a nuclei output file
findings-summary() {
  local file="$1"
  [[ -z "$file" ]] && { echo "Usage: findings-summary <nuclei_output.txt>"; return 1; }
  echo "=== Nuclei Findings Summary ==="
  for sev in critical high medium low info; do
    local count
    count=$(grep -ic "\[$sev\]" "$file" 2>/dev/null || echo 0)
    printf "  %-10s: %d\n" "${sev^^}" "$count"
  done
  echo ""
  echo "=== By Template ==="
  grep -oP '(?<=\[)[^\]]+(?=\] \[)' "$file" 2>/dev/null | sort | uniq -c | sort -rn | head -20
}

# Update all ProjectDiscovery tools
update-pd() {
  echo "[*] Updating ProjectDiscovery tools via pdtm..."
  pdtm -up 2>/dev/null || true
  echo "[*] Updating nuclei templates..."
  nuclei -update-templates
  echo "[✓] PD tools updated"
}

# Update all Go tools
update-go-tools() {
  echo "[*] Updating Go-installed tools..."
  local tools=(
    "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    "github.com/projectdiscovery/httpx/cmd/httpx@latest"
    "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    "github.com/projectdiscovery/katana/cmd/katana@latest"
    "github.com/tomnomnom/waybackurls@latest"
    "github.com/tomnomnom/gf@latest"
    "github.com/hahwul/dalfox/v2@latest"
  )
  for tool in "${tools[@]}"; do
    echo "  Updating: $tool"
    go install -v "$tool" 2>/dev/null && echo "  [✓] Done" || echo "  [!] Failed"
  done
}

# Run full toolkit update
bb-update() {
  echo "[*] Bug Bounty Toolkit Update"
  update-pd
  update-go-tools
  echo "[✓] All tools updated"
}

# Create a new bug bounty workspace
bb-init() {
  local domain="$1"
  [[ -z "$domain" ]] && { echo "Usage: bb-init <domain>"; return 1; }

  local dir="$BB_HOME/$domain"
  mkdir -p "$dir"/{subdomains,hosts,urls,vulns,screenshots,reports,notes,poc}

  cat > "$dir/notes/scope.txt" <<EOF
# Bug Bounty Scope — $domain
# Created: $(date)

## In Scope
$domain
*.$domain

## Out of Scope
# Add out-of-scope assets here

## Notes

EOF

  echo "[✓] Workspace created: $dir"
  echo "[*] Edit your scope: $dir/notes/scope.txt"
  echo "[*] Start recon:     bb-recon $domain"
}

# Quick report generator
bb-report() {
  local domain="$1"
  [[ -z "$domain" ]] && { echo "Usage: bb-report <domain>"; return 1; }

  local dir
  dir=$(find "$BB_HOME/$domain" -name "summary.md" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

  if [[ -n "$dir" ]]; then
    cat "$dir/summary.md"
  else
    echo "[!] No summary.md found for $domain. Run bb-recon first."
  fi
}

# Show all bb tool versions
bb-versions() {
  echo "=== Bug Bounty Toolkit Versions ==="
  local tools=(subfinder httpx nuclei katana dnsx naabu dalfox ffuf gobuster sqlmap nmap)
  for t in "${tools[@]}"; do
    if command -v "$t" &>/dev/null; then
      printf "  %-20s" "$t"
      "$t" -version 2>&1 | head -1 | grep -oP '\d+\.\d+[\.\d]*' | head -1 || echo "ok"
    else
      printf "  %-20s %s\n" "$t" "NOT INSTALLED"
    fi
  done
}

# ─── gf Pattern Shortcuts ─────────────────────────────────────────────────────
alias gf-xss='gf xss'
alias gf-sqli='gf sqli'
alias gf-ssrf='gf ssrf'
alias gf-lfi='gf lfi'
alias gf-rce='gf rce'
alias gf-idor='gf idor'
alias gf-redirect='gf redirect'
alias gf-all='for p in xss sqli ssrf lfi rce idor redirect; do echo "=== $p ==="; gf $p; done'

# ─── Wordlists ────────────────────────────────────────────────────────────────
export SECLISTS="$HOME/wordlists/SecLists"
export WL_DIRS="$SECLISTS/Discovery/Web-Content"
export WL_DNS="$SECLISTS/Discovery/DNS"
export WL_PASS="$SECLISTS/Passwords"
export WL_FUZZ="$SECLISTS/Fuzzing"

alias wl='ls $SECLISTS'
alias wl-dirs='ls $WL_DIRS'

# ─── Interactsh ───────────────────────────────────────────────────────────────
# Start an OOB listener for SSRF/blind XSS detection
alias oob-listen='interactsh-client -v'
alias oob-server='interactsh-client -server oast.pro -v'

# ─── Misc Utilities ───────────────────────────────────────────────────────────
# Strip http/https and paths from a URL list
alias strip-proto='sed -E "s|https?://||;s|/.*||"'

# Get only URLs with query parameters
alias only-params='grep "?"'

# Sort + unique for piping
alias srt='sort -u'

# Pretty print JSON
alias pp='jq .'

# Count lines fast
alias lc='wc -l'

# URL encode a string
urlencode() {
  python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

# URL decode a string
urldecode() {
  python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))" "$1"
}

# Base64 encode/decode
b64enc() { echo -n "$1" | base64; }
b64dec() { echo -n "$1" | base64 -d; }

# Check if a domain resolves
resolves() {
  dig +short "$1" | grep -q "." && echo "Resolves: YES" || echo "Resolves: NO"
}

# ─── Load Message ─────────────────────────────────────────────────────────────
# (uncomment to show on shell start)
# echo "🔒 Bug Bounty Toolkit loaded. Type 'bb-versions' to check tools."
