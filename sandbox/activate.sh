#!/bin/bash
# Micolash Cage — venv-style activation script
#
# Source this to set up environment variables for the cage.
# For actual jail enforcement, use 'cage enter' or 'cage shell'.
#
# Usage: source activate.sh

SANDBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_NAME="$(basename "$SANDBOX_ROOT")"

if [[ ! -f "$SANDBOX_ROOT/.env" ]]; then
    echo "Error: Cage not initialized. Run 'cage create' first." >&2
    return 1 2>/dev/null || exit 1
fi

source "$SANDBOX_ROOT/.env"

if [[ ! -d "$SANDBOX_WORKSPACE" ]]; then
    echo "Error: Workspace not found: $SANDBOX_WORKSPACE" >&2
    return 1 2>/dev/null || exit 1
fi

# Save originals
export _CAGE_OLD_HOME="${HOME}"
export _CAGE_OLD_PS1="${PS1:-}"
export _CAGE_OLD_PATH="${PATH}"

# Set cage environment
export CAGE_NAME="$SANDBOX_NAME"
export CAGE_ROOT="$SANDBOX_ROOT"
export CAGE_WORKSPACE="$SANDBOX_WORKSPACE"
export HOME="$SANDBOX_ROOT/home"
export PATH="$SANDBOX_ROOT/tools/bin:$PATH"

# Infrastructure
export PGHOST="${SANDBOX_PG_HOST:-localhost}"
export PGPORT="${SANDBOX_PG_PORT:-5432}"
export PGUSER="sandbox"
export PGPASSWORD="sandbox"
export PGDATABASE="flow"
export DATABASE_URL="postgresql://sandbox:sandbox@${PGHOST}:${PGPORT}/flow"
export NATS_URL="nats://localhost:${SANDBOX_NATS_PORT:-4222}"
export REDIS_URL="redis://localhost:${SANDBOX_REDIS_PORT:-6379}"

export PS1="(cage:${SANDBOX_NAME}) ${_CAGE_OLD_PS1}"

deactivate() {
    export HOME="$_CAGE_OLD_HOME"
    export PS1="$_CAGE_OLD_PS1"
    export PATH="$_CAGE_OLD_PATH"
    unset CAGE_NAME CAGE_ROOT CAGE_WORKSPACE
    unset PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE DATABASE_URL
    unset NATS_URL REDIS_URL
    unset _CAGE_OLD_HOME _CAGE_OLD_PS1 _CAGE_OLD_PATH
    unset -f deactivate
    echo "Left cage: $SANDBOX_NAME"
}

echo "Activated cage: $SANDBOX_NAME"
echo "  Workspace: $SANDBOX_WORKSPACE"
echo "  Type 'deactivate' to leave."

cd "$SANDBOX_WORKSPACE"
