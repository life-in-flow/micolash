# /cage — Work inside a jailed sandbox

Use when the user says "cage", "sandbox", "jailed", "work in a cage", or wants isolated autonomous work.

## How it works

You stay as the ONE Claude session. No second Claude, no MCP, no agent-to-agent.
The cage jails your Bash commands via macOS sandbox-exec. File operations are scoped to the cage workspace.

## Workflow

### 1. Create the cage

```bash
cage create <name> --repo <repo-path> --branch <branch>
```

This creates:
- `~/.micolash/cages/<name>/workspace/` — a git worktree (your working directory)
- `~/.micolash/cages/<name>/home/` — sandbox HOME
- `~/.micolash/cages/<name>/tools/bin/` — sandbox-local tool installs

### 2. Switch to cage mode

After creating the cage, read the `.env` file to get paths:
```bash
cat ~/.micolash/cages/<name>/.env
```

Then follow these rules for ALL subsequent work:

**File operations (Read/Edit/Write):**
- Use the CAGE_WORKSPACE path for all file operations
- Example: Read/Edit/Write to `~/.micolash/cages/<name>/workspace/src/main.py`
- Do NOT touch files outside the cage workspace

**Shell commands (Bash):**
- Prefix ALL Bash commands with `cage exec <name> --`
- Example: `cage exec <name> -- make test`
- Example: `cage exec <name> -- git status`
- Example: `cage exec <name> -- npm install`
- The jail enforces this — writes outside the cage return "Operation not permitted"

### 3. Git workflow inside the cage

```bash
cage exec <name> -- git checkout -b fix/my-thing
# ... make changes via Edit/Write tools ...
cage exec <name> -- git add -A
cage exec <name> -- git commit -m "fix: the thing"
```

### 4. Destroy when done

```bash
cage destroy <name> --force
```

## Example session

User: "create a cage for the flow repo and fix the auth bug"

```bash
# Create cage
cage create fix-auth --repo ~/Documents/github/flow --branch main

# Read the env
cat ~/.micolash/cages/fix-auth/.env

# All Bash goes through the jail
cage exec fix-auth -- grep -r "authenticate" src/
cage exec fix-auth -- make test

# File edits use the workspace path directly
# Edit ~/.micolash/cages/fix-auth/workspace/src/auth.py

# Git via jail
cage exec fix-auth -- git add -A
cage exec fix-auth -- git commit -m "fix: auth bug"

# Clean up
cage destroy fix-auth --force
```
