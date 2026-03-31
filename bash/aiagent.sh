#!/usr/bin/env bash
# =============================================================================
# aiagent.sh  v1.0.0
#
# Creates and manages a dedicated macOS user account for running AI agents
# (Claude Code, Gemini CLI) in full isolation from your main user account.
#
# USAGE:
#   sudo ./aiagent.sh <command> [options]
#
# COMMANDS:
#   install               Full setup — create user, install Node + Claude Code
#   status                Show current state of the aiagent user and tools
#   run                   Run Claude Code as the aiagent user
#   run --cmd <name>      Run a specific agent binary (e.g. gemini)
#   run --project <path>  Run agent in a specific project folder
#   add-key anthropic     Store or rotate the Anthropic API key
#   add-key google        Store or rotate the Google / Gemini API key
#   share <path>          Grant aiagent read+write access to a folder
#   unshare <path>        Remove aiagent access from a folder
#   teardown              Permanently delete the aiagent user and all files
#   help                  Show full help with examples and notes
#
# QUICK START:
#   chmod +x aiagent.sh
#   sudo ./aiagent.sh install
#   ./aiagent.sh run
#
# REQUIREMENTS:
#   - macOS 12 Monterey or later (tested on Apple Silicon M1/M2/M3/M4)
#   - sudo access on your main account
#   - Internet connection (for nvm + Node download during install)
#
# CHANGELOG:
# =============================================================================

set -euo pipefail

# ── Version ───────────────────────────────────────────────────────────────────
SCRIPT_VERSION="2.1.5"

# ── Color codes for output ────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ── Logging functions ─────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}ℹ️  $*${NC}" >&2; }
log_success() { echo -e "${GREEN}✅ $*${NC}" >&2; }
log_warning() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }
log_error()   { echo -e "${RED}❌ $*${NC}" >&2; }
die()         { log_error "$*"; exit 1; }
step()        { echo -e "\n${BOLD}${BLUE}▶ $*${NC}" >&2; }
dim()         { echo -e "${DIM}  $*${NC}" >&2; }
hr()          { echo -e "${DIM}────────────────────────────────────────────────────${NC}" >&2; }

# ── Configuration ─────────────────────────────────────────────────────────────
AGENT_USER="aiagent"
AGENT_REALNAME="AI Agent"
AGENT_UID=601
AGENT_GID=600
AGENT_HOME="/Users/${AGENT_USER}"
WORKSPACE="/opt/ai-workspace"
NODE_VERSION="20"
NVM_VERSION="0.39.7"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-latest}"
GEMINI_CLI_VERSION="${GEMINI_CLI_VERSION:-latest}"

# ── Guard functions ───────────────────────────────────────────────────────────

require_macos() {
  [[ "$(uname)" == "Darwin" ]] || die "This script is for macOS only."
}

require_sudo() {
  local cmd="${1:-}"
  if [[ "$EUID" -ne 0 ]]; then
    die "This command requires sudo. Run:\n  sudo ./aiagent.sh ${cmd}"
  fi
}

user_exists() {
  dscl . -read "/Users/${AGENT_USER}" UniqueID &>/dev/null
}

# ── help ──────────────────────────────────────────────────────────────────────
cmd_help() {
  echo -e ""
  echo -e "${BOLD}${CYAN}aiagent.sh${NC}  v${SCRIPT_VERSION}"
  echo -e "${DIM}Isolated macOS AI agent user manager${NC}"
  hr
  echo -e ""
  echo -e "${BOLD}USAGE${NC}"
  echo -e "  sudo ./aiagent.sh ${CYAN}<command>${NC} [options]"
  echo -e "       ./aiagent.sh run [options]   ${DIM}(no sudo needed)${NC}"
  echo -e ""
  hr
  echo -e ""
  echo -e "${BOLD}COMMANDS${NC}"
  echo -e ""
  echo -e "  ${CYAN}install${NC}"
  echo -e "    Full one-time setup. Creates the '${AGENT_USER}' macOS user, installs"
  echo -e "    nvm, Node.js ${NODE_VERSION}, and Claude Code. Optionally installs Gemini CLI."
  echo -e "    Prompts interactively for your Anthropic API key."
  echo -e "    ${DIM}Safe to re-run — every step is idempotent (skips if already done).${NC}"
  echo -e "    ${DIM}Requires sudo.${NC}"
  echo -e ""
  echo -e "  ${CYAN}status${NC}"
  echo -e "    Full health check. Shows user account details, installed tool"
  echo -e "    versions, API key presence, and isolation confirmation."
  echo -e "    ${DIM}Requires sudo.${NC}"
  echo -e ""
  echo -e "  ${CYAN}run${NC} [${YELLOW}--cmd${NC} <agent>] [${YELLOW}--project${NC} <path>]"
  echo -e "    Switch to the '${AGENT_USER}' user and run an AI agent."
  echo -e "    Defaults to 'claude' in ${WORKSPACE}."
  echo -e "    Use ${YELLOW}--project .${NC} to run in the current directory."
  echo -e "    ${DIM}Does NOT require sudo.${NC}"
  echo -e ""
  echo -e "    ${YELLOW}--cmd${NC} <agent>     Binary to run. Default: claude"
  echo -e "    ${YELLOW}--project${NC} <path>  Working directory. Default: ${WORKSPACE}"
  echo -e ""
  echo -e "  ${CYAN}add-key${NC} <service>"
  echo -e "    Store or rotate an API key in ${AGENT_HOME}/.zshrc."
  echo -e "    Key is written with 600 permissions — only '${AGENT_USER}' can read it."
  echo -e "    If the key already exists it is replaced in-place."
  echo -e "    ${DIM}Requires sudo.${NC}"
  echo -e ""
  echo -e "    ${YELLOW}anthropic${NC}   sets ANTHROPIC_API_KEY  (Claude Code)"
  echo -e "    ${YELLOW}google${NC}      sets GOOGLE_API_KEY      (Gemini CLI)"
  echo -e ""
  echo -e "  ${CYAN}share${NC} <path>"
  echo -e "    Grant '${AGENT_USER}' read+write access to a folder via macOS ACL."
  echo -e "    Automatically grants traverse permission on parent directories."
  echo -e "    Use this to give the agent access to a project in your home dir."
  echo -e "    Use ${YELLOW}.${NC} to share the current directory."
  echo -e "    ${DIM}Requires sudo.${NC}"
  echo -e ""
  echo -e "  ${CYAN}unshare${NC} <path>"
  echo -e "    Remove the ACL entry added by 'share', including traverse ACLs."
  echo -e "    Standard Unix permissions are not affected."
  echo -e "    Use ${YELLOW}.${NC} to unshare the current directory."
  echo -e "    ${DIM}Requires sudo.${NC}"
  echo -e ""
  echo -e "  ${CYAN}teardown${NC}"
  echo -e "    ${RED}Permanently${NC} deletes the '${AGENT_USER}' user, home directory,"
  echo -e "    ${WORKSPACE}, all tools, and all stored API keys."
  echo -e "    Requires typing '${AGENT_USER}' to confirm. Cannot be undone."
  echo -e "    ${DIM}Requires sudo.${NC}"
  echo -e ""
  echo -e "  ${CYAN}help${NC}  |  ${CYAN}--help${NC}  |  ${CYAN}-h${NC}"
  echo -e "    Show this screen."
  echo -e ""
  hr
  echo -e ""
  echo -e "${BOLD}EXAMPLES${NC}"
  echo -e ""
  echo -e "  ${BOLD}# First-time setup:${NC}"
  echo -e "  ${CYAN}sudo ./aiagent.sh install${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Verify everything installed correctly:${NC}"
  echo -e "  ${CYAN}sudo ./aiagent.sh status${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Run Claude Code in the shared workspace :${NC}"
  echo -e "  ${CYAN}./aiagent.sh run${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Run Claude Code on a specific project:${NC}"
  echo -e "  ${CYAN}./aiagent.sh run --project ~/projects/my-app${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Run Gemini CLI instead of Claude:${NC}"
  echo -e "  ${CYAN}./aiagent.sh run --cmd gemini${NC}"
  echo -e ""
  echo -e ""
  echo -e "  ${BOLD}# Run Gemini CLI on a specific project:${NC}"
  echo -e "  ${CYAN}./aiagent.sh run --cmd gemini --project ~/projects/my-app${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Rotate the Anthropic API key:${NC}"
  echo -e "  ${CYAN}sudo ./aiagent.sh add-key anthropic${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Let the agent access a project in your home folder:${NC}"
  echo -e "  ${CYAN}sudo ./aiagent.sh share ~/projects/my-app${NC}"
  echo -e "  ${CYAN}./aiagent.sh run --project ~/projects/my-app${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Share and run in the current directory:${NC}"
  echo -e "  ${CYAN}sudo ./aiagent.sh share .${NC}"
  echo -e "  ${CYAN}./aiagent.sh run --project .${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Revoke that access when the session is done:${NC}"
  echo -e "  ${CYAN}sudo ./aiagent.sh unshare ~/projects/my-app${NC}"
  echo -e "  ${BOLD}# or from the shared directory:${NC}"
  echo -e "  ${CYAN}sudo ./aiagent.sh unshare .${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Remove everything permanently:${NC}"
  echo -e "  ${CYAN}sudo ./aiagent.sh teardown${NC}"
  echo -e ""
  echo -e "  ${BOLD}# Connect as the agent user:${NC}"
  echo -e "  ${CYAN}sudo -u aiagent -i${NC}"
  echo -e ""
  hr
  echo -e ""
  echo -e "${BOLD}NOTES${NC}"
  echo -e ""
  echo -e "  • '${AGENT_USER}' is a Standard (non-admin) account — cannot run sudo."
  echo -e "  • Hidden from the macOS login screen automatically."
  echo -e "  • Node.js, Claude Code, and Gemini CLI live entirely inside"
  echo -e "    ${AGENT_HOME} — your system Node is not touched."
  echo -e "  • Your main account's files are invisible to the agent unless"
  echo -e "    you explicitly use 'share'."
  echo -e "  • Network is NOT blocked — Claude Code and Gemini CLI require"
  echo -e "    internet to reach their APIs."
  echo -e "  • Tested on Apple Silicon (M1/M2/M3/M4) and Intel Macs."
  echo -e ""
  hr
  echo -e ""
  echo -e "${BOLD}FILES${NC}"
  echo -e ""
  echo -e "  ${AGENT_HOME}/.zshrc          Shell config + API keys (mode 600)"
  echo -e "  ${AGENT_HOME}/.npmrc           npm prefix config"
  echo -e "  ${AGENT_HOME}/.nvm/            Node version manager"
  echo -e "  ${AGENT_HOME}/.npm-global/bin/ claude, gemini binaries"
  echo -e "  ${WORKSPACE}/        Shared project workspace"
  echo -e ""
}

# ── install ───────────────────────────────────────────────────────────────────
cmd_install() {
  require_sudo install

  step "Preflight checks"
  local _macos_ver _macos_major
  _macos_ver=$(sw_vers -productVersion)
  _macos_major=$(echo "${_macos_ver}" | cut -d. -f1)
  log_info "macOS ${_macos_ver}  |  $(uname -m)  |  script v${SCRIPT_VERSION}"
  if [[ "${_macos_major}" -lt 12 ]]; then
    die "macOS 12 or later required. You are running macOS ${_macos_ver}."
  fi
  log_success "Preflight checks passed"

  # Detect Apple Silicon vs Intel for nvm arch hint
  local _arch
  _arch="$(uname -m)"
  log_info "Detected architecture: ${_arch}"

  # ── Interactive prompts ─────────────────────────────────────────────────────
  step "Configuration"

  # FIX #10: declare local before read so the variable does not leak globally
  local _api_key=""
  echo -e "${YELLOW}Anthropic API key${NC} (starts with sk-ant-...)"
  echo -e "${DIM}Stored in ${AGENT_HOME}/.zshrc — never visible to your main account.${NC}"
  echo -n "API key (press Enter to skip): "
  read -r _api_key
  echo ""
  if [[ -z "$_api_key" ]]; then
    log_warning "No API key provided. Add it later: sudo ./aiagent.sh add-key anthropic"
  else
    log_info "API key will be stored after setup."
  fi

  local _install_gemini="false"
  echo -n "Install Gemini CLI as well? [y/N]: "
  local _gemini_input=""
  read -r _gemini_input
  echo ""
  if [[ "$_gemini_input" =~ ^[Yy]$ ]]; then
    _install_gemini="true"
    log_info "Gemini CLI will be installed."
  fi

  # ── Step 1: OS group ────────────────────────────────────────────────────────
  step "Step 1/7 — Creating OS group '${AGENT_USER}'"

  if dscl . -read /Groups/${AGENT_USER} &>/dev/null; then
    log_warning "Group '${AGENT_USER}' already exists — skipping"
  else
    dscl . -create /Groups/${AGENT_USER}
    dscl . -create /Groups/${AGENT_USER} PrimaryGroupID ${AGENT_GID}
    log_success "Group '${AGENT_USER}' created (GID ${AGENT_GID})"
  fi

  # ── Step 2: OS user ─────────────────────────────────────────────────────────
  step "Step 2/7 — Creating OS user '${AGENT_USER}'"

  if user_exists; then
    log_warning "User '${AGENT_USER}' already exists — skipping"
  else
    dscl . -create /Users/${AGENT_USER}
    dscl . -create /Users/${AGENT_USER} UserShell        /bin/zsh
    dscl . -create /Users/${AGENT_USER} RealName         "${AGENT_REALNAME}"
    dscl . -create /Users/${AGENT_USER} UniqueID         ${AGENT_UID}
    dscl . -create /Users/${AGENT_USER} PrimaryGroupID   ${AGENT_GID}
    dscl . -create /Users/${AGENT_USER} NFSHomeDirectory ${AGENT_HOME}

    local _rpass
    _rpass=$(openssl rand -base64 20)
    dscl . -passwd /Users/${AGENT_USER} "${_rpass}"

    # createhomedir prints hostname noise to stdout on some macOS versions.
    # Redirect stdout to /dev/null; only show stderr on failure.
    if ! createhomedir -c -u ${AGENT_USER} >/dev/null 2>&1; then
      log_warning "createhomedir failed — creating home directory manually"
      mkdir -p "${AGENT_HOME}"
      chown ${AGENT_USER}:${AGENT_USER} "${AGENT_HOME}"
      chmod 700 "${AGENT_HOME}"
    fi

    log_success "User '${AGENT_USER}' created (UID ${AGENT_UID})"
    dim "Switch to this user anytime: sudo -u ${AGENT_USER} -i"
  fi

  # ── Step 3: Hide from login screen ──────────────────────────────────────────
  step "Step 3/7 — Hiding '${AGENT_USER}' from login screen"

  local _plist="/Library/Preferences/com.apple.loginwindow.plist"
  local _pbuddy="/usr/libexec/PlistBuddy"

  # Check if already in the list using PlistBuddy to avoid plist parse errors
  local _already_hidden=false
  if "${_pbuddy}" -c "Print :HiddenUsersList" "${_plist}" &>/dev/null; then
    local _i=0 _entry=""
    while true; do
      _entry=$("${_pbuddy}" -c "Print :HiddenUsersList:${_i}" "${_plist}" 2>/dev/null) || break
      if [[ "$_entry" == "${AGENT_USER}" ]]; then
        _already_hidden=true
        break
      fi
      (( _i++ )) || true
    done
  fi

  if [[ "$_already_hidden" == "true" ]]; then
    log_warning "'${AGENT_USER}' is already hidden — skipping"
  else
    defaults write /Library/Preferences/com.apple.loginwindow \
      HiddenUsersList -array-add "${AGENT_USER}"
    log_success "'${AGENT_USER}' hidden from login screen"
  fi

  # ── Step 4: Shared workspace ─────────────────────────────────────────────────
  step "Step 4/7 — Creating shared workspace at ${WORKSPACE}"

  if [[ -d "${WORKSPACE}" ]]; then
    log_warning "${WORKSPACE} already exists — skipping"
  else
    mkdir -p "${WORKSPACE}"
    chown ${AGENT_USER}:staff "${WORKSPACE}"
    chmod 750 "${WORKSPACE}"
    log_success "Workspace created at ${WORKSPACE}"
  fi

  # ── Step 5: Bootstrap nvm + Node + agents ───────────────────────────────────
  # FIX #1 #2 #3: The old version wrote the bootstrap using an unquoted heredoc
  # and embedded a nested heredoc (ZSHRC_BLOCK) inside it. This caused bash to
  # expand variables from the outer scope into the inner block, writing root's
  # $HOME into the agent's .zshrc instead of the literal string "$HOME".
  #
  # FIX: Write the bootstrap using printf instead of a heredoc. Every line of
  # the bootstrap script is a separate printf call with explicit escaping.
  # This gives complete control over what is literal vs what is expanded.
  #
  # FIX #4: Run bootstrap with env -i to give it a clean environment, then
  # explicitly pass only the variables the bootstrap actually needs.
  #
  # FIX #7: The bootstrap itself does NOT use set -e, because the nvm installer
  # returns non-zero on warnings on Apple Silicon, which would abort the script.
  #
  # FIX #8: Use a trap to clean up the temp file even if the bootstrap fails.
  #
  # FIX #9: Set TERM and NVM_DIR explicitly in the bootstrap environment.

  step "Step 5/7 — Installing nvm, Node ${NODE_VERSION}, and Claude Code"
  dim "This may take a few minutes on the first run."

  # Clean up any stale bootstrap files left by previous failed runs
  rm -f /tmp/aiagent_bootstrap.*.sh 2>/dev/null || true

  # mktemp on macOS requires XXXXXX to be the final component — adding a .sh
  # suffix after the pattern causes "mktemp: mkstemp failed" on some systems.
  # Solution: create without extension, then move to add .sh suffix.
  local _bootstrap _bootstrap_sh
  _bootstrap=$(mktemp /tmp/aiagent_bootstrap.XXXXXX)
  _bootstrap_sh="${_bootstrap}.sh"
  mv "${_bootstrap}" "${_bootstrap_sh}"
  _bootstrap="${_bootstrap_sh}"

  # Always clean up the temp file, even on failure
  trap 'rm -f "${_bootstrap}" 2>/dev/null || true' EXIT

  chmod 700 "${_bootstrap}"
  chown "${AGENT_USER}" "${_bootstrap}"

  # Write the bootstrap script line by line using printf.
  # Variables we want EXPANDED NOW (at write time):   ${AGENT_HOME}, ${AGENT_USER},
  #                                                    ${NODE_VERSION}, ${NVM_VERSION},
  #                                                    ${_arch}, ${_install_gemini}, ${_api_key}
  # Variables we want LITERAL in the script (runtime): \$HOME, \$NVM_DIR, \$PATH, \$ZSHRC
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Bootstrap — runs as aiagent, NOT as root\n'
    printf '# set -e is intentionally omitted: nvm installer exits non-zero on warnings\n'
    printf 'set -uo pipefail\n\n'

    # FIX #4 + #5: set HOME, USER, ARCH explicitly
    printf 'export HOME="%s"\n'   "${AGENT_HOME}"
    printf 'export USER="%s"\n'   "${AGENT_USER}"
    printf 'export ARCH="%s"\n'   "${_arch}"        # FIX #5: arm64 on Apple Silicon
    printf 'export TERM="xterm-256color"\n'
    printf 'export NVM_DIR="$HOME/.nvm"\n\n'        # literal $HOME — resolved at runtime

    printf 'echo "[bootstrap] Installing nvm %s..."\n' "${NVM_VERSION}"
    printf 'curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v%s/install.sh" | bash\n\n' \
      "${NVM_VERSION}"

    printf '# Load nvm into this shell session\n'
    printf '[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"\n\n'

    # FIX #5: pass --default and rely on ARCH env var for correct binary
    printf 'echo "[bootstrap] Installing Node.js %s (arch: $ARCH)..."\n' "${NODE_VERSION}"
    printf 'nvm install %s\n'         "${NODE_VERSION}"
    printf 'nvm use %s\n'             "${NODE_VERSION}"
    printf 'nvm alias default %s\n\n' "${NODE_VERSION}"

    printf 'echo "[bootstrap] Configuring npm local prefix..."\n'
    printf 'mkdir -p "$HOME/.npm-global"\n'
    printf 'npm config set prefix "$HOME/.npm-global"\n'
    printf 'export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.npm-global/bin:$PATH"\n\n'

    printf 'echo "[bootstrap] Installing Claude Code (%s)..."\n' "${CLAUDE_CODE_VERSION}"
    if [[ "${CLAUDE_CODE_VERSION}" == "latest" ]]; then
      printf 'npm install -g @anthropic-ai/claude-code\n\n'
    else
      printf 'npm install -g @anthropic-ai/claude-code@%s\n\n' "${CLAUDE_CODE_VERSION}"
    fi

    if [[ "${_install_gemini}" == "true" ]]; then
      printf 'echo "[bootstrap] Installing Gemini CLI (%s)..."\n' "${GEMINI_CLI_VERSION}"
      if [[ "${GEMINI_CLI_VERSION}" == "latest" ]]; then
        printf 'npm install -g @google/gemini-cli\n\n'
      else
        printf 'npm install -g @google/gemini-cli@%s\n\n' "${GEMINI_CLI_VERSION}"
      fi
      printf 'mkdir -p "$HOME/.gemini"\n'
    fi

    # Write .zshrc — all variable references here are LITERAL (runtime)
    # because we use printf %s and write them as single-quoted shell text
    printf 'echo "[bootstrap] Writing ~/.zshrc environment block..."\n'
    printf 'ZSHRC="$HOME/.zshrc"\n'
    printf 'touch "$ZSHRC"\n\n'

    # Only append the block if NVM_DIR is not already there
    printf 'if ! grep -q "NVM_DIR" "$ZSHRC" 2>/dev/null; then\n'
    # FIX #1 #3: write each line of the .zshrc block individually with printf
    # so there is no nested heredoc and no accidental expansion
    printf '  printf "\\n# ── AI Agent environment ──\\n"         >> "$ZSHRC"\n'
    printf '  printf "export NVM_DIR=\\"\\$HOME/.nvm\\"\\n"      >> "$ZSHRC"\n'
    printf '  printf "[ -s \\"\\$NVM_DIR/nvm.sh\\" ]"            >> "$ZSHRC"\n'
    printf '  printf " && source \\"\\$NVM_DIR/nvm.sh\\"\\n"     >> "$ZSHRC"\n'
    printf '  printf "[ -s \\"\\$NVM_DIR/bash_completion\\" ]"   >> "$ZSHRC"\n'
    printf '  printf " && source \\"\\$NVM_DIR/bash_completion\\"\\n" >> "$ZSHRC"\n'
    printf '  printf "export PATH=\\"\\$HOME/.npm-global/bin:\\$PATH\\"\\n" >> "$ZSHRC"\n'
    printf 'fi\n\n'

    # Store the API key if one was provided (expanded at write time — correct)
    if [[ -n "${_api_key}" ]]; then
      printf 'if ! grep -q "ANTHROPIC_API_KEY" "$ZSHRC" 2>/dev/null; then\n'
      # The key value itself is expanded now (correct — we want the literal key)
      printf '  printf "\\n# Anthropic API key\\nexport ANTHROPIC_API_KEY='"'"'%s'"'"'\\n" >> "$ZSHRC"\n' \
        "${_api_key}"
      printf '  echo "[bootstrap] API key written to $ZSHRC"\n'
      printf 'else\n'
      printf '  echo "[bootstrap] ANTHROPIC_API_KEY already present — skipping"\n'
      printf 'fi\n\n'
    fi

    printf 'chmod 600 "$ZSHRC"\n'
    printf 'echo "[bootstrap] Done."\n'

  } > "${_bootstrap}"

  # Run the bootstrap as the agent user with a clean, explicit environment.
  # We avoid 'sudo -i' here because -i loads the full login shell and may
  # interfere with our explicit HOME/PATH settings.
  # HOME must be set correctly so nvm installs into the agent's home, not root's.
  #
  # CRITICAL: cd to AGENT_HOME first so the child process inherits a cwd that
  # the aiagent user can access. Without this, every command in the bootstrap
  # fails with "getcwd: cannot access parent directories: Permission denied"
  # because the caller's cwd (e.g. /Users/xxx) is not readable by aiagent.
  cd "${AGENT_HOME}" || die "Cannot cd to ${AGENT_HOME} — was the home directory created?"

  if ! sudo -u "${AGENT_USER}" \
    HOME="${AGENT_HOME}" \
    USER="${AGENT_USER}" \
    ARCH="${_arch}" \
    TERM="xterm-256color" \
    NVM_DIR="${AGENT_HOME}/.nvm" \
    PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    bash "${_bootstrap}"; then
    rm -f "${_bootstrap}"
    trap - EXIT
    die "Bootstrap script failed. Check the output above for details."
  fi

  # Trap will clean up _bootstrap on exit — remove it early on success
  rm -f "${_bootstrap}"
  trap - EXIT

  log_success "nvm, Node ${NODE_VERSION}, and Claude Code installed for '${AGENT_USER}'"

  # ── Step 6: Verify ───────────────────────────────────────────────────────────
  step "Step 6/7 — Verifying installation"

  # cd to AGENT_HOME so the verification subprocess has a valid cwd
  cd "${AGENT_HOME}" 2>/dev/null || true

  local _verify=""
  _verify=$(sudo -u "${AGENT_USER}" \
    HOME="${AGENT_HOME}" \
    USER="${AGENT_USER}" \
    PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    zsh -c '
    ZSH_DISABLE_COMPFIX=true
    [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null || true
    [ -s "$HOME/.nvm/nvm.sh" ] && source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
    export PATH="$HOME/.npm-global/bin:$PATH"
    printf "node:   %s\n" "$(node   --version       2>/dev/null || echo NOT FOUND)"
    printf "npm:    %s\n" "$(npm    --version       2>/dev/null || echo NOT FOUND)"
    printf "claude: %s\n" "$(command -v claude      2>/dev/null || echo NOT FOUND)"
    printf "gemini: %s\n" "$(command -v gemini      2>/dev/null || echo NOT FOUND)"
  ' 2>/dev/null || echo "ERROR: Could not query agent user environment")

  echo "$_verify" | while IFS= read -r line; do
    if echo "$line" | grep -qE "NOT FOUND|ERROR"; then
      log_warning "$line"
    else
      log_success "$line"
    fi
  done

  # ── Step 7: Isolation check ──────────────────────────────────────────────────
  step "Step 7/7 — Confirming isolation from main user"

  local _main_claude=""
  _main_claude=$(which claude 2>/dev/null || echo "")

  if [[ -z "$_main_claude" ]]; then
    log_success "'claude' is NOT visible to your main account — isolation confirmed"
  else
    log_warning "'claude' is also on your main account PATH: ${_main_claude}"
    dim  "This is fine if you intentionally installed it for your own use."
  fi

  # ── Summary ──────────────────────────────────────────────────────────────────
  echo ""
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  Setup complete!${NC}"
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}"
  echo ""
  cmd_help
}

# ── status ────────────────────────────────────────────────────────────────────
cmd_status() {
  require_sudo status

  step "AI Agent Status Report"

  echo -e "\n${BOLD}User account${NC}"
  if user_exists; then
    local _uid _name
    _uid=$(dscl . -read /Users/${AGENT_USER} UniqueID 2>/dev/null | awk '{print $2}')
    _name=$(dscl . -read /Users/${AGENT_USER} RealName 2>/dev/null | tail -1 | xargs)
    log_success "User '${AGENT_USER}' exists  (UID ${_uid}, display: ${_name})"
  else
    log_warning "User '${AGENT_USER}' does NOT exist."
    dim  "Run: sudo ./aiagent.sh install"
    return
  fi

  [[ -d "${AGENT_HOME}" ]] \
    && log_success "Home directory: ${AGENT_HOME}" \
    || log_warning    "Home directory not found: ${AGENT_HOME}"

  [[ -d "${WORKSPACE}" ]] \
    && log_success "Shared workspace: ${WORKSPACE}" \
    || log_warning    "Shared workspace not found: ${WORKSPACE}"

  local _pbuddy="/usr/libexec/PlistBuddy"
  local _plist="/Library/Preferences/com.apple.loginwindow.plist"
  local _is_hidden=false
  if "${_pbuddy}" -c "Print :HiddenUsersList" "${_plist}" &>/dev/null; then
    local _si=0 _sentry=""
    while true; do
      _sentry=$("${_pbuddy}" -c "Print :HiddenUsersList:${_si}" "${_plist}" 2>/dev/null) || break
      [[ "$_sentry" == "${AGENT_USER}" ]] && _is_hidden=true && break
      (( _si++ )) || true
    done
  fi
  [[ "$_is_hidden" == "true" ]] \
    && log_success "Hidden from macOS login screen" \
    || log_warning    "NOT hidden from macOS login screen"

  echo -e "\n${BOLD}Installed tools (as '${AGENT_USER}')${NC}"
  local _runtime=""
  _runtime=$(cd "${AGENT_HOME}" 2>/dev/null && sudo -u "${AGENT_USER}" \
    HOME="${AGENT_HOME}" \
    USER="${AGENT_USER}" \
    PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    zsh -c '
    ZSH_DISABLE_COMPFIX=true
    [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null || true
    [ -s "$HOME/.nvm/nvm.sh" ] && source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
    export PATH="$HOME/.npm-global/bin:$PATH"
    printf "node:   %s\n" "$(node   --version        2>/dev/null || echo NOT FOUND)"
    printf "npm:    %s\n" "$(npm    --version        2>/dev/null || echo NOT FOUND)"
    printf "claude: %s\n" "$(command -v claude       2>/dev/null || echo NOT FOUND)"
    printf "gemini: %s\n" "$(command -v gemini       2>/dev/null || echo NOT FOUND)"
  ' 2>/dev/null || echo "ERROR: Could not query agent user")

  echo "$_runtime" | while IFS= read -r line; do
    if echo "$line" | grep -qE "NOT FOUND|ERROR"; then
      log_warning "$line"
    else
      log_success "$line"
    fi
  done

  echo -e "\n${BOLD}API keys  ${DIM}(presence only — values never shown)${NC}"
  if [[ -f "${AGENT_HOME}/.zshrc" ]]; then
    grep -q "ANTHROPIC_API_KEY" "${AGENT_HOME}/.zshrc" \
      && log_success "ANTHROPIC_API_KEY is set" \
      || log_warning    "ANTHROPIC_API_KEY not set. Run: sudo ./aiagent.sh add-key anthropic"
    grep -qE "GOOGLE_API_KEY|GEMINI_API_KEY" "${AGENT_HOME}/.zshrc" \
      && log_success "GOOGLE_API_KEY is set" \
      || log_info    "GOOGLE_API_KEY not set (only needed for Gemini CLI)"
  else
    log_warning "${AGENT_HOME}/.zshrc not found"
  fi

  echo -e "\n${BOLD}Isolation check${NC}"
  local _main_claude=""
  _main_claude=$(which claude 2>/dev/null || echo "")
  [[ -z "$_main_claude" ]] \
    && log_success "'claude' is NOT on your main account PATH — isolation confirmed" \
    || log_warning    "'claude' also on main account PATH: ${_main_claude}"

  echo ""
}

# ── run ───────────────────────────────────────────────────────────────────────
cmd_run() {
  local _cmd="claude"
  local _project="${WORKSPACE}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cmd)
        [[ -n "${2:-}" ]] || die "--cmd requires a value. Example: --cmd gemini"
        _cmd="$2"; shift 2 ;;
      --project)
        [[ -n "${2:-}" ]] || die "--project requires a path."
        _project="$(cd "$2" 2>/dev/null && pwd)" \
          || die "--project path does not exist or is not accessible: $2"
        shift 2 ;;
      --help|-h)
        echo "Usage: ./aiagent.sh run [--cmd <agent>] [--project <path>]"
        return 0 ;;
      *)
        die "Unknown option: $1\nRun: ./aiagent.sh help" ;;
    esac
  done

  user_exists            || die "User '${AGENT_USER}' does not exist. Run: sudo ./aiagent.sh install"
  [[ -d "${_project}" ]] || die "Directory does not exist: ${_project}"

  step "Launching '${_cmd}' as '${AGENT_USER}'"
  log_info  "Working directory: ${_project}"
  echo ""

  # Verify the aiagent user can actually traverse to the project directory.
  # share only ACLs the target dir — parent dirs need at least execute permission.
  if ! sudo -u "${AGENT_USER}" test -d "${_project}" 2>/dev/null; then
    die "'${AGENT_USER}' cannot access ${_project}.\n" \
        "  The agent needs execute permission on every parent directory.\n" \
        "  Try: sudo ./aiagent.sh share $(dirname "${_project}")"
  fi

  # Write the run script to a temp file to avoid quoting hell with zsh -c.
  local _run_script
  _run_script=$(mktemp /tmp/aiagent_run.XXXXXX)
  chmod 755 "${_run_script}"

  cat > "${_run_script}" <<RUNEOF
#!/usr/bin/env zsh
export ZSH_DISABLE_COMPFIX=true
[ -f "\$HOME/.zshrc" ] && source "\$HOME/.zshrc" 2>/dev/null || true
[ -s "\$HOME/.nvm/nvm.sh" ] && source "\$HOME/.nvm/nvm.sh" 2>/dev/null || true
export PATH="\$HOME/.npm-global/bin:\$PATH"

cd "${_project}" || { echo "[ERROR] Cannot cd to ${_project} — permission denied or missing" >&2; exit 1; }
command -v ${_cmd} >/dev/null 2>&1 || { echo "[ERROR] '${_cmd}' not found in PATH. Run: sudo ./aiagent.sh status" >&2; exit 1; }
exec ${_cmd}
RUNEOF

  # exec replaces this process — Ctrl+C passes directly to the agent
  # Clean up temp file after exec (the OS reclaims it when the process ends)
  trap 'rm -f "${_run_script}" 2>/dev/null || true' EXIT
  exec sudo -u "${AGENT_USER}" HOME="${AGENT_HOME}" zsh "${_run_script}"
}

# ── add-key ───────────────────────────────────────────────────────────────────
cmd_add_key() {
  require_sudo "add-key"

  local _service="${1:-}"
  [[ -n "$_service" ]] || die "Usage: sudo ./aiagent.sh add-key <anthropic|google>"

  local _env_var="" _prompt=""
  case "$_service" in
    anthropic)
      _env_var="ANTHROPIC_API_KEY"
      _prompt="Enter Anthropic API key (sk-ant-...): " ;;
    google|gemini)
      _env_var="GOOGLE_API_KEY"
      _prompt="Enter Google / Gemini API key: " ;;
    *)
      die "Unknown service '${_service}'. Valid: anthropic, google" ;;
  esac

  user_exists || die "User '${AGENT_USER}' does not exist. Run: sudo ./aiagent.sh install"

  step "Storing ${_env_var} for '${AGENT_USER}'"

  local _key=""
  echo -n "$_prompt"
  read -rs _key
  echo ""
  [[ -n "$_key" ]] || { log_warning "Empty key — nothing written."; return; }

  local _zshrc="${AGENT_HOME}/.zshrc"
  touch "${_zshrc}"

  if grep -q "^export ${_env_var}=" "${_zshrc}" 2>/dev/null; then
    # Replace in-place using awk to avoid sed injection from special chars
    # in the key value (|, &, \, single quotes, etc.)
    local _tmp _new_line
    _tmp=$(mktemp)
    _new_line="export ${_env_var}='${_key//\'/\'\"\'\'\"\'}'"
    awk -v var="^export ${_env_var}=" -v repl="${_new_line}" \
      '{ if ($0 ~ var) print repl; else print }' \
      "${_zshrc}" > "${_tmp}"
    if [[ ! -s "${_tmp}" ]]; then
      rm -f "${_tmp}"
      die "Failed to update ${_env_var} — temp file was empty. ${_zshrc} is unchanged."
    fi
    mv "${_tmp}" "${_zshrc}"
    log_info "Existing ${_env_var} replaced"
  else
    # Escape single quotes in the key value for safe shell export
    local _escaped_key="${_key//\'/\'\"\'\'\"\'}"  
    printf "\n# %s API key\nexport %s='%s'\n" \
      "${_service}" "${_env_var}" "${_escaped_key}" >> "${_zshrc}"
    log_info "New ${_env_var} appended to ${_zshrc}"
  fi

  chown "${AGENT_USER}:${AGENT_USER}" "${_zshrc}"
  chmod 600 "${_zshrc}"
  log_success "${_env_var} saved. Only '${AGENT_USER}' can read ${_zshrc}."
}

# ── share ─────────────────────────────────────────────────────────────────────
cmd_share() {
  require_sudo share

  local _target="${1:-}"
  [[ -n "$_target" ]] || die "Usage: sudo ./aiagent.sh share <path>"

  _target="$(cd "${_target}" 2>/dev/null && pwd)" \
    || die "Path does not exist: ${1}"

  step "Sharing '${_target}' with '${AGENT_USER}'"

  # Grant execute (traverse) permission on each parent directory so the agent
  # can reach the target. Only adds execute — not read or write — so the agent
  # cannot list or modify files in parent directories.
  local _dir="${_target}"
  local -a _parents=()
  while true; do
    _dir=$(dirname "${_dir}")
    [[ "${_dir}" == "/" || "${_dir}" == "." ]] && break
    _parents+=("${_dir}")
  done

  # Apply in reverse order (from root toward target) for cleaner output
  local _p
  for (( i=${#_parents[@]}-1; i>=0; i-- )); do
    _p="${_parents[$i]}"
    # Skip if the agent can already traverse this directory
    if sudo -u "${AGENT_USER}" test -x "${_p}" 2>/dev/null; then
      continue
    fi
    if chmod +a "${AGENT_USER} allow execute" "${_p}" 2>/dev/null; then
      log_info "Granted traverse (execute) on ${_p}"
    else
      log_warning "Could not grant traverse on ${_p} — agent may not reach ${_target}"
    fi
  done

  # Apply ACL to the directory itself
  if ! chmod +a "${AGENT_USER} allow read,write,execute,delete,add_file,add_subdirectory" \
    "${_target}" 2>&1; then
    die "Failed to apply ACL to ${_target}"
  fi

  # Apply ACL recursively to existing contents
  if ! chmod -R +a "${AGENT_USER} allow read,write,execute,delete,add_file,add_subdirectory" \
    "${_target}" 2>&1; then
    log_warning "ACL applied to ${_target} but failed on some contents. Check: ls -leR ${_target}"
  fi

  ls -le "${_target}" | grep -q "${AGENT_USER}" \
    && log_success "'${AGENT_USER}' now has read+write access to ${_target} (recursive)" \
    || log_warning    "ACL may not have applied. Check: ls -le ${_target}"
  dim "Note: new files created outside the agent will not inherit this ACL."
}

# ── unshare ───────────────────────────────────────────────────────────────────
cmd_unshare() {
  require_sudo unshare

  local _target="${1:-}"
  [[ -n "$_target" ]] || die "Usage: sudo ./aiagent.sh unshare <path>"

  _target="$(cd "${_target}" 2>/dev/null && pwd)" \
    || die "Path does not exist: ${1}"

  step "Removing '${AGENT_USER}' ACL access from '${_target}'"

  # Remove ACL recursively from the target directory and its contents
  local _acl_errors
  _acl_errors=$(chmod -R -a "${AGENT_USER} allow read,write,execute,delete,add_file,add_subdirectory" \
    "${_target}" 2>&1) || true

  if [[ -n "${_acl_errors}" ]]; then
    log_warning "Some ACL entries could not be removed:\n${_acl_errors}"
  else
    log_success "'${AGENT_USER}' access removed from ${_target} (recursive)"
  fi

  # Remove traverse (execute-only) ACLs from parent directories.
  # Only removes the exact execute-only ACE that share added.
  local _dir="${_target}"
  while true; do
    _dir=$(dirname "${_dir}")
    [[ "${_dir}" == "/" || "${_dir}" == "." ]] && break
    if chmod -a "${AGENT_USER} allow execute" "${_dir}" 2>/dev/null; then
      log_info "Removed traverse ACL from ${_dir}"
    fi
  done

  dim "Standard Unix permissions are unchanged."
}

# ── teardown ──────────────────────────────────────────────────────────────────
cmd_teardown() {
  require_sudo teardown

  step "Teardown — permanently removing '${AGENT_USER}'"

  echo -e "\n${RED}${BOLD}⚠  The following will be permanently deleted:${NC}"
  dim "• macOS user and group '${AGENT_USER}'"
  dim "• Home directory: ${AGENT_HOME}"
  dim "• Shared workspace: ${WORKSPACE}"
  dim "• All tools: Node.js, nvm, Claude Code, Gemini CLI"
  dim "• All stored API keys"
  echo ""
  echo -e "${YELLOW}This cannot be undone. Copy anything from ${WORKSPACE} first.${NC}"
  echo ""
  echo -n "Type '${AGENT_USER}' to confirm: "
  local _confirm=""
  read -r _confirm
  echo ""

  [[ "$_confirm" == "${AGENT_USER}" ]] || { log_info "Teardown cancelled."; return; }

  log_info "Terminating running processes for '${AGENT_USER}'..."
  pkill -u "${AGENT_USER}" 2>/dev/null || true

  log_info "Removing from Directory Services..."
  dscl . -delete "/Users/${AGENT_USER}"  2>/dev/null \
    && log_success "User removed from dscl" \
    || log_warning    "Could not remove user (may already be gone)"
  dscl . -delete "/Groups/${AGENT_USER}" 2>/dev/null || true

  log_info "Removing from login screen hidden list..."
  local _plist="/Library/Preferences/com.apple.loginwindow.plist"
  local _pbuddy="/usr/libexec/PlistBuddy"

  # Use PlistBuddy to safely read and modify the plist array.
  # 'defaults read' returns a plist-formatted string like "(\n  aiagent\n)"
  # which breaks when word-split by bash. PlistBuddy works on the raw plist.
  if "${_pbuddy}" -c "Print :HiddenUsersList" "${_plist}" &>/dev/null; then
    # Find the index of AGENT_USER in the array
    local _idx=0 _found_idx=-1 _entry=""
    while true; do
      _entry=$("${_pbuddy}" -c "Print :HiddenUsersList:${_idx}" "${_plist}" 2>/dev/null) || break
      if [[ "$_entry" == "${AGENT_USER}" ]]; then
        _found_idx="${_idx}"
      fi
      (( _idx++ )) || true
    done

    if [[ "${_found_idx}" -ge 0 ]]; then
      "${_pbuddy}" -c "Delete :HiddenUsersList:${_found_idx}" "${_plist}" 2>/dev/null || true
      # If the array is now empty, remove the key entirely
      local _remaining
      local _remaining=0
      _remaining=$("${_pbuddy}" -c "Print :HiddenUsersList" "${_plist}" 2>/dev/null | grep -c '^[[:space:]]' 2>/dev/null) || _remaining=0
      if [[ "${_remaining}" -eq 0 ]]; then
        "${_pbuddy}" -c "Delete :HiddenUsersList" "${_plist}" 2>/dev/null || true
      fi
      log_success "'${AGENT_USER}' removed from login screen hidden list"
    else
      log_info "'${AGENT_USER}' was not in the hidden list — skipping"
    fi
  else
    log_info "HiddenUsersList key not found — skipping"
  fi

  if [[ -d "${AGENT_HOME}" ]]; then
    log_info "Deleting ${AGENT_HOME}..."
    if ! rm -rf "${AGENT_HOME}" 2>/dev/null; then
      # macOS SIP may protect some dirs (Pictures, etc.) — force with ditto workaround
      log_warning "Some files in ${AGENT_HOME} could not be removed (SIP-protected)."
      log_info "Trying to remove remaining contents..."
      find "${AGENT_HOME}" -mindepth 1 -delete 2>/dev/null || true
      rmdir "${AGENT_HOME}" 2>/dev/null || true
    fi
    if [[ -d "${AGENT_HOME}" ]]; then
      log_warning "${AGENT_HOME} could not be fully removed. Remove manually:\n  sudo rm -rf ${AGENT_HOME}"
    else
      log_success "Deleted ${AGENT_HOME}"
    fi
  fi

  if [[ -d "${WORKSPACE}" ]]; then
    log_info "Deleting ${WORKSPACE}..."
    rm -rf "${WORKSPACE}"
    log_success "Deleted ${WORKSPACE}"
  fi

  echo ""
  log_success "Teardown complete. '${AGENT_USER}' has been fully removed."
}

# ── Entry point ───────────────────────────────────────────────────────────────
require_macos

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  install)        cmd_install  "$@" ;;
  status)         cmd_status   "$@" ;;
  run)            cmd_run      "$@" ;;
  add-key)        cmd_add_key  "$@" ;;
  share)          cmd_share    "$@" ;;
  unshare)        cmd_unshare  "$@" ;;
  teardown)       cmd_teardown "$@" ;;
  help|--help|-h) cmd_help        ;;
  *)
    echo -e "${RED}Unknown command: ${COMMAND}${NC}"
    echo ""
    cmd_help
    exit 1
    ;;
esac
