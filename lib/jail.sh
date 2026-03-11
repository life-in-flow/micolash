# cage jail — sandbox-exec (Seatbelt) enforcement
#
# Core primitive: run anything inside a macOS Seatbelt jail.
# Writes restricted to cage dir + workspace + repo .git + /tmp.
# Everything else (reads, network, process exec) unrestricted.

# Resolve the parent repo's .git directory from a worktree workspace.
# Git worktrees store refs/objects in the parent repo's .git/,
# so the jail must allow writes there for branches, commits, etc.
_resolve_git_dir() {
    local workspace="$1"
    local git_pointer="$workspace/.git"

    if [[ -f "$git_pointer" ]]; then
        # Worktree: .git is a file containing "gitdir: /path/to/repo/.git/worktrees/<name>"
        local gitdir
        gitdir="$(sed 's/^gitdir: //' "$git_pointer")"
        # Resolve to absolute path
        gitdir="$(cd "$workspace" && cd "$(dirname "$gitdir")" && pwd)/$(basename "$gitdir")"
        # Walk up from .git/worktrees/<name> to .git/
        echo "$(cd "$gitdir/../.." && pwd)"
    elif [[ -d "$git_pointer" ]]; then
        # Regular repo: .git is the directory itself
        echo "$git_pointer"
    else
        # Not a git repo — use a dummy path that won't match anything
        echo "/nonexistent"
    fi
}

# Run a command inside the jail.
# Usage: jail_run <cage_dir> <workspace> <command...>
jail_run() {
    local cage_dir="$1"
    local workspace="$2"
    shift 2

    local git_dir
    git_dir="$(_resolve_git_dir "$workspace")"

    # Inherit git identity from host — check worktree-local config first, then global
    local git_user_name git_user_email
    git_user_name="$(git -C "$workspace" config user.name 2>/dev/null || git config --global user.name 2>/dev/null || echo "cage")"
    git_user_email="$(git -C "$workspace" config user.email 2>/dev/null || git config --global user.email 2>/dev/null || echo "cage@micolash")"

    sandbox-exec -f "$CAGE_SB_PROFILE" \
        -D "SANDBOX_ROOT=$cage_dir" \
        -D "SANDBOX_WORKSPACE=$workspace" \
        -D "GIT_DIR=$git_dir" \
        env \
            CAGE_NAME="$(basename "$cage_dir")" \
            CAGE_ROOT="$cage_dir" \
            CAGE_WORKSPACE="$workspace" \
            HOME="$cage_dir/home" \
            PATH="$cage_dir/tools/bin:$PATH" \
            GIT_AUTHOR_NAME="$git_user_name" \
            GIT_AUTHOR_EMAIL="$git_user_email" \
            GIT_COMMITTER_NAME="$git_user_name" \
            GIT_COMMITTER_EMAIL="$git_user_email" \
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
            echo 'Write access: $cage_dir, $workspace, .git/, /tmp'
            echo ''
            echo 'Type \"exit\" to leave.'
            echo ''
            exec /bin/bash --norc
        "
}
