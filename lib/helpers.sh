# cage helper functions

# ============================================
# LOGGING
# ============================================

log_info()    { echo -e "${BLUE}i${NC}  $1"; }
log_success() { echo -e "${GREEN}+${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}!${NC}  $1"; }
log_error()   { echo -e "${RED}x${NC}  $1"; }
log_step()    { echo -e "${CYAN}>${NC}  $1"; }

# ============================================
# PORT ALLOCATION
# ============================================

cage_alloc_port() {
    local base_port="$1"
    local port="$base_port"

    while lsof -i :"$port" &>/dev/null || cage_port_in_use "$port"; do
        port=$((port + 1))
        if [[ $port -gt $((base_port + 100)) ]]; then
            log_error "Could not find free port near $base_port"
            exit 1
        fi
    done

    echo "$port"
}

cage_port_in_use() {
    local port="$1"
    if [[ -d "$CAGE_SANDBOX_DIR" ]]; then
        grep -r "PORT=$port$" "$CAGE_SANDBOX_DIR"/*/".env" 2>/dev/null | grep -q .
    else
        return 1
    fi
}

# ============================================
# SETUP
# ============================================

cage_setup() {
    log_info "Setting up micolash (cage)"

    # Create state directory
    mkdir -p "$CAGE_STATE_DIR"

    # Symlink cage to /usr/local/bin if not already there
    local target="/usr/local/bin/cage"
    local source="$CAGE_DIR/cage"

    if [[ -L "$target" ]]; then
        local current
        current="$(readlink "$target")"
        if [[ "$current" == "$source" ]]; then
            log_success "cage already linked: $target -> $source"
        else
            log_warn "cage symlink points elsewhere: $current"
            echo -n "  Update to $source? [y/N] "
            read -r confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                ln -sf "$source" "$target"
                log_success "Updated: $target -> $source"
            fi
        fi
    elif [[ -e "$target" ]]; then
        log_warn "$target exists but is not a symlink. Skipping."
    else
        ln -s "$source" "$target" 2>/dev/null || {
            log_warn "Could not create symlink (try with sudo)"
            echo "  sudo ln -s $source $target"
        }
        if [[ -L "$target" ]]; then
            log_success "Linked: $target -> $source"
        fi
    fi

    log_success "Setup complete"
    echo ""
    echo "  Run 'cage help' to get started."
}
