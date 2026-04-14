# Isolated macOS AI Agent User — Complete Guide

> **aiagent.sh** — Create and manage a dedicated macOS user account for
> running AI agents (Claude Code, Gemini CLI) in full isolation from your main
> account.

---

## Table of Contents

1. [Why an Isolated User?](#1-why-an-isolated-user)
2. [How It Works](#2-how-it-works)
3. [Requirements](#3-requirements)
4. [Quick Start](#4-quick-start)
5. [Installation Tutorial](#5-installation-tutorial)
6. [Command Reference](#6-command-reference)
   - [install](#install)
   - [status](#status)
   - [run](#run)
   - [add-key](#add-key)
   - [share](#share)
   - [unshare](#unshare)
   - [teardown](#teardown)
   - [help](#help)
7. [File Layout Reference](#7-file-layout-reference)
8. [Security Model](#8-security-model)
9. [Day-to-Day Workflows](#9-day-to-day-workflows)
10. [Troubleshooting](#10-troubleshooting)
11. [Shell Script Internals](#11-shell-script-internals)
12. [Uninstall](#12-uninstall)

---

## 1. Why an Isolated User?

By default, when you run an AI agent like Claude Code directly in your terminal, it runs
as **you** — with full access to everything your account can read, write, and
execute. This includes:

| What the agent can reach | Risk |
|--------------------------|------|
| `~/.ssh/` private keys | Can read and exfiltrate SSH keys |
| `~/.aws/credentials` | Full AWS access |
| `~/.zsh_history` | Shell history often contains inline passwords |
| All project files | Can read, modify, or delete anything |
| `.env` files anywhere | API keys, DB credentials |
| System config files | `/etc/hosts`, cron jobs, launch agents |

A **dedicated OS user account** is the simplest reliable isolation on macOS.
The agent user has its own home directory, its own shell history, its own
credentials store — and by default **cannot see your main account's files at
all**.

This is lighter than Docker (no VM overhead, no container runtime) and more
robust than directory permissions alone (the OS enforces the boundary, not
just file modes).

---

## 2. How It Works

```
Your main account (/Users/yourname)
├── .ssh/            ← INVISIBLE to agent
├── .aws/            ← INVISIBLE to agent
├── Documents/       ← INVISIBLE to agent
└── projects/
    └── my-app/      ← visible ONLY if you run `share`

AI agent account (/Users/aiagent)
├── .zshrc           ← agent's own shell config
├── .nvm/            ← isolated Node.js installation
├── .npm-global/     ← claude, gemini binaries
└── (empty by default — no access to your files)

Shared workspace (/opt/ai-workspace)
└── your-project/    ← neutral ground both users can reach
```

The script creates the `aiagent` user as a **Standard (non-admin)** account,
hides it from the login screen, installs Node.js and CLI tools exclusively
inside its home directory, and creates a shared workspace at `/opt/ai-workspace`
that the agent owns.

---

## 3. Requirements

| Requirement | Details |
|-------------|---------|
| macOS version | 12 Monterey or later |
| Privileges | `sudo` access on your main account |
| Internet | Required during `install` to download nvm and Node |
| Disk space | ~500 MB for Node + Claude Code |
| Shell | zsh (default on macOS since Catalina) |

No other dependencies. The script uses only macOS built-in tools (`dscl`,
`defaults`, `createhomedir`, `chmod`, `openssl`).

---

## 4. Quick Start

```bash
# 1. Download and make executable
chmod +x aiagent.sh

# 2. Run the full setup (creates user, installs Claude Code)
sudo ./aiagent.sh install

# 3. Run Claude Code in the isolated workspace
./aiagent.sh run
```

To pin specific tool versions:

```bash
sudo CLAUDE_CODE_VERSION=1.0.12 GEMINI_CLI_VERSION=0.3.0 ./aiagent.sh install
```

That's it. The agent is now running in a fully isolated account with no
access to your home directory.

---

## 5. Installation Tutorial

### Step 1 — Get the script

Save `aiagent.sh` to a convenient location, for example your home
directory or a `scripts/` folder.

```bash
# Make it executable
chmod +x aiagent.sh
```

### Step 2 — Run install

```bash
sudo ./aiagent.sh install
```

The installer is **interactive**. It will ask you two questions:

```
Enter your Anthropic API key (starts with sk-ant-...):
▸ Paste your key and press Enter, or press Enter to skip

Also install Gemini CLI? [y/N]:
▸ Press y to also install Gemini CLI, or Enter to skip
```

You can also pin specific tool versions via environment variables:

```bash
# Pin both versions
sudo CLAUDE_CODE_VERSION=1.0.12 GEMINI_CLI_VERSION=0.3.0 ./aiagent.sh install

# Pin only one (the other defaults to latest)
sudo CLAUDE_CODE_VERSION=1.0.12 ./aiagent.sh install

# Default behaviour — installs latest
sudo ./aiagent.sh install
```

Then it runs automatically through 7 steps:

```
▶ Preflight checks
  ✅ Running on macOS 14.5

▶ Creating group 'aiagent'
  ✅ Group 'aiagent' created (GID 600)

▶ Creating user 'aiagent'
  ✅ User 'aiagent' created (UID 601)

▶ Hiding 'aiagent' from login screen
  ✅ 'aiagent' hidden from login screen

▶ Creating shared workspace at /opt/ai-workspace
  ✅ Workspace created at /opt/ai-workspace

▶ Installing nvm, Node 20, and Claude Code as 'aiagent'
  [bootstrap] Installing nvm 0.39.7...
  [bootstrap] Installing Node.js 20...
  [bootstrap] Installing Claude Code (latest)...
  [bootstrap] Done.

▶ Verifying installation
  ✅ node:   v20.x.x
  ✅ npm:    10.x.x
  ✅ claude: /Users/aiagent/.npm-global/bin/claude

▶ Confirming isolation from main user
  ✅ 'claude' is not visible to your main user account — isolation confirmed
```

**Safe to re-run.** If you run `install` again, every step checks whether it
has already been completed and skips it. Nothing is overwritten.

### Step 3 — Verify the setup

```bash
sudo ./aiagent.sh status
```

This shows a full health check: user account, runtime versions, API key
presence, and isolation confirmation.

### Step 4 — Share a project (optional)

If your project lives in your main account's home directory, grant the agent
read+write access:

```bash
sudo ./aiagent.sh share ~/projects/my-app

# Or share the current directory
sudo ./aiagent.sh share .
```

Or copy/move the project to the shared workspace instead:

```bash
cp -r ~/projects/my-app /opt/ai-workspace/
```

### Step 5 — Run the agent

```bash
# In the shared workspace
./aiagent.sh run

# In a specific project
./aiagent.sh run --project ~/projects/my-app

# In the current directory
./aiagent.sh run --project .

# With Gemini instead of Claude
./aiagent.sh run --cmd gemini

# Gemini in the current directory
./aiagent.sh run --cmd gemini --project .
```

---

## 6. Command Reference

### `install`

**Full setup.** Creates the `aiagent` macOS user, installs nvm, Node.js,
Claude Code, and optionally Gemini CLI. Prompts interactively for your
Anthropic API key.

```bash
sudo ./aiagent.sh install
```

**Behaviour:**
- Creates OS group `aiagent` (GID 600) and user `aiagent` (UID 601)
- Sets a random password — the account is not meant for GUI login
- Hides the account from the macOS login screen
- Creates `/opt/ai-workspace` owned by `aiagent`
- Runs a bootstrap script as `aiagent` to install nvm + Node + tools
- Stores the Anthropic API key in `/Users/aiagent/.zshrc` (600 permissions)
- Verifies all tools are accessible and confirms isolation

**Idempotent:** Safe to run multiple times. Each step checks if it is already
done and skips if so.

**Requires sudo:** Yes

---

### `status`

**Health check.** Shows the current state of the agent user and all installed
tools.

```bash
sudo ./aiagent.sh status
```

**Output sections:**

| Section | What it checks |
|---------|---------------|
| User account | UID, home dir, workspace, login screen visibility |
| Runtime | Node, npm, claude, gemini versions as the agent user |
| API keys | Whether ANTHROPIC_API_KEY and GOOGLE_API_KEY are set (values not shown) |
| Isolation check | Whether `claude` is visible on your main user's PATH |

**Requires sudo:** Yes

---

### `run`

**Launch an agent.** Switches to the `aiagent` user and runs an AI agent CLI
in the specified directory.

```bash
./aiagent.sh run [--cmd <agent>] [--project <path>]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--cmd` | `claude` | Agent binary to run. Any installed CLI name. |
| `--project` | `/opt/ai-workspace` | Directory to run the agent in. |

**Examples:**

```bash
# Run Claude Code in the shared workspace
./aiagent.sh run

# Run in a specific project folder
./aiagent.sh run --project ~/projects/my-app

# Run in the current directory
./aiagent.sh run --project .

# Run Gemini CLI
./aiagent.sh run --cmd gemini

# Run Gemini in the current directory
./aiagent.sh run --cmd gemini --project .

# Run Gemini in a specific project
./aiagent.sh run --cmd gemini --project ~/projects/my-app
```

**Notes:**
- Does **not** require sudo
- Uses `exec` internally so `Ctrl+C` passes through to the agent cleanly
- The agent sees only files it has been granted access to — your main home
  directory is invisible

**Requires sudo:** No

---

### `add-key`

**Store or rotate an API key** in `/Users/aiagent/.zshrc`. The key is stored
with `600` permissions — only readable by the `aiagent` user.

```bash
sudo ./aiagent.sh add-key <service>
```

**Services:**

| Service | Environment variable set | Used by |
|---------|--------------------------|---------|
| `anthropic` | `ANTHROPIC_API_KEY` | Claude Code |
| `google` | `GOOGLE_API_KEY` | Gemini CLI |

**Examples:**

```bash
# Store or rotate the Anthropic key
sudo ./aiagent.sh add-key anthropic

# Store or rotate the Google key
sudo ./aiagent.sh add-key google
```

**Behaviour:**
- Prompts for the key with hidden input (characters not echoed)
- If the key already exists in `.zshrc`, it is **replaced** in-place
- If it does not exist, it is **appended** to `.zshrc`
- File ownership and permissions are corrected after writing

**Requires sudo:** Yes

---

### `share`

**Grant the agent read+write access** to a folder in your main account using
macOS ACLs (Access Control Lists).

```bash
sudo ./aiagent.sh share <path>
```

**Examples:**

```bash
# Share a project folder
sudo ./aiagent.sh share ~/projects/my-app

# Share the current directory
sudo ./aiagent.sh share .

# Share a whole projects directory
sudo ./aiagent.sh share ~/projects
```

**What it does:**

1. **Grants traverse (execute-only) permission** on each parent directory
   from the target up to `/`. This allows the agent to `cd` through the path
   but **cannot list or read** files in those parent directories.
2. **Grants full read+write+execute access** recursively on the target
   directory and its contents using `chmod +a` / `chmod -R +a`.

ACL entry added to the target:
```
aiagent allow read,write,execute,delete,add_file,add_subdirectory
```

ACL entry added to each parent (execute only):
```
aiagent allow execute
```

**Example output:**

```
▶ Sharing '/Users/you/projects/my-app' with 'aiagent'
ℹ️  Granted traverse (execute) on /Users/you
ℹ️  Granted traverse (execute) on /Users/you/projects
✅ 'aiagent' now has read+write access to /Users/you/projects/my-app (recursive)
  Note: new files created outside the agent will not inherit this ACL.
```

**Verify the ACL was applied:**

```bash
ls -le ~/projects/my-app
# Should show a line like:
# 0: user:aiagent allow list,add_file,search,delete,...
```

> **Security note:** The traverse ACL on parent directories only grants
> `execute` — the agent can pass through the directory but cannot list its
> contents or read any files. Use `unshare` to remove all ACLs including
> the traverse entries.

**Requires sudo:** Yes

---

### `unshare`

**Remove the agent's ACL access** from a folder.

```bash
sudo ./aiagent.sh unshare <path>
```

**Examples:**

```bash
sudo ./aiagent.sh unshare ~/projects/my-app

# Or from the shared directory
sudo ./aiagent.sh unshare .
```

Removes the full read+write ACL from the target directory (recursively) **and**
the traverse (execute-only) ACLs from each parent directory that `share` added.
Standard Unix permissions are not affected.

**Requires sudo:** Yes

---

### `teardown`

**Permanently remove everything.** Deletes the `aiagent` user, home
directory, shared workspace, all installed tools, and all stored API keys.

```bash
sudo ./aiagent.sh teardown
```

**You must type `aiagent` at the confirmation prompt to proceed.**

**What is deleted:**

| Path | Contents |
|------|----------|
| `/Users/aiagent/` | Home dir, nvm, Node, Claude Code, Gemini CLI, API keys |
| `/opt/ai-workspace/` | Shared project workspace and its contents |
| Directory Services | User and group entries removed from `dscl` |
| Login screen list | Entry removed from `HiddenUsersList` |

> ⚠️ **This is irreversible.** Any project files you stored in
> `/opt/ai-workspace` will be deleted. Copy them out first if needed.

**Requires sudo:** Yes

---

### `help`

**Show the built-in help screen** with all commands, options, examples, notes,
and file locations.

```bash
./aiagent.sh help
# or
./aiagent.sh --help
./aiagent.sh -h
```

Also shown automatically when an unknown command is given.

**Requires sudo:** No

---

## 7. File Layout Reference

```
/Users/aiagent/                     ← agent home directory
├── .zshrc                          ← shell config: PATH, nvm, API keys
├── .npmrc                          ← npm prefix config
├── .nvm/                           ← nvm installation
│   ├── nvm.sh                      ← nvm loader
│   └── versions/node/v20.x.x/     ← isolated Node.js binary
├── .npm-global/                    ← npm global prefix (not system-wide)
│   ├── bin/
│   │   ├── claude                  ← Claude Code binary
│   │   └── gemini                  ← Gemini CLI binary (if installed)
│   └── lib/node_modules/
│       ├── @anthropic-ai/claude-code/
│       └── @google/gemini-cli/
└── projects/                       ← optional: clone repos here directly

/opt/ai-workspace/                  ← shared workspace
└── your-project/                   ← owned by aiagent, writable by both
```

**Key config file — `/Users/aiagent/.zshrc`:**

```zsh
# ── AI Agent environment ──────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
export PATH="$HOME/.npm-global/bin:$PATH"

# Anthropic API key
export ANTHROPIC_API_KEY='sk-ant-...'
```

---

## 8. Security Model

### What is isolated

| Resource | Isolated? | How |
|----------|-----------|-----|
| Your home directory | ✅ Yes | macOS user boundary — `aiagent` has no permissions to `/Users/yourname` |
| SSH private keys | ✅ Yes | Lives in `~/.ssh` which the agent cannot read |
| AWS credentials | ✅ Yes | Lives in `~/.aws` which the agent cannot read |
| Shell history | ✅ Yes | Each user has their own history file |
| macOS Keychain | ✅ Yes | Per-user keychain, agent cannot access yours |
| npm global packages | ✅ Yes | Agent's npm prefix is inside its own home dir |
| API keys | ✅ Yes | Stored in agent's `.zshrc` with 600 permissions |

### What is NOT isolated

| Resource | Notes |
|----------|-------|
| Internet access | The agent can make outbound connections — required for Claude/Gemini APIs |
| Shared workspace | `/opt/ai-workspace` is intentionally shared |
| Folders you `share` | Explicitly granted — you control this |
| System-level files | Standard user cannot write to `/etc`, `/usr`, `/System` anyway |

### What the agent user cannot do

- Run `sudo` (Standard account, not in sudoers)
- Install system-wide software
- Modify other users' files
- Read your main account's home directory
- Access your macOS Keychain entries

### Comparing to Docker

| | Dedicated OS User | Docker Container |
|--|---|---|
| Filesystem isolation | Strong (OS-enforced) | Strong (mount-controlled) |
| Setup complexity | Low | Medium |
| Performance overhead | None | Some (Linux VM on macOS) |
| Network isolation | Harder (needs Little Snitch/Lulu) | Easy (`--network none`) |
| Separate keychain | ✅ Yes | N/A |
| Works without Docker | ✅ Yes | No |
| Kill instantly | `sudo pkill -u aiagent` | `docker stop` |

---

## 9. Day-to-Day Workflows

### Starting a new project

```bash
# Option A — use the shared workspace
mkdir /opt/ai-workspace/my-new-project
./aiagent.sh run --project /opt/ai-workspace/my-new-project

# Option B — work on an existing project in your home dir
sudo ./aiagent.sh share ~/projects/my-app
./aiagent.sh run --project ~/projects/my-app

# Option C — share and run in the current directory
cd ~/projects/my-app
sudo ./aiagent.sh share .
./aiagent.sh run --project .
```

### Rotating an API key

```bash
sudo ./aiagent.sh add-key anthropic
# Enter new key at the prompt
# The old key is replaced in-place — no duplicate entries
```

### Checking what the agent can see

```bash
# Open a shell as the agent user
sudo -u aiagent -i

# From inside that shell, these should all fail or return empty:
ls /Users/yourname        # Permission denied
cat ~/.aws/credentials    # No such file
ssh-add -l               # no identities (empty keychain)

# This should work:
ls /opt/ai-workspace      # your projects are here
```

### Removing access to a project when done

```bash
sudo ./aiagent.sh unshare ~/projects/my-app

# Or from the shared directory
cd ~/projects/my-app
sudo ./aiagent.sh unshare .
```

### Connecting as the aiagent user

You can open an interactive shell as the `aiagent` user to inspect its
environment, debug issues, or run commands manually.

```bash
# Open a login shell as aiagent
sudo -u aiagent -i

# You are now aiagent — load nvm and tools
source ~/.nvm/nvm.sh
export PATH="$HOME/.npm-global/bin:$PATH"

# Verify
whoami          # aiagent
node --version  # v20.x.x
claude --version
gemini --version

# Check what the agent can and cannot see
ls ~/                     # agent's own home
ls /opt/ai-workspace      # shared workspace
ls /Users/yourname        # Permission denied — isolation works

# Exit back to your main account
exit
```

You can also run a single command without entering an interactive shell:

```bash
# Check claude version
sudo -u aiagent -i zsh -c 'source ~/.nvm/nvm.sh && claude --version'

# Check gemini version
sudo -u aiagent -i zsh -c 'source ~/.nvm/nvm.sh && export PATH="$HOME/.npm-global/bin:$PATH" && gemini --version'

# List installed global npm packages
sudo -u aiagent -i zsh -c 'source ~/.nvm/nvm.sh && npm list -g --depth=0'
```

> **Note:** The `aiagent` user has a random password set during install and
> is hidden from the login screen. You cannot log in as `aiagent` via the
> macOS GUI — only via `sudo -u aiagent` from your main account.

### Updating Claude Code / Gemini CLI

```bash
# Option A — re-run install with a specific version
sudo CLAUDE_CODE_VERSION=1.0.15 ./aiagent.sh install

# Option B — switch to agent user and update manually
sudo -u aiagent -i
source ~/.nvm/nvm.sh
npm update -g @anthropic-ai/claude-code
npm update -g @google/gemini-cli
exit
```

### Running a one-off command as the agent

```bash
# Without fully switching users
sudo -u aiagent -i bash -c 'source ~/.nvm/nvm.sh && claude --version'
```

---

## 10. Troubleshooting

### `command not found: claude` inside the agent shell

nvm is not loaded. Either source it manually or use the `run` command which
loads it automatically:

```bash
# Manual fix inside an agent shell:
source ~/.nvm/nvm.sh

# Or use the script which handles this:
./aiagent.sh run
```

### Permission denied on the shared workspace

The `chown` step in `install` may not have run correctly. Fix manually:

```bash
sudo chown aiagent:staff /opt/ai-workspace
sudo chmod 750 /opt/ai-workspace
```

### `dscl` error: eDSRecordAlreadyExists

The user or group already exists from a previous partial install. The `install`
command handles this gracefully — it detects existing entries and skips them.
If you see this outside the script, run `status` to check the current state.

### Agent can still see a folder after `unshare`

ACL changes take effect immediately but a running agent process may have an
open file descriptor. Restart the agent:

```bash
# Kill any running agent processes
sudo pkill -u aiagent
# Then re-run
./aiagent.sh run --project ~/projects/my-app
```

### Apple Silicon — nvm install warning about platform

You may see:
```
WARNING: The requested image's platform (linux/amd64) does not match...
```

This is from Docker, not this script. For the OS user approach, nvm selects
the correct ARM64 Node binary automatically. No action needed.

### UID/GID conflict (601/600 already in use)

Edit the config section at the top of the script and change `AGENT_UID` and
`AGENT_GID` to unused values. Check existing IDs with:

```bash
dscl . -list /Users UniqueID | sort -k2 -n | tail -20
dscl . -list /Groups PrimaryGroupID | sort -k2 -n | tail -20
```

---

## 11. Shell Script Internals

This section explains how `aiagent.sh` is structured for developers who
want to understand, fork, or extend it.

### Architecture

The script uses a **subcommand dispatch pattern**:

```
aiagent.sh <command> [args]
        │
        ▼
   case "$COMMAND" in
     install)  cmd_install  "$@" ;;
     status)   cmd_status   "$@" ;;
     run)      cmd_run      "$@" ;;
     ...
   esac
```

Each command is a self-contained function prefixed with `cmd_`. This makes it
easy to add new commands without modifying existing ones.

### Strict mode

```bash
set -euo pipefail
```

| Flag | Effect |
|------|--------|
| `-e` | Exit immediately if any command returns non-zero |
| `-u` | Treat unset variables as errors |
| `-o pipefail` | Pipe fails if any command in it fails (not just the last) |

### Logging functions

Five logging functions produce colour-coded, emoji-prefixed output to stderr:

```bash
log_info()    { echo -e "${BLUE}ℹ️  $*${NC}" >&2; }    # informational
log_success() { echo -e "${GREEN}✅ $*${NC}" >&2; }    # success confirmation
log_warning() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }  # non-fatal warning
log_error()   { echo -e "${RED}❌ $*${NC}" >&2; }      # error (does not exit)
die()         { log_error "$*"; exit 1; }              # fatal error, exits
step()        { echo -e "\n${BOLD}${BLUE}▶ $*${NC}" >&2; } # section header
dim()         { echo -e "${DIM}  $*${NC}" >&2; }       # indented detail line
```

All output goes to stderr so it doesn't interfere with piped stdout.
Colour codes are stored as `readonly` variables at the top of the file.

### Guard functions

```bash
require_macos() {
  [[ "$(uname)" == "Darwin" ]] || die "This script is for macOS only."
}

require_sudo() {
  [[ "$EUID" -eq 0 ]] || die "This command requires sudo. ..."
}

user_exists() {
  dscl . -read "/Users/${AGENT_USER}" UniqueID &>/dev/null
}
```

`require_macos` is called once at the entry point before dispatch.
`require_sudo` is called at the top of every command that needs it.
`user_exists` is used as a precondition check in `run`, `add-key`, and
`teardown`.

### Bootstrap pattern

`cmd_install` cannot simply run npm commands as `aiagent` line by line,
because it is running as root. Instead it writes a bootstrap script to a
temp file using `printf` (not heredocs, to avoid variable expansion issues)
and executes it as the agent user:

```bash
_bootstrap=$(mktemp /tmp/aiagent_bootstrap.XXXXXX)
mv "${_bootstrap}" "${_bootstrap}.sh"
# ... write script with printf ...
cd "${AGENT_HOME}"  # critical: agent can't access caller's cwd
sudo -u "${AGENT_USER}" HOME="${AGENT_HOME}" bash "${_bootstrap}"
rm -f "${_bootstrap}"
```

The bootstrap sets `HOME` and `USER` explicitly so nvm installs into the
agent's home directory, not root's. The `cd` to `AGENT_HOME` before `sudo -u`
is critical — without it, the child process inherits the caller's cwd which
the agent user cannot access, causing `getcwd: Permission denied` errors.

### `exec` in `cmd_run`

`cmd_run` writes a temp zsh script and runs it as the agent user:

```bash
_run_script=$(mktemp /tmp/aiagent_run.XXXXXX)
chmod 755 "${_run_script}"
cat > "${_run_script}" <<RUNEOF
#!/usr/bin/env zsh
export ZSH_DISABLE_COMPFIX=true
[ -f "\$HOME/.zshrc" ] && source "\$HOME/.zshrc" 2>/dev/null || true
# ... load nvm, set PATH ...
exec ${_cmd}
RUNEOF
exec sudo -u "${AGENT_USER}" HOME="${AGENT_HOME}" zsh "${_run_script}"
```

Using a temp file instead of `zsh -c "..."` avoids quoting/escaping issues
that caused error messages to be silently swallowed. `exec` **replaces** the
current shell process so `Ctrl+C` sends `SIGINT` directly to the agent.

Before launching, `cmd_run` also verifies the agent user can actually
traverse to the project directory, and prints a clear error if not.

### In-place key replacement

`add-key` uses `awk` + temp file + `mv` instead of `sed -i` to avoid both
the macOS/GNU `sed -i` incompatibility and injection vulnerabilities when
the API key contains special characters (`|`, `&`, `\`, `'`):

```bash
_tmp=$(mktemp)
_new_line="export ${_env_var}='${_key//\'/\'\"\'\'\"\'}'"
awk -v var="^export ${_env_var}=" -v repl="${_new_line}" \
  '{ if ($0 ~ var) print repl; else print }' \
  "${_zshrc}" > "${_tmp}"
mv "${_tmp}" "${_zshrc}"
```

Single quotes in the key value are escaped to prevent shell injection.

### Config section

All tuneable values live at the top of the script in clearly marked variables:

```bash
AGENT_USER="aiagent"      # macOS username
AGENT_REALNAME="AI Agent" # display name
AGENT_UID=601             # must be unused on your system
AGENT_GID=600             # must be unused on your system
AGENT_HOME="/Users/${AGENT_USER}"
WORKSPACE="/opt/ai-workspace"
NODE_VERSION="20"
NVM_VERSION="0.39.7"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-latest}"  # override via env var
GEMINI_CLI_VERSION="${GEMINI_CLI_VERSION:-latest}"    # override via env var
```

To use a different username, change only `AGENT_USER`. Everything else
is derived from it.

To pin tool versions, set the environment variables before running install:

```bash
sudo CLAUDE_CODE_VERSION=1.0.12 GEMINI_CLI_VERSION=0.3.0 ./aiagent.sh install
```

### Adding a new command

1. Write a `cmd_mycommand()` function
2. Add it to the `case` block at the bottom
3. Add it to `cmd_help()`

```bash
cmd_mycommand() {
  require_sudo mycommand    # if needed
  step "Doing my thing"
  # ...
  log_success "Done"
}

# In the case block:
mycommand) cmd_mycommand "$@" ;;

# In cmd_help():
echo -e "  ${CYAN}mycommand${NC}"
echo -e "    Description of what it does."
```

---

## 12. Uninstall

### Remove everything

```bash
sudo ./aiagent.sh teardown
# Type 'aiagent' to confirm
```

This removes:
- The `aiagent` macOS user and group
- `/Users/aiagent/` — home directory, Node, nvm, Claude Code, Gemini CLI, API keys
- `/opt/ai-workspace/` — shared workspace

### Remove only the tools (keep the user)

```bash
sudo -u aiagent -i
npm uninstall -g @anthropic-ai/claude-code
npm uninstall -g @google/gemini-cli
rm -rf ~/.nvm
exit
```

### Remove only the API key

```bash
sudo -u aiagent -i
# Edit ~/.zshrc and delete the ANTHROPIC_API_KEY line
nano ~/.zshrc
exit
```

Or use `add-key` to replace it with a new value.

---

*Generated by `aiagent.sh` — macOS 12+ — Claude Code & Gemini CLI isolation*
