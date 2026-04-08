# 🔒 Bug Bounty Toolkit for Arch Linux

> **⚠ LEGAL NOTICE:** This toolkit is for **authorized security testing only**.
> Only use against targets you have **explicit, written permission** to test.
> Unauthorized scanning is illegal under the CFAA (US), CMA (UK), and equivalent laws worldwide.
> The author assumes **no liability** for misuse. Always test responsibly.

---

## One-Line Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mrwade-arch/bb-toolkit/main/install.sh)
```

Or clone and run locally:

```bash
git clone https://github.com/mrwade-arch/bb-toolkit.git
cd bb-toolkit
chmod +x install.sh
./install.sh
```

---

## What Gets Installed

### Custom Scripts

| Script | Purpose |
|--------|---------|
| `bb-recon` | Full recon pipeline: subdomains → live hosts → URLs → vulnerabilities → screenshots |
| `bb-scan` | Multithreaded vulnerability scanner: nuclei + nmap + dalfox + ffuf |
| `bb-idor` | Automated IDOR tester with baseline response diffing and built-in rate limiting |

### Tool Suite

| Category | Tools |
|----------|-------|
| **Subdomain Enum** | subfinder, amass, assetfinder, shuffledns, github-subdomains |
| **DNS** | dnsx, bind-tools (dig), whois |
| **HTTP Probing** | httpx |
| **Crawling** | katana, hakrawler |
| **URL Collection** | waybackurls, gau |
| **Vuln Scanning** | nuclei, nikto |
| **Port Scanning** | nmap, masscan, naabu |
| **Fuzzing** | ffuf, gobuster, dirb |
| **XSS** | dalfox |
| **SQL Injection** | sqlmap |
| **IDOR/Param** | arjun, qsreplace, gf |
| **Screenshots** | gowitness |
| **Secrets** | trufflehog |
| **OOB** | interactsh-client |
| **Network** | asnmap, mapcidr, cdncheck, tlsx |
| **Notification** | notify |
| **Utilities** | anew, unfurl, uro, jq, parallel |

---

## File Layout

```
bb-toolkit/
├── install.sh        ← Main installer (idempotent)
├── uninstall.sh      ← Clean uninstaller
├── tools.json        ← Tool list (edit to add/remove tools)
├── bb-recon          ← Recon pipeline script
├── bb-scan           ← Scanner script
├── bb-idor           ← IDOR tester script
├── aliases.zsh       ← Shell shortcuts & helper functions
└── README.md         ← This file
```

After install, your system looks like:

```
~/bugbounty/           ← Main workspace (BB_HOME)
│   └── README.md
~/.bugbounty/          ← Toolkit config
│   ├── aliases.zsh
│   └── nuclei-templates/   ← community + custom templates
~/.local/bin/          ← Custom scripts
│   ├── bb-recon
│   ├── bb-scan
│   └── bb-idor
~/go/bin/              ← Go-installed tools
~/wordlists/
│   └── SecLists/      ← (optional, ~1.8GB)
```

---

## Quick Start

```bash
# 1. Reload your shell after install
source ~/.zshrc

# 2. Check everything is working
bb-versions

# 3. Create a workspace
bb-init example.com

# 4. Full recon
bb-recon example.com

# 5. Scan findings
bb-scan -l ~/bugbounty/example.com/hosts/live.txt

# 6. Test IDOR
bb-idor -u "https://api.example.com/users/{ID}" \
        -H "Authorization: Bearer YOUR_TOKEN" \
        --start 1 --end 200
```

---

## bb-recon — Full Recon Pipeline

```
bb-recon [OPTIONS] <domain>

OPTIONS
  -t, --threads N      Number of threads         (default: 50)
  -r, --rate N         HTTP requests per second   (default: 150)
  -s, --severity S     Nuclei severity filter     (default: critical,high,medium)
  -o, --output DIR     Custom output directory
  -p, --passive        Passive recon only (no active scanning)
  --no-screenshots     Skip gowitness screenshot phase
  --resolvers FILE     Custom DNS resolvers file
  -h, --help           Show help

PIPELINE
  1. subfinder + assetfinder + github-subdomains → passive subdomain enum
  2. shuffledns → DNS brute force (if SecLists present)
  3. dnsx → DNS resolution
  4. httpx → live host probing (status, title, tech)
  5. waybackurls + gau → URL collection
  6. katana → active crawling
  7. gf → filter interesting URLs (xss, sqli, ssrf, lfi, idor)
  8. gowitness → screenshots
  9. nuclei → vulnerability scanning
  10. Summary report generation

EXAMPLES
  bb-recon example.com
  bb-recon -t 100 -r 200 -s critical example.com
  bb-recon --passive example.com
  GITHUB_TOKEN=ghp_xxx bb-recon example.com
```

**Output:**
```
~/bugbounty/example.com/TIMESTAMP/
├── subdomains/all.txt       — all unique subdomains
├── subdomains/resolved.txt  — DNS-confirmed
├── hosts/live.txt           — live HTTP/S hosts
├── hosts/live.json          — httpx JSON (tech/title/status)
├── urls/all.txt             — all URLs
├── urls/interesting.txt     — gf-filtered
├── vulns/nuclei.txt         — findings
├── vulns/nuclei.json        — machine-readable
├── screenshots/             — PNG files
└── reports/summary.md       — full summary
```

---

## bb-scan — Vulnerability Scanner

```
bb-scan [OPTIONS] (-u URL | -l FILE)

TARGET
  -u, --url URL      Single target
  -l, --list FILE    File of targets
  --scope FILE       Scope whitelist (out-of-scope skipped)

SCAN MODES
  -m full     nuclei + nmap + dalfox XSS   (default)
  -m passive  nuclei passive templates only (safest)
  -m fuzz     nuclei + dalfox + ffuf dirs

OPTIONS
  -s, --severity S   critical,high,medium,low,info
  -t, --threads N    Concurrent templates    (default: 25)
  -r, --rate N       Requests/sec            (default: 50)
  --tags TAGS        Template tags filter    (cve, xss, rce, sqli...)
  --exclude-tags T   Exclude matching tags
  --no-json          Text output only

EXAMPLES
  bb-scan -u https://example.com
  bb-scan -l hosts.txt -m passive -s critical,high
  bb-scan -l hosts.txt --tags cve,rce
  bb-scan -l hosts.txt --scope scope.txt -m fuzz
```

---

## bb-idor — IDOR Tester

```
bb-idor [OPTIONS] -u URL

TARGET
  -u, --url URL       URL with {ID} placeholder
  -l, --list FILE     File of URLs with {ID} placeholder
  -p, --param NAME    Query param to fuzz (alternative to {ID})

ID VALUES
  --start N           Sequential start    (default: 1)
  --end N             Sequential end      (default: 100)
  --ids FILE          Custom values file
  --uuids             Also test UUID patterns

AUTH
  -H, --header STR    Auth header: "Authorization: Bearer TOKEN"
  -c, --cookie STR    Cookie string

DETECTION
  --diff N            Size diff % to flag   (default: 50)
  --no-compare        Flag all matching status codes
  --match-codes C     Codes to capture      (default: 200)
  --filter-codes C    Codes to ignore       (default: 404)

EXAMPLES
  # Basic sequential IDOR
  bb-idor -u "https://api.example.com/user/{ID}" \
          -H "Authorization: Bearer TOKEN" --start 1 --end 500

  # Parameter fuzzing
  bb-idor -u "https://example.com/api" -p user_id \
          --ids my_ids.txt -c "session=abc"

  # POST-based IDOR
  bb-idor -u "https://api.example.com/view" \
          --method POST \
          --data '{"id": "{ID}"}' \
          -H "Authorization: Bearer TOKEN"

  # UUID IDOR
  bb-idor -u "https://api.example.com/docs/{ID}" \
          -H "Authorization: Bearer TOKEN" \
          --uuids --ids known_ids.txt
```

**How it works:**
1. Takes a baseline response using a nonexistent ID
2. Iterates through all IDs with rate limiting per thread
3. Compares response size to baseline (flags if diff > threshold)
4. Saves full response body for interesting hits
5. Scans bodies for sensitive field patterns (email, token, etc.)

---

## Shell Aliases Reference

After `source ~/.zshrc`:

```bash
# Navigation & init
bb                   # cd ~/bugbounty
bb-init example.com  # create workspace + scope.txt
bb-versions          # show all tool versions
bb-update            # update all tools

# Quick recon functions
subs example.com           # passive subdomain enum
livecheck file.txt         # probe live hosts
scan https://target.com    # quick nuclei scan
wayback example.com        # collect + filter wayback URLs
quickrecon example.com     # quick full-stack recon
techcheck https://url      # technology fingerprint
getparams urls.txt         # extract unique param names

# Tool shortcuts
sf-passive, sf-fast         # subfinder
hx-probe, hx-fast           # httpx
nuc-crit, nuc-update        # nuclei
gb-dir, gb-dns, gb-vhost    # gobuster
nm-quick, nm-full, nm-vuln  # nmap
kat, kat-fast               # katana
gf-xss, gf-sqli, gf-idor   # gf patterns

# Utility functions
findings-summary file.txt   # breakdown of nuclei findings
urlencode "string"          # URL encode
urldecode "string%20here"   # URL decode
b64enc "string"             # base64 encode
b64dec "YWJj"               # base64 decode
resolves example.com        # quick DNS check

# Wordlists
$SECLISTS                   # path to SecLists
$WL_DIRS                    # web content wordlists
$WL_DNS                     # DNS wordlists
```

---

## Environment Variables

Set these in `~/.zshrc` or export before running:

```bash
export BB_HOME="$HOME/bugbounty"          # workspace root
export BB_RECON_THREADS=100               # more threads
export BB_RECON_RATE=200                  # faster HTTP probing
export BB_NUCLEI_SEVERITY="critical,high" # fewer findings, more signal
export BB_SCREENSHOTS=false               # disable screenshots
export BB_IDOR_THREADS=5                  # conservative IDOR threads
export BB_IDOR_RATE=10                    # conservative IDOR rate

# API keys (add to ~/.zshrc)
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"    # github subdomain search
export CHAOS_KEY="your_key_here"          # chaos.projectdiscovery.io
```

---

## Update & Maintenance

```bash
# Full update (all tools + templates)
./install.sh --update
# or
bb-update

# Update only nuclei templates
nuclei -update-templates

# Update only Go tools
update-go-tools

# Update ProjectDiscovery suite
update-pd
```

---

## Customizing tools.json

Edit `tools.json` to add/remove/modify tools before running the installer:

```json
{
  "go_tools": [
    {
      "name": "my-custom-tool",
      "install": "go install github.com/user/tool@latest",
      "purpose": "Does something useful"
    }
  ],
  "pacman_packages": [
    {
      "name": "my-extra-tool",
      "package": "extra-tool",
      "purpose": "Extra functionality"
    }
  ]
}
```

---

## Adding Custom Nuclei Templates

```bash
# Add templates to your custom directory
mkdir -p ~/.bugbounty/nuclei-templates/custom
nano ~/.bugbounty/nuclei-templates/custom/my-template.yaml

# bb-scan automatically includes ~/.bugbounty/nuclei-templates/
# bb-recon also includes this directory
```

---

## Troubleshooting

**Tools not found after install:**
```bash
source ~/.zshrc   # reload PATH
# or
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
```

**Go tools failing to install:**
```bash
go version          # check Go is installed
go env GOPATH       # check GOPATH
echo $PATH          # check ~/go/bin is in PATH
```

**Nuclei template errors:**
```bash
nuclei -update-templates
rm -rf ~/.config/nuclei/  # reset templates
nuclei -update-templates
```

**Rate limiting / getting blocked:**
- Reduce `-r` (rate limit) to 20-30 req/s
- Use `-m passive` for passive-only scans
- Add longer delays with `BB_IDOR_DELAY=500`

---

## Safety & Responsible Disclosure

### Before Testing
- ✅ Read the full bug bounty program policy
- ✅ Identify all in-scope assets
- ✅ Check for rate limiting policies
- ✅ Note any excluded test types

### During Testing
- ✅ Stay within scope — check every target
- ✅ Use built-in rate limits — don't modify them up
- ✅ Don't use destructive payloads (`DROP TABLE`, `rm -rf`, etc.)
- ✅ Don't access more data than needed to prove the bug
- ✅ Stop if you find something critical — report first

### After Finding Issues
- ✅ Document everything with screenshots and request/response
- ✅ Report via the official disclosure channel
- ✅ Give the team time to fix before disclosing publicly
- ✅ Never share or use any real user data you found

### Never Do
- ❌ Test without written authorization
- ❌ Scan government or critical infrastructure
- ❌ Exfiltrate real user data as PoC
- ❌ Share vulnerabilities publicly before fix
- ❌ Test out-of-scope targets

---

## Legal Resources

- [HackerOne Disclosure Guidelines](https://www.hackerone.com/disclosure-guidelines)
- [Bugcrowd Vulnerability Rating Taxonomy](https://bugcrowd.com/vulnerability-rating-taxonomy)
- [Computer Fraud and Abuse Act (US)](https://www.law.cornell.edu/uscode/text/18/1030)
- [Computer Misuse Act (UK)](https://www.legislation.gov.uk/ukpga/1990/18/contents)

---

*Bug Bounty Toolkit v1.0.0 | Arch Linux | Authorized testing only*
