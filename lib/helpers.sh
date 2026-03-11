# cage helpers

log_info()    { echo -e "${BLUE}i${NC}  $1"; }
log_success() { echo -e "${GREEN}+${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}!${NC}  $1"; }
log_error()   { echo -e "${RED}x${NC}  $1"; }
log_step()    { echo -e "${CYAN}>${NC}  $1"; }

cage_setup() {
    log_info "Setting up micolash (cage)"
    mkdir -p "$CAGE_STATE_DIR"

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
        [[ -L "$target" ]] && log_success "Linked: $target -> $source"
    fi

    log_success "Setup complete. Run 'cage help' to get started."
}
