# cage sandbox lifecycle — create, destroy, enter, shell, exec, list, status

# ============================================
# CREATE
# ============================================

cage_create() {
    local name=""
    local repo=""
    local branch=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-n)    name="$2"; shift 2 ;;
            --repo|-r)    repo="$2"; shift 2 ;;
            --branch|-b)  branch="$2"; shift 2 ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"; shift
                else
                    log_error "Unknown argument: $1"
                    exit 1
                fi
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage create <name> [--repo <path>] [--branch <branch>]"
        exit 1
    fi

    local cage_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ -d "$cage_dir" ]]; then
        log_error "Cage '$name' already exists at $cage_dir"
        log_info "Use 'cage destroy $name' first, or choose a different name."
        exit 1
    fi

    log_info "Creating cage: ${BOLD}$name${NC}"

    # Directory structure
    log_step "Creating directory structure"
    mkdir -p "$cage_dir"/{home,tools/bin}

    # Workspace
    local workspace_dir="$cage_dir/workspace"

    if [[ -n "$repo" ]]; then
        repo="$(cd "$repo" 2>/dev/null && pwd)" || {
            log_error "Repository path not found: $repo"
            rm -rf "$cage_dir"
            exit 1
        }

        if [[ -n "$branch" ]]; then
            log_step "Creating git worktree from $repo (branch: $branch)"
            git -C "$repo" worktree add "$workspace_dir" -b "cage/$name" "${branch}" 2>/dev/null || \
            git -C "$repo" worktree add --detach "$workspace_dir" "${branch}" || {
                log_error "Failed to create git worktree"
                rm -rf "$cage_dir"
                exit 1
            }
        else
            log_step "Linking repository: $repo"
            ln -s "$repo" "$workspace_dir"
        fi
    else
        log_step "Creating empty workspace"
        mkdir -p "$workspace_dir"
    fi

    # Write .env config
    log_step "Writing configuration"
    cat > "$cage_dir/.env" <<EOF
# Micolash Cage: $name
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
CAGE_NAME=$name
CAGE_ROOT=$cage_dir
CAGE_WORKSPACE=$workspace_dir
EOF

    [[ -n "$repo" ]] && echo "CAGE_REPO=$repo" >> "$cage_dir/.env"
    [[ -n "$branch" ]] && echo "CAGE_BRANCH=$branch" >> "$cage_dir/.env"

    echo ""
    log_success "Cage '${BOLD}$name${NC}' created"
    echo ""
    echo "  Enter (Claude Code, full permissions, jailed):"
    echo "    cage enter $name"
    echo ""
    echo "  Raw shell (jailed):"
    echo "    cage shell $name"
    echo ""
    echo "  Run a command (jailed):"
    echo "    cage exec $name -- <command>"
    echo ""
    [[ -n "$repo" ]] && echo "  Workspace: $workspace_dir"
    echo "  Cage root: $cage_dir"
}

# ============================================
# DESTROY
# ============================================

cage_destroy() {
    local name="${1:-}"
    local force=false

    if [[ "$name" == "--force" || "$name" == "-f" ]]; then
        force=true
        name="${2:-}"
    fi
    [[ "${2:-}" == "--force" || "${2:-}" == "-f" ]] && force=true

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage destroy <name> [--force]"
        exit 1
    fi

    local cage_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$cage_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    if [[ "$force" != true ]]; then
        echo -n "Destroy cage '$name' and all its data? [y/N] "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Cancelled."
            return 0
        fi
    fi

    log_info "Destroying cage: $name"

    # Remove git worktree if applicable
    if [[ -f "$cage_dir/.env" ]]; then
        source "$cage_dir/.env"
        local workspace="${CAGE_WORKSPACE:-}"
        local repo="${CAGE_REPO:-}"

        if [[ -n "$repo" && -n "$workspace" && -d "$workspace/.git" ]]; then
            log_step "Removing git worktree"
            git -C "$repo" worktree remove "$workspace" --force 2>/dev/null || true
        fi
    fi

    log_step "Removing cage directory"
    rm -rf "$cage_dir"

    log_success "Cage '$name' destroyed"
}

# ============================================
# ENTER (default = Claude Code agent)
# ============================================

cage_enter() {
    local name="${1:-}"
    shift || true

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage enter <name>"
        exit 1
    fi

    cage_agent "$name" "$@"
}

# ============================================
# SHELL (raw bash in jail)
# ============================================

cage_shell() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage shell <name>"
        exit 1
    fi

    local cage_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$cage_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    source "$cage_dir/.env"

    log_info "Entering cage shell: ${BOLD}$name${NC} (jailed)"
    jail_shell "$cage_dir" "$CAGE_WORKSPACE"
}

# ============================================
# EXEC (single command in jail)
# ============================================

cage_exec() {
    local name="${1:-}"
    shift || true

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage exec <name> [--] <command...>"
        exit 1
    fi

    [[ "${1:-}" == "--" ]] && shift

    if [[ $# -eq 0 ]]; then
        log_error "No command specified"
        echo "Usage: cage exec <name> [--] <command...>"
        exit 1
    fi

    local cage_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$cage_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    source "$cage_dir/.env"
    jail_exec "$cage_dir" "$CAGE_WORKSPACE" "$*"
}

# ============================================
# LIST
# ============================================

cage_list() {
    if [[ ! -d "$CAGE_SANDBOX_DIR" ]] || [[ -z "$(ls -A "$CAGE_SANDBOX_DIR" 2>/dev/null)" ]]; then
        log_info "No cages found"
        echo "  Create one with: cage create <name>"
        return 0
    fi

    echo ""
    printf "  ${BOLD}%-20s %-40s${NC}\n" "NAME" "WORKSPACE"
    printf "  %-20s %-40s\n" "----" "---------"

    for cage_dir in "$CAGE_SANDBOX_DIR"/*/; do
        [[ -d "$cage_dir" ]] || continue
        local name
        name="$(basename "$cage_dir")"
        local workspace="-"

        if [[ -f "$cage_dir/.env" ]]; then
            source "$cage_dir/.env"
            workspace="${CAGE_WORKSPACE:-$cage_dir/workspace}"
        fi

        printf "  %-20s %-40s\n" "$name" "$workspace"
    done
    echo ""
}

# ============================================
# STATUS
# ============================================

cage_status() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        cage_list
        return
    fi

    local cage_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$cage_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    source "$cage_dir/.env"

    echo ""
    echo "  ${BOLD}Cage: $name${NC}"
    echo "  Root:      $cage_dir"
    echo "  Workspace: ${CAGE_WORKSPACE:-n/a}"
    echo "  Repo:      ${CAGE_REPO:-n/a}"
    echo "  Branch:    ${CAGE_BRANCH:-n/a}"
    echo ""
    echo "  ${BOLD}Jail:${NC} macOS sandbox-exec (Seatbelt)"
    echo "  Write access: $cage_dir, ${CAGE_WORKSPACE:-n/a}, /tmp"
    echo ""
}

# ============================================
# HELP
# ============================================

cage_help() {
    cat <<'EOF'

  micolash cage — Jailed developer sandbox for autonomous AI agents

  Usage:
    cage create <name> [options]    Create a new cage
    cage destroy <name> [--force]   Destroy a cage and all its data
    cage enter <name>               Launch Claude Code (jailed, full permissions)
    cage shell <name>               Enter a raw bash shell (jailed)
    cage exec <name> -- <cmd>       Run a single command (jailed)
    cage list                       List all cages
    cage status [<name>]            Show cage details
    cage setup                      Install cage to PATH

  Create options:
    --repo, -r <path>       Mount a git repository as the workspace
    --branch, -b <branch>   Create a git worktree from this branch

  Agent options (enter/agent):
    --prompt, -p <prompt>   Run non-interactively with this prompt
    --print                 Non-interactive mode (output only)

  Examples:
    cage create my-task --repo ~/code/myapp --branch main
    cage enter my-task
    cage enter my-task --prompt "fix the failing tests"
    cage shell my-task
    cage exec my-task -- make test
    cage destroy my-task

  How it works:
    macOS sandbox-exec (Seatbelt) jails all processes inside the cage.
    File writes are restricted to the cage directory and workspace only.
    Reads, network, and process execution are fully unrestricted.

    'cage enter' launches Claude Code with --dangerously-skip-permissions.
    The agent gets full autonomy. The OS enforces that writes stay in the cage.

EOF
}
