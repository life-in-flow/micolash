# cage jail — sandbox-exec (Seatbelt) enforcement
#
# Core primitive: run anything inside a macOS Seatbelt jail.
# Writes restricted to cage dir + workspace + /tmp. Everything else unrestricted.

# Run a command inside the jail.
# Usage: jail_run <cage_dir> <workspace> <command...>
jail_run() {
    local cage_dir="$1"
    local workspace="$2"
    shift 2

    sandbox-exec -f "$CAGE_SB_PROFILE" \
        -D "SANDBOX_ROOT=$cage_dir" \
        -D "SANDBOX_WORKSPACE=$workspace" \
        env \
            CAGE_NAME="$(basename "$cage_dir")" \
            CAGE_ROOT="$cage_dir" \
            CAGE_WORKSPACE="$workspace" \
            HOME="$cage_dir/home" \
            PATH="$cage_dir/tools/bin:$PATH" \
        "$@"
}

# Run a shell command string inside the jail.
# Usage: jail_exec <cage_dir> <workspace> <shell_command_string>
jail_exec() {
    local cage_dir="$1"
    local workspace="$2"
    local cmd="$3"

    jail_run "$cage_dir" "$workspace" \
        /bin/bash -c "cd '$workspace' 2>/dev/null; $cmd"
}

# Launch an interactive bash shell inside the jail.
# Usage: jail_shell <cage_dir> <workspace>
jail_shell() {
    local cage_dir="$1"
    local workspace="$2"
    local name
    name="$(basename "$cage_dir")"

    jail_run "$cage_dir" "$workspace" \
        env PS1="(cage:${name}) \w \$ " \
        /bin/bash --norc -c "
            cd '$workspace' 2>/dev/null || true
            echo ''
            echo 'Cage: $name (jailed)'
            echo 'Workspace: $workspace'
            echo 'Write access: $cage_dir, $workspace, /tmp'
            echo ''
            echo 'Type \"exit\" to leave.'
            echo ''
            exec /bin/bash --norc
        "
}
