# cage infrastructure module — docker compose services

cage_infra() {
    local subcmd="${1:-status}"
    shift || true
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        log_error "Cage name is required"
        echo "Usage: cage infra <up|down|restart|status> <name>"
        exit 1
    fi

    case "$subcmd" in
        up)      cage_infra_up "$name" ;;
        down)    cage_infra_down "$name" ;;
        restart)
            cage_infra_down "$name"
            cage_infra_up "$name"
            ;;
        status)  cage_status "$name" ;;
        *)
            log_error "Unknown infra command: $subcmd"
            echo "Usage: cage infra <up|down|restart|status> <name>"
            exit 1
            ;;
    esac
}

cage_infra_up() {
    local name="$1"
    local sandbox_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -f "$sandbox_dir/.env" ]]; then
        log_error "Cage '$name' not initialized"
        exit 1
    fi

    source "$sandbox_dir/.env"

    local project="cage-${name}"

    COMPOSE_PROJECT_NAME="$project" \
    SANDBOX_PG_PORT="${SANDBOX_PG_PORT}" \
    SANDBOX_NATS_PORT="${SANDBOX_NATS_PORT}" \
    SANDBOX_NATS_MONITOR_PORT="${SANDBOX_NATS_MONITOR_PORT}" \
    SANDBOX_REDIS_PORT="${SANDBOX_REDIS_PORT}" \
        docker compose -f "$CAGE_COMPOSE_FILE" up -d

    # Wait for services with healthchecks
    log_step "Waiting for infrastructure to be ready..."
    local retries=0
    while [[ $retries -lt 15 ]]; do
        if COMPOSE_PROJECT_NAME="$project" docker compose -f "$CAGE_COMPOSE_FILE" ps --format json 2>/dev/null \
            | grep -q '"Health":"healthy"'; then
            break
        fi
        sleep 1
        retries=$((retries + 1))
    done

    log_success "Infrastructure started for cage: $name"
}

cage_infra_down() {
    local name="$1"
    local sandbox_dir="$CAGE_SANDBOX_DIR/$name"

    if [[ ! -f "$sandbox_dir/.env" ]]; then
        log_error "Cage '$name' not initialized"
        exit 1
    fi

    source "$sandbox_dir/.env"

    local project="cage-${name}"

    COMPOSE_PROJECT_NAME="$project" \
    SANDBOX_PG_PORT="${SANDBOX_PG_PORT}" \
    SANDBOX_NATS_PORT="${SANDBOX_NATS_PORT}" \
    SANDBOX_NATS_MONITOR_PORT="${SANDBOX_NATS_MONITOR_PORT}" \
    SANDBOX_REDIS_PORT="${SANDBOX_REDIS_PORT}" \
        docker compose -f "$CAGE_COMPOSE_FILE" down -v

    log_success "Infrastructure stopped for cage: $name"
}
