# Micolash

Jailed developer sandbox for autonomous AI agents.

## For users: Working inside a cage

When a cage is active, follow these rules:

1. **All Bash commands** must go through `cage exec <name> -- <command>`
2. **All file operations** (Read/Edit/Write) must target paths inside `~/.micolash/cages/<name>/workspace/`
3. **Do not** write to paths outside the cage workspace

The macOS Seatbelt jail enforces rule 1 at the OS level — commands that try to write outside the cage get "Operation not permitted". Rules 2-3 are convention enforced by the skill.

## Quick reference

```bash
cage create <name> --repo <path> --branch <branch>   # Create a cage
cage enter <name>                                      # Launch jailed Claude Code
cage shell <name>                                      # Raw bash in jail
cage exec <name> -- <cmd>                              # Run command in jail
cage list                                              # List cages
cage status <name>                                     # Show cage details
cage destroy <name> [--force]                          # Tear down cage
cage setup                                             # Install to PATH
```
