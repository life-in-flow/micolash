# cage jail module — sandbox-exec (Seatbelt) enforcement
#
# Provides the core jail_run function that executes commands
# inside the macOS Seatbelt sandbox.

# Run a command inside the Seatbelt jail for a given sandbox.
#
# Usage: jail_run <sandbox_dir> <workspace> <command...>
#
# The jail restricts file writes to:
#   - sandbox_dir (sandbox root)
#   - workspace (git worktree / mounted repo)
#   - /tmp, /private/tmp, /var/folders
#   - /dev (for /dev/null, /dev/tty, etc.)
#
# Everything else (reads, network, process exec) is unrestricted.

jail_run() {
    local sandbox_dir="$1"
    local workspace="$2"
    shift 2

    source "$sandbox_dir/.env"

    sandbox-exec -f "$CAGE_SB_PROFILE" \
        -D "SANDBOX_ROOT=$sandbox_dir" \
        -D "SANDBOX_WORKSPACE=$workspace" \
        env \
            CAGE_NAME="${SANDBOX_NAME}" \
            CAGE_ROOT="$sandbox_dir" \
            CAGE_WORKSPACE="$workspace" \
            HOME="$sandbox_dir/home" \
            PATH="$sandbox_dir/tools/bin:$PATH" \
            PGHOST="${SANDBOX_PG_HOST:-localhost}" \
            PGPORT="${SANDBOX_PG_PORT:-5432}" \
            PGUSER="sandbox" \
            PGPASSWORD="sandbox" \
            PGDATABASE="flow" \
            DATABASE_URL="postgresql://sandbox:sandbox@localhost:${SANDBOX_PG_PORT:-5432}/flow" \
            NATS_URL="nats://localhost:${SANDBOX_NATS_PORT:-4222}" \
            REDIS_URL="redis://localhost:${SANDBOX_REDIS_PORT:-6379}" \
        "$@"
}

# Run a shell command string inside the jail.
#
# Usage: jail_exec <sandbox_dir> <workspace> <shell_command_string>

jail_exec() {
    local sandbox_dir="$1"
    local workspace="$2"
    local cmd="$3"

    jail_run "$sandbox_dir" "$workspace" \
        /bin/bash -c "cd '$workspace' 2>/dev/null; $cmd"
}

# Launch an interactive bash shell inside the jail.
#
# Usage: jail_shell <sandbox_dir> <workspace>

jail_shell() {
    local sandbox_dir="$1"
    local workspace="$2"
    local name
    name="$(basename "$sandbox_dir")"

    jail_run "$sandbox_dir" "$workspace" \
        env PS1="(cage:${name}) \w \$ " \
        /bin/bash --norc -c "
            cd '$workspace' 2>/dev/null || true
            echo ''
            echo 'Cage: $name (jailed)'
            echo 'Workspace: $workspace'
            echo 'Write access: $sandbox_dir, $workspace, /tmp'
            echo ''
            echo 'Type \"exit\" to leave.'
            echo ''
            exec /bin/bash --norc
        "
}
