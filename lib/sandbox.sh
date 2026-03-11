# cage sandbox lifecycle — create, destroy, enter, list, status

# ============================================
# CREATE
# ============================================

cage_create() {
    local name=""
    local repo=""
    local branch=""
    local no_infra=false
    local infra_profile="default"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-n)    name="$2"; shift 2 ;;
            --repo|-r)    repo="$2"; shift 2 ;;
            --branch|-b)  branch="$2"; shift 2 ;;
            --no-infra)   no_infra=true; shift ;;
            --profile)    infra_profile="$2"; shift 2 ;;
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
        echo "Usage: cage create <name> [--repo <path>] [--branch <branch>] [--no-infra]"
        exit 1
    fi

    local sandbox_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ -d "$sandbox_dir" ]]; then
        log_error "Cage '$name' already exists at $sandbox_dir"
        log_info "Use 'cage destroy $name' first, or choose a different name."
        exit 1
    fi

    log_info "Creating cage: ${BOLD}$name${NC}"

    # ---- Directory structure ----
    log_step "Creating directory structure"
    mkdir -p "$sandbox_dir"/{home,tools/bin,infra}

    # ---- Workspace (git worktree or repo symlink) ----
    local workspace_dir="$sandbox_dir/workspace"

    if [[ -n "$repo" ]]; then
        repo="$(cd "$repo" 2>/dev/null && pwd)" || {
            log_error "Repository path not found: $repo"
            rm -rf "$sandbox_dir"
            exit 1
        }

        if [[ -n "$branch" ]]; then
            log_step "Creating git worktree from $repo (branch: $branch)"
            git -C "$repo" worktree add "$workspace_dir" -b "cage/$name" "${branch}" 2>/dev/null || \
            git -C "$repo" worktree add --detach "$workspace_dir" "${branch}" || {
                log_error "Failed to create git worktree"
                rm -rf "$sandbox_dir"
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

    # ---- Allocate unique ports ----
    local pg_port nats_port nats_monitor_port redis_port
    pg_port=$(cage_alloc_port 5432)
    nats_port=$(cage_alloc_port 4222)
    nats_monitor_port=$(cage_alloc_port 8222)
    redis_port=$(cage_alloc_port 6379)

    # ---- Write .env config ----
    log_step "Writing configuration"
    cat > "$sandbox_dir/.env" <<EOF
# Micolash Cage: $name
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
SANDBOX_NAME=$name
SANDBOX_ROOT=$sandbox_dir
SANDBOX_WORKSPACE=$workspace_dir
SANDBOX_PG_PORT=$pg_port
SANDBOX_NATS_PORT=$nats_port
SANDBOX_NATS_MONITOR_PORT=$nats_monitor_port
SANDBOX_REDIS_PORT=$redis_port
SANDBOX_INFRA_PROFILE=$infra_profile
EOF

    [[ -n "$repo" ]] && echo "SANDBOX_REPO=$repo" >> "$sandbox_dir/.env"
    [[ -n "$branch" ]] && echo "SANDBOX_BRANCH=$branch" >> "$sandbox_dir/.env"

    # ---- Copy activate script ----
    if [[ -f "$CAGE_ACTIVATE_TEMPLATE" ]]; then
        cp "$CAGE_ACTIVATE_TEMPLATE" "$sandbox_dir/activate.sh"
        chmod +x "$sandbox_dir/activate.sh"
    fi

    # ---- Start infrastructure ----
    if [[ "$no_infra" == false ]]; then
        log_step "Starting infrastructure (Postgres:$pg_port, NATS:$nats_port, Redis:$redis_port)"
        cage_infra_up "$name"
    fi

    # ---- Done ----
    echo ""
    log_success "Cage '${BOLD}$name${NC}' created"
    echo ""
    echo "  Enter (launches Claude Code with full permissions, jailed):"
    echo "    cage enter $name"
    echo ""
    echo "  Raw shell:"
    echo "    cage shell $name"
    echo ""
    echo "  Run a command:"
    echo "    cage exec $name -- <command>"
    echo ""
    [[ -n "$repo" ]] && echo "  Workspace: $workspace_dir"
    echo "  Cage root: $sandbox_dir"
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
    if [[ "${2:-}" == "--force" || "${2:-}" == "-f" ]]; then
        force=true
    fi

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage destroy <name> [--force]"
        exit 1
    fi

    local sandbox_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$sandbox_dir" ]]; then
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

    # Stop infrastructure
    cage_infra_down "$name" 2>/dev/null || true

    # Remove git worktree if workspace is one
    if [[ -f "$sandbox_dir/.env" ]]; then
        source "$sandbox_dir/.env"
        local workspace="${SANDBOX_WORKSPACE:-}"
        local repo="${SANDBOX_REPO:-}"

        if [[ -n "$repo" && -n "$workspace" && -d "$workspace/.git" ]]; then
            log_step "Removing git worktree"
            git -C "$repo" worktree remove "$workspace" --force 2>/dev/null || true
        fi
    fi

    log_step "Removing cage directory"
    rm -rf "$sandbox_dir"

    log_success "Cage '$name' destroyed"
}

# ============================================
# ENTER (default = Claude Code agent in jail)
# ============================================

cage_enter() {
    local name="${1:-}"
    shift || true

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage enter <name> [claude args...]"
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

    local sandbox_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$sandbox_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    source "$sandbox_dir/.env"
    local workspace="${SANDBOX_WORKSPACE:-$sandbox_dir/workspace}"

    log_info "Entering cage shell: ${BOLD}$name${NC} (jailed via sandbox-exec)"

    jail_shell "$sandbox_dir" "$workspace"
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

    local sandbox_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$sandbox_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    source "$sandbox_dir/.env"
    local workspace="${SANDBOX_WORKSPACE:-$sandbox_dir/workspace}"

    jail_exec "$sandbox_dir" "$workspace" "$*"
}

# ============================================
# LIST
# ============================================

cage_list() {
    if [[ ! -d "$CAGE_SANDBOX_DIR" ]] || [[ -z "$(ls -A "$CAGE_SANDBOX_DIR" 2>/dev/null)" ]]; then
        log_info "No cages found"
        echo "Create one with: cage create <name>"
        return 0
    fi

    echo ""
    printf "  ${BOLD}%-20s %-10s %-40s${NC}\n" "NAME" "INFRA" "WORKSPACE"
    printf "  %-20s %-10s %-40s\n" "----" "-----" "---------"

    for sandbox_dir in "$CAGE_SANDBOX_DIR"/*/; do
        [[ -d "$sandbox_dir" ]] || continue
        local name
        name="$(basename "$sandbox_dir")"
        local infra_status="down"
        local workspace="-"

        if [[ -f "$sandbox_dir/.env" ]]; then
            source "$sandbox_dir/.env"
            workspace="${SANDBOX_WORKSPACE:-$sandbox_dir/workspace}"

            local project="cage-${name}"
            if docker compose -p "$project" -f "$CAGE_COMPOSE_FILE" ps --status running 2>/dev/null | grep -q "running"; then
                infra_status="${GREEN}up${NC}"
            else
                infra_status="${DIM}down${NC}"
            fi
        fi

        printf "  %-20s %-10b %-40s\n" "$name" "$infra_status" "$workspace"
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

    local sandbox_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -d "$sandbox_dir" ]]; then
        log_error "Cage '$name' not found"
        exit 1
    fi

    source "$sandbox_dir/.env"

    echo ""
    echo "  ${BOLD}Cage: $name${NC}"
    echo "  Root:      $sandbox_dir"
    echo "  Workspace: ${SANDBOX_WORKSPACE:-n/a}"
    echo "  Repo:      ${SANDBOX_REPO:-n/a}"
    echo "  Branch:    ${SANDBOX_BRANCH:-n/a}"
    echo ""
    echo "  ${BOLD}Infrastructure:${NC}"
    echo "  PostgreSQL: localhost:${SANDBOX_PG_PORT:-5432}"
    echo "  NATS:       localhost:${SANDBOX_NATS_PORT:-4222}"
    echo "  Redis:      localhost:${SANDBOX_REDIS_PORT:-6379}"
    echo ""

    local project="cage-${name}"
    echo "  ${BOLD}Services:${NC}"
    docker compose -p "$project" -f "$CAGE_COMPOSE_FILE" ps 2>/dev/null || echo "  (not running)"
    echo ""
}

# ============================================
# HELP
# ============================================

cage_help() {
    cat <<'EOF'

  micolash cage — Jailed developer sandbox for autonomous AI agents

  Usage:
    cage create <name> [options]       Create a new cage
    cage destroy <name> [--force]      Destroy a cage and all its data
    cage enter <name>                  Launch Claude Code agent (jailed, full permissions)
    cage shell <name>                  Enter a raw bash shell (jailed)
    cage exec <name> -- <cmd>          Run a single command (jailed)
    cage agent <name> [options]        Launch Claude Code agent (same as enter)
    cage list                          List all cages
    cage status [<name>]               Show cage status and infrastructure
    cage infra <up|down|restart> <name> Manage infrastructure services
    cage setup                         Install cage to PATH

  Create options:
    --repo, -r <path>       Mount a git repository as the workspace
    --branch, -b <branch>   Create a git worktree from this branch
    --no-infra              Skip starting infrastructure (Postgres, NATS, Redis)

  Agent options:
    --prompt, -p <prompt>   Run non-interactively with this prompt
    --print                 Non-interactive mode (output only)

  Examples:
    cage create my-feature --repo ~/code/myapp --branch main
    cage enter my-feature
    cage agent my-feature --prompt "fix the failing tests"
    cage shell my-feature
    cage exec my-feature -- make test
    cage destroy my-feature

  How it works:
    The cage uses macOS sandbox-exec (Seatbelt) to jail all processes.
    File writes are restricted to the cage directory and workspace only.
    Reads, network, and process execution are fully unrestricted.

    'cage enter' launches Claude Code with --dangerously-skip-permissions
    inside the jail. The agent gets full autonomy but the OS enforces that
    writes cannot escape the cage.

EOF
}
