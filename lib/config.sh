# cage configuration

CAGE_DIR="${CAGE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# State directory — all cages live here
CAGE_STATE_DIR="${CAGE_STATE_DIR:-$HOME/.micolash}"
CAGE_SANDBOX_DIR="$CAGE_STATE_DIR/cages"

# Seatbelt profile
CAGE_SB_PROFILE="$CAGE_DIR/sandbox/jail.sb"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
