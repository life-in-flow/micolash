# cage agent module — launch Claude Code inside the jail

cage_agent() {
    local name="${1:-}"
    shift || true

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage agent <name> [--prompt <prompt>] [--print]"
        exit 1
    fi

    local sandbox_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$sandbox_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    # Parse optional flags
    local prompt=""
    local print_mode=false
    local claude_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prompt|-p)  prompt="$2"; shift 2 ;;
            --print)      print_mode=true; shift ;;
            --)           shift; claude_args+=("$@"); break ;;
            *)            claude_args+=("$1"); shift ;;
        esac
    done

    source "$sandbox_dir/.env"

    local workspace="${SANDBOX_WORKSPACE:-$sandbox_dir/workspace}"

    # Verify claude is available
    if ! command -v claude &>/dev/null; then
        log_error "Claude Code CLI not found"
        echo "  Install: https://docs.anthropic.com/en/docs/claude-code"
        exit 1
    fi

    # Set up sandbox-local Claude config
    local sandbox_home="$sandbox_dir/home"
    mkdir -p "$sandbox_home/.claude"

    # Write a CLAUDE.md into the sandbox so the agent knows its context
    local sandbox_claude_md="$sandbox_dir/CLAUDE.md"
    if [[ ! -f "$sandbox_claude_md" ]]; then
        cat > "$sandbox_claude_md" <<AGENT_MD
# Cage: Sandbox Agent Environment

You are running inside a jailed sandbox environment (micolash cage).

## Environment
- **Cage name**: $name
- **Workspace**: $workspace
- **Sandbox root**: $sandbox_dir
- **Write access**: Only this sandbox directory and workspace. All other paths are read-only.

## Infrastructure
- **PostgreSQL**: \$DATABASE_URL (localhost:${SANDBOX_PG_PORT:-5432}, user: sandbox, db: flow)
- **NATS**: \$NATS_URL (localhost:${SANDBOX_NATS_PORT:-4222})
- **Redis**: \$REDIS_URL (localhost:${SANDBOX_REDIS_PORT:-6379})

## Rules
- You have full permissions inside this cage. Use them freely.
- All file writes are restricted to the workspace and sandbox directory by the OS-level jail.
- You can install tools, run builds, execute tests, and modify any file in the workspace.
- Commit your work to git branches in the workspace.
AGENT_MD
    fi

    log_info "Launching Claude Code agent in cage: ${BOLD}$name${NC}"
    echo ""
    echo "  Workspace:    $workspace"
    echo "  Permissions:  all actions auto-approved (jailed by sandbox-exec)"
    echo "  Infra:        Postgres:${SANDBOX_PG_PORT:-5432} NATS:${SANDBOX_NATS_PORT:-4222} Redis:${SANDBOX_REDIS_PORT:-6379}"
    echo ""

    # Build the claude command
    local claude_cmd="claude --dangerously-skip-permissions"

    if [[ -n "$prompt" ]]; then
        claude_cmd="$claude_cmd --print --prompt $(printf '%q' "$prompt")"
    elif [[ "$print_mode" == true ]]; then
        claude_cmd="$claude_cmd --print"
    fi

    # Append any extra args
    if [[ ${#claude_args[@]} -gt 0 ]]; then
        for arg in "${claude_args[@]}"; do
            claude_cmd="$claude_cmd $(printf '%q' "$arg")"
        done
    fi

    # Launch Claude inside the Seatbelt jail
    jail_run "$sandbox_dir" "$workspace" \
        /bin/bash -c "cd '$workspace' && $claude_cmd"
}
