# cage agent — launch Claude Code inside the jail with full permissions

cage_agent() {
    local name="${1:-}"
    shift || true

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage agent <name> [--prompt <prompt>] [--print]"
        exit 1
    fi

    local cage_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$cage_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    # Parse flags
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

    source "$cage_dir/.env"
    local workspace="${CAGE_WORKSPACE}"

    if ! command -v claude &>/dev/null; then
        log_error "Claude Code CLI not found"
        echo "  Install: https://docs.anthropic.com/en/docs/claude-code"
        exit 1
    fi

    # Set up sandbox-local Claude config
    mkdir -p "$cage_dir/home/.claude"

    # Write a CLAUDE.md so the agent knows its context
    if [[ ! -f "$cage_dir/CLAUDE.md" ]]; then
        cat > "$cage_dir/CLAUDE.md" <<AGENT_MD
# Cage: $name

You are running inside a jailed sandbox (micolash cage).

## Environment
- **Workspace**: $workspace
- **Cage root**: $cage_dir
- **Write access**: Only the cage directory and workspace. All other paths are read-only.

## Rules
- You have full permissions inside this cage. Use them freely.
- File writes outside the cage are blocked at the OS level.
- Install tools, run builds, execute tests, modify any file in the workspace.
- Commit your work to git branches.
AGENT_MD
    fi

    log_info "Launching Claude Code in cage: ${BOLD}$name${NC}"
    echo ""
    echo "  Workspace:    $workspace"
    echo "  Permissions:  full (jailed by sandbox-exec)"
    echo ""

    # Build claude command
    local claude_cmd="claude --dangerously-skip-permissions"

    if [[ -n "$prompt" ]]; then
        claude_cmd="$claude_cmd --print --prompt $(printf '%q' "$prompt")"
    elif [[ "$print_mode" == true ]]; then
        claude_cmd="$claude_cmd --print"
    fi

    if [[ ${#claude_args[@]} -gt 0 ]]; then
        for arg in "${claude_args[@]}"; do
            claude_cmd="$claude_cmd $(printf '%q' "$arg")"
        done
    fi

    jail_run "$cage_dir" "$workspace" \
        /bin/bash -c "cd '$workspace' && $claude_cmd"
}
