#!/bin/bash

################################################################################
# Matrix Homeserver Update Script
# Safely updates configuration while preserving secrets and user data
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MATRIX_DIR="/opt/matrix"
BACKUP_DIR="$MATRIX_DIR/backups/$(date +%Y%m%d_%H%M%S)"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

################################################################################
# Backup existing configuration and secrets
################################################################################

backup_current_state() {
    log_info "Creating backup in $BACKUP_DIR..."

    mkdir -p "$BACKUP_DIR"

    # Backup configuration files
    for file in tuwunel.toml coturn.conf Caddyfile docker-compose.yml element-config.json livekit.yaml; do
        if [[ -f "$MATRIX_DIR/$file" ]]; then
            cp "$MATRIX_DIR/$file" "$BACKUP_DIR/"
            log_info "✓ Backed up $file"
        fi
    done

    # Backup secrets
    for file in turn_shared_secret registration_token livekit_api_key livekit_api_secret; do
        if [[ -f "$MATRIX_DIR/$file" ]]; then
            cp "$MATRIX_DIR/$file" "$BACKUP_DIR/"
            chmod 600 "$BACKUP_DIR/$file"
            log_info "✓ Backed up $file"
        fi
    done

    # Backup well-known files
    if [[ -d "$MATRIX_DIR/wellknown" ]]; then
        cp -r "$MATRIX_DIR/wellknown" "$BACKUP_DIR/"
        log_info "✓ Backed up wellknown directory"
    fi

    log_info "Backup completed: $BACKUP_DIR"
}

################################################################################
# Preserve secrets from current installation
################################################################################

preserve_secrets() {
    log_info "Preserving existing secrets..."

    # Read existing secrets
    if [[ -f "$MATRIX_DIR/turn_shared_secret" ]]; then
        TURN_SECRET=$(cat "$MATRIX_DIR/turn_shared_secret")
        log_info "✓ Preserved TURN secret"
    else
        log_warn "TURN secret not found, will generate new one"
        TURN_SECRET=$(openssl rand -hex 32)
        echo "$TURN_SECRET" > "$MATRIX_DIR/turn_shared_secret"
        chmod 600 "$MATRIX_DIR/turn_shared_secret"
        log_info "✓ Generated new TURN secret"
    fi

    if [[ -f "$MATRIX_DIR/registration_token" ]]; then
        REGISTRATION_TOKEN=$(cat "$MATRIX_DIR/registration_token")
        log_info "✓ Preserved registration token"
    else
        log_warn "Registration token not found, will generate new one"
        REGISTRATION_TOKEN=$(openssl rand -hex 32)
        echo "$REGISTRATION_TOKEN" > "$MATRIX_DIR/registration_token"
        chmod 600 "$MATRIX_DIR/registration_token"
        log_info "✓ Generated new registration token"
    fi

    # LiveKit credentials
    if [[ -f "$MATRIX_DIR/livekit_api_key" ]]; then
        LIVEKIT_KEY=$(cat "$MATRIX_DIR/livekit_api_key")
        log_info "✓ Preserved LiveKit API key"
    else
        log_warn "LiveKit API key not found, will generate new one"
        LIVEKIT_KEY="API$(openssl rand -hex 6)"
        echo "$LIVEKIT_KEY" > "$MATRIX_DIR/livekit_api_key"
        chmod 600 "$MATRIX_DIR/livekit_api_key"
        log_info "✓ Generated new LiveKit API key"
    fi

    if [[ -f "$MATRIX_DIR/livekit_api_secret" ]]; then
        LIVEKIT_SECRET=$(cat "$MATRIX_DIR/livekit_api_secret")
        log_info "✓ Preserved LiveKit API secret"
    else
        log_warn "LiveKit API secret not found, will generate new one"
        LIVEKIT_SECRET=$(openssl rand -hex 32)
        echo "$LIVEKIT_SECRET" > "$MATRIX_DIR/livekit_api_secret"
        chmod 600 "$MATRIX_DIR/livekit_api_secret"
        log_info "✓ Generated new LiveKit API secret"
    fi
}

################################################################################
# Update configuration files with secrets
################################################################################

update_configurations() {
    log_info "Updating configuration files with preserved secrets..."

    # Update coturn.conf
    if [[ -f "$MATRIX_DIR/coturn.conf" ]]; then
        if grep -q "PLACEHOLDER_TURN_SECRET" "$MATRIX_DIR/coturn.conf"; then
            sed -i.tmp "s|PLACEHOLDER_TURN_SECRET|${TURN_SECRET}|g" "$MATRIX_DIR/coturn.conf"
            rm -f "$MATRIX_DIR/coturn.conf.tmp"
            log_info "✓ Updated coturn.conf with TURN secret"
        else
            log_info "✓ coturn.conf already has TURN secret"
        fi
    fi

    # Update tuwunel.toml
    if [[ -f "$MATRIX_DIR/tuwunel.toml" ]]; then
        if grep -q "PLACEHOLDER_REGISTRATION_TOKEN" "$MATRIX_DIR/tuwunel.toml"; then
            sed -i.tmp "s|PLACEHOLDER_REGISTRATION_TOKEN|${REGISTRATION_TOKEN}|g" "$MATRIX_DIR/tuwunel.toml"
            rm -f "$MATRIX_DIR/tuwunel.toml.tmp"
            log_info "✓ Updated tuwunel.toml with registration token"
        else
            log_info "✓ tuwunel.toml already has registration token"
        fi

        # Verify registration_token line exists
        if ! grep -q "^registration_token" "$MATRIX_DIR/tuwunel.toml"; then
            log_warn "registration_token line missing, adding it back"
            sed -i.tmp "/^allow_registration = true/a\\
registration_token = \"${REGISTRATION_TOKEN}\"" "$MATRIX_DIR/tuwunel.toml"
            rm -f "$MATRIX_DIR/tuwunel.toml.tmp"
            log_info "✓ Added registration_token line"
        fi
    fi

    # Update livekit.yaml
    if [[ -f "$MATRIX_DIR/livekit.yaml" ]]; then
        if grep -q "PLACEHOLDER_LIVEKIT_KEY" "$MATRIX_DIR/livekit.yaml"; then
            sed -i.tmp "s|PLACEHOLDER_LIVEKIT_KEY|${LIVEKIT_KEY}|g" "$MATRIX_DIR/livekit.yaml"
            sed -i.tmp "s|PLACEHOLDER_LIVEKIT_SECRET|${LIVEKIT_SECRET}|g" "$MATRIX_DIR/livekit.yaml"
            rm -f "$MATRIX_DIR/livekit.yaml.tmp"
            log_info "✓ Updated livekit.yaml with LiveKit credentials"
        else
            log_info "✓ livekit.yaml already has LiveKit credentials"
        fi
    fi

    # Update docker-compose.yml (lk-jwt-service env vars)
    if [[ -f "$MATRIX_DIR/docker-compose.yml" ]]; then
        if grep -q "PLACEHOLDER_LIVEKIT_KEY" "$MATRIX_DIR/docker-compose.yml"; then
            sed -i.tmp "s|PLACEHOLDER_LIVEKIT_KEY|${LIVEKIT_KEY}|g" "$MATRIX_DIR/docker-compose.yml"
            sed -i.tmp "s|PLACEHOLDER_LIVEKIT_SECRET|${LIVEKIT_SECRET}|g" "$MATRIX_DIR/docker-compose.yml"
            rm -f "$MATRIX_DIR/docker-compose.yml.tmp"
            log_info "✓ Updated docker-compose.yml with LiveKit credentials"
        else
            log_info "✓ docker-compose.yml already has LiveKit credentials"
        fi
    fi
}

################################################################################
# Validate configuration
################################################################################

validate_config() {
    log_info "Validating configuration..."

    local errors=0

    # Check for placeholders
    if grep -r "PLACEHOLDER" "$MATRIX_DIR"/*.conf "$MATRIX_DIR"/*.toml 2>/dev/null; then
        log_error "Found PLACEHOLDER values in configuration files"
        ((errors++))
    fi

    # Check docker-compose.yml syntax
    if ! docker compose -f "$MATRIX_DIR/docker-compose.yml" config > /dev/null 2>&1; then
        log_error "docker-compose.yml has syntax errors"
        ((errors++))
    else
        log_info "✓ docker-compose.yml is valid"
    fi

    # Check secrets exist
    if [[ ! -f "$MATRIX_DIR/turn_shared_secret" ]]; then
        log_error "turn_shared_secret file missing"
        ((errors++))
    fi

    if [[ ! -f "$MATRIX_DIR/registration_token" ]]; then
        log_error "registration_token file missing"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Configuration validation failed with $errors errors"
        return 1
    fi

    log_info "✓ Configuration validation passed"
    return 0
}

################################################################################
# Deploy updated configuration
################################################################################

deploy_update() {
    log_info "Deploying updated configuration..."

    cd "$MATRIX_DIR"

    # Pull latest images
    log_info "Pulling latest Docker images..."
    docker compose pull

    # Restart services with new configuration
    log_info "Restarting services..."
    docker compose down

    # Give services time to stop cleanly
    sleep 5

    docker compose up -d

    log_info "✓ Services restarted"

    # Wait for services to start
    log_info "Waiting for services to initialize (30 seconds)..."
    sleep 30
}

################################################################################
# Health checks
################################################################################

run_health_checks() {
    log_info "Running health checks..."

    cd "$MATRIX_DIR"

    # Check container status
    log_info "Container status:"
    docker compose ps

    # Test Matrix API (internal)
    if docker compose exec -T caddy curl -f -s http://tuwunel:8008/_matrix/client/versions > /dev/null 2>&1; then
        log_info "✓ Matrix Client API responding (internal)"
    else
        log_warn "⚠ Matrix Client API not responding (internal)"
    fi

    # Check TURN server
    if docker compose logs coturn 2>&1 | grep -q "listener opened"; then
        log_info "✓ Coturn TURN server is running"
    else
        log_warn "⚠ Coturn may have issues"
    fi

    # Check LiveKit SFU
    if docker compose logs livekit 2>&1 | grep -q "started"; then
        log_info "✓ LiveKit SFU is running"
    else
        log_warn "⚠ LiveKit SFU may have issues"
    fi

    # Show recent logs
    log_info "Recent service logs:"
    docker compose logs --tail=10 tuwunel
    docker compose logs --tail=10 coturn
    docker compose logs --tail=10 livekit
    docker compose logs --tail=10 livekit-jwt
}

################################################################################
# Display summary
################################################################################

show_summary() {
    log_info "================================================"
    log_info "Update Complete!"
    log_info "================================================"
    log_info ""
    log_info "Backup location: $BACKUP_DIR"
    log_info ""
    log_info "Preserved secrets:"
    log_info "  - TURN secret: $MATRIX_DIR/turn_shared_secret"
    log_info "  - Registration token: $MATRIX_DIR/registration_token"
    log_info "  - LiveKit API key: $MATRIX_DIR/livekit_api_key"
    log_info "  - LiveKit API secret: $MATRIX_DIR/livekit_api_secret"
    log_info ""
    log_info "Your registration token is:"
    log_info "  $REGISTRATION_TOKEN"
    log_info ""
    log_info "User data preserved in volume: tuwunel_data"
    log_info ""
    log_info "To view logs:"
    log_info "  cd $MATRIX_DIR && docker compose logs -f"
    log_info ""
    log_info "To rollback (if needed):"
    log_info "  cd $MATRIX_DIR"
    log_info "  docker compose down"
    log_info "  cp $BACKUP_DIR/* ."
    log_info "  docker compose up -d"
    log_info "================================================"
}

################################################################################
# Main execution
################################################################################

main() {
    log_info "Starting Matrix Homeserver Update..."
    log_info "Working directory: $MATRIX_DIR"

    check_root
    backup_current_state
    preserve_secrets
    update_configurations

    if ! validate_config; then
        log_error "Configuration validation failed. Aborting update."
        log_info "Your original configuration is backed up at: $BACKUP_DIR"
        exit 1
    fi

    deploy_update
    run_health_checks
    show_summary

    log_info "Update completed successfully!"
}

# Run main function
main
