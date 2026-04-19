#!/bin/bash

################################################################################
# Matrix Homeserver Setup Script
# For Tuwunel + Caddy + Coturn on Ubuntu 24.04 LTS
#
# IMPORTANT: Configure YOUR_DOMAIN, YOUR_IPV4, YOUR_IPV6, and YOUR_EMAIL below
#            before running this script
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration — EDIT THESE BEFORE RUNNING
MATRIX_DIR="/opt/matrix"
DOMAIN="YOUR_DOMAIN"
SERVER_IP_V4="YOUR_IPV4"
SERVER_IP_V6="YOUR_IPV6"
ADMIN_EMAIL="YOUR_EMAIL"

################################################################################
# Helper Functions
################################################################################

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
# System Preparation
################################################################################

install_dependencies() {
    log_info "Updating system packages..."
    apt-get update

    log_info "Installing required packages..."
    apt-get install -y \
        curl \
        wget \
        jq \
        git \
        ca-certificates \
        gnupg \
        lsb-release \
        openssl \
        ufw
}

install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker is already installed: $(docker --version)"
        return
    fi

    log_info "Installing Docker..."

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up the Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    log_info "Docker installed: $(docker --version)"
}

################################################################################
# Directory and File Setup
################################################################################

create_directories() {
    log_info "Creating directory structure..."

    mkdir -p "$MATRIX_DIR"
    mkdir -p "$MATRIX_DIR/wellknown/matrix"
    mkdir -p "$MATRIX_DIR/logs"

    log_info "Directories created"
}

generate_secrets() {
    log_info "Generating secure secrets..."

    # Generate TURN shared secret (32 bytes = 64 hex chars)
    if [[ ! -f "$MATRIX_DIR/turn_shared_secret" ]]; then
        TURN_SECRET=$(openssl rand -hex 32)
        echo "$TURN_SECRET" > "$MATRIX_DIR/turn_shared_secret"
        chmod 600 "$MATRIX_DIR/turn_shared_secret"
        log_info "Generated new TURN secret"
    else
        TURN_SECRET=$(cat "$MATRIX_DIR/turn_shared_secret")
        log_info "Using existing TURN secret"
    fi

    # Update coturn.conf with the actual TURN secret
    if grep -q "PLACEHOLDER_TURN_SECRET" "$MATRIX_DIR/coturn.conf" 2>/dev/null; then
        # Use | as delimiter to avoid issues with special chars
        sed -i.bak "s|PLACEHOLDER_TURN_SECRET|${TURN_SECRET}|g" "$MATRIX_DIR/coturn.conf"
        rm -f "$MATRIX_DIR/coturn.conf.bak"
        log_info "Updated coturn.conf with TURN secret"

        # Verify the replacement worked
        if grep -q "PLACEHOLDER_TURN_SECRET" "$MATRIX_DIR/coturn.conf" 2>/dev/null; then
            log_error "Failed to replace TURN secret in coturn.conf"
        else
            log_info "✓ TURN secret successfully set in coturn.conf"
        fi
    fi

    # Generate registration token (32 bytes = 64 hex chars)
    if [[ ! -f "$MATRIX_DIR/registration_token" ]]; then
        REGISTRATION_TOKEN=$(openssl rand -hex 32)
        echo "$REGISTRATION_TOKEN" > "$MATRIX_DIR/registration_token"
        chmod 600 "$MATRIX_DIR/registration_token"
        log_info "Generated new registration token"
    else
        REGISTRATION_TOKEN=$(cat "$MATRIX_DIR/registration_token")
        log_info "Using existing registration token"
    fi

    # Update tuwunel.toml with the actual registration token
    if grep -q "PLACEHOLDER_REGISTRATION_TOKEN" "$MATRIX_DIR/tuwunel.toml" 2>/dev/null; then
        # Use | as delimiter to avoid issues with special chars, and escape the replacement
        sed -i.bak "s|PLACEHOLDER_REGISTRATION_TOKEN|${REGISTRATION_TOKEN}|g" "$MATRIX_DIR/tuwunel.toml"
        rm -f "$MATRIX_DIR/tuwunel.toml.bak"
        log_info "Updated tuwunel.toml with registration token"

        # Verify the replacement worked
        if grep -q "PLACEHOLDER_REGISTRATION_TOKEN" "$MATRIX_DIR/tuwunel.toml" 2>/dev/null; then
            log_error "Failed to replace registration token in tuwunel.toml"
        else
            log_info "✓ Registration token successfully set in tuwunel.toml"
        fi
    fi

    # ── LiveKit API credentials ───────────────────────────────────
    # Generate LiveKit API key (short identifier) and secret (64 hex chars)
    if [[ ! -f "$MATRIX_DIR/livekit_api_key" ]]; then
        LIVEKIT_KEY="API$(openssl rand -hex 6)"
        echo "$LIVEKIT_KEY" > "$MATRIX_DIR/livekit_api_key"
        chmod 600 "$MATRIX_DIR/livekit_api_key"
        log_info "Generated new LiveKit API key"
    else
        LIVEKIT_KEY=$(cat "$MATRIX_DIR/livekit_api_key")
        log_info "Using existing LiveKit API key"
    fi

    if [[ ! -f "$MATRIX_DIR/livekit_api_secret" ]]; then
        LIVEKIT_SECRET=$(openssl rand -hex 32)
        echo "$LIVEKIT_SECRET" > "$MATRIX_DIR/livekit_api_secret"
        chmod 600 "$MATRIX_DIR/livekit_api_secret"
        log_info "Generated new LiveKit API secret"
    else
        LIVEKIT_SECRET=$(cat "$MATRIX_DIR/livekit_api_secret")
        log_info "Using existing LiveKit API secret"
    fi

    # Update livekit.yaml with the actual LiveKit credentials
    if grep -q "PLACEHOLDER_LIVEKIT_KEY" "$MATRIX_DIR/livekit.yaml" 2>/dev/null; then
        sed -i.bak "s|PLACEHOLDER_LIVEKIT_KEY|${LIVEKIT_KEY}|g" "$MATRIX_DIR/livekit.yaml"
        sed -i.bak "s|PLACEHOLDER_LIVEKIT_SECRET|${LIVEKIT_SECRET}|g" "$MATRIX_DIR/livekit.yaml"
        rm -f "$MATRIX_DIR/livekit.yaml.bak"
        log_info "✓ LiveKit credentials set in livekit.yaml"
    fi

    # Update docker-compose.yml with LiveKit credentials (for lk-jwt-service)
    if grep -q "PLACEHOLDER_LIVEKIT_KEY" "$MATRIX_DIR/docker-compose.yml" 2>/dev/null; then
        sed -i.bak "s|PLACEHOLDER_LIVEKIT_KEY|${LIVEKIT_KEY}|g" "$MATRIX_DIR/docker-compose.yml"
        sed -i.bak "s|PLACEHOLDER_LIVEKIT_SECRET|${LIVEKIT_SECRET}|g" "$MATRIX_DIR/docker-compose.yml"
        rm -f "$MATRIX_DIR/docker-compose.yml.bak"
        log_info "✓ LiveKit credentials set in docker-compose.yml"
    fi

    log_info "Secrets generated and injected into configuration files"

    # Restrict permissions on config files that now contain secrets
    for f in coturn.conf tuwunel.toml docker-compose.yml livekit.yaml; do
        [[ -f "$MATRIX_DIR/$f" ]] && chmod 640 "$MATRIX_DIR/$f"
    done
    log_info "✓ Config file permissions restricted to 640"
}

configure_firewall() {
    log_info "Configuring firewall (UFW)..."

    # Enable UFW if not already enabled
    ufw --force enable

    # Allow SSH (important!)
    ufw allow 22/tcp

    # Allow HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp  # QUIC

    # Allow Matrix Federation
    ufw allow 8448/tcp

    # Allow TURN/STUN
    ufw allow 3478/tcp
    ufw allow 3478/udp
    ufw allow 5349/tcp
    ufw allow 60001:65535/udp  # Coturn relay ports

    # Allow LiveKit SFU
    ufw allow from 172.16.0.0/12 to any port 7880 proto tcp comment 'LiveKit API from Docker'
    ufw allow 7881/tcp         # LiveKit WebRTC TCP fallback
    ufw allow 50000:60000/udp  # LiveKit SFU media ports

    ufw reload

    log_info "Firewall configured"
}

################################################################################
# Docker Setup
################################################################################

start_services() {
    log_info "Starting Docker services..."

    cd "$MATRIX_DIR"

    # Pull latest images
    docker compose pull

    # Start services
    docker compose up -d

    log_info "Waiting for services to start (30 seconds)..."
    sleep 30

    # Check service status
    docker compose ps
}

################################################################################
# Coturn TLS cert refresh
# Coturn reads certs at startup only. Caddy renews Let's Encrypt certs
# automatically, but coturn needs a restart to pick up new certs.
################################################################################

setup_coturn_cert_cron() {
    log_info "Setting up weekly coturn restart for TLS cert refresh..."

    local cron_job="0 4 * * 0 root cd $MATRIX_DIR && docker compose restart coturn >> /var/log/coturn-restart.log 2>&1"
    local cron_file="/etc/cron.d/coturn-tls-refresh"

    echo "$cron_job" > "$cron_file"
    chmod 644 "$cron_file"

    log_info "✓ Coturn restart cron installed: Sundays at 04:00"
}

################################################################################
# Health Checks
################################################################################

run_health_checks() {
    log_info "Running health checks..."

    # Check if containers are running
    log_info "Checking container status..."
    docker compose ps

    # Wait for services to be fully ready
    log_info "Waiting for services to be fully operational..."
    sleep 10

    # Test Matrix client API
    log_info "Testing Matrix Client API..."
    # Test internally first (container to container)
    if docker compose exec -T caddy curl -f -s http://tuwunel:8008/_matrix/client/versions > /dev/null 2>&1; then
        log_info "✓ Matrix Client API is responding (internal)"
        # Try external HTTPS if available
        if curl -f -s -k https://$DOMAIN/_matrix/client/versions > /dev/null 2>&1; then
            log_info "✓ Matrix Client API is responding (external HTTPS)"
            curl -s -k https://$DOMAIN/_matrix/client/versions | jq 2>/dev/null || true
        else
            log_warn "⚠ External HTTPS not yet configured (normal during initial setup)"
        fi
    else
        log_error "✗ Matrix Client API is not responding"
    fi

    # Test Matrix federation
    log_info "Testing Matrix Federation API..."
    if docker compose exec -T caddy curl -f -s http://tuwunel:8008/_matrix/federation/v1/version > /dev/null 2>&1; then
        log_info "✓ Matrix Federation API is responding (internal)"
        if curl -f -s -k https://$DOMAIN:8448/_matrix/federation/v1/version > /dev/null 2>&1; then
            log_info "✓ Matrix Federation API is responding (external)"
            curl -s -k https://$DOMAIN:8448/_matrix/federation/v1/version | jq 2>/dev/null || true
        else
            log_warn "⚠ External federation not yet configured"
        fi
    else
        log_error "✗ Matrix Federation API is not responding"
    fi

    # Test well-known delegation
    log_info "Testing .well-known delegation..."
    if docker compose exec -T caddy curl -f -s http://localhost/.well-known/matrix/server > /dev/null 2>&1; then
        log_info "✓ Well-known server delegation is working (internal)"
        docker compose exec -T caddy curl -s http://localhost/.well-known/matrix/server | jq 2>/dev/null || true
        if curl -f -s -k https://$DOMAIN/.well-known/matrix/server > /dev/null 2>&1; then
            log_info "✓ Well-known server delegation is working (external)"
        fi
    else
        log_error "✗ Well-known server delegation is not working"
    fi

    if docker compose exec -T caddy curl -f -s http://localhost/.well-known/matrix/client > /dev/null 2>&1; then
        log_info "✓ Well-known client delegation is working (internal)"
        docker compose exec -T caddy curl -s http://localhost/.well-known/matrix/client | jq 2>/dev/null || true
        if curl -f -s -k https://$DOMAIN/.well-known/matrix/client > /dev/null 2>&1; then
            log_info "✓ Well-known client delegation is working (external)"
        fi
    else
        log_error "✗ Well-known client delegation is not working"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "Starting Matrix Homeserver Setup..."
    log_info "Domain: $DOMAIN"
    log_info "Installation directory: $MATRIX_DIR"

    check_root
    install_dependencies
    install_docker
    create_directories
    generate_secrets
    configure_firewall
    start_services
    run_health_checks
    setup_coturn_cert_cron

    log_info "================================================"
    log_info "Matrix Homeserver Setup Complete!"
    log_info "================================================"
    log_info ""
    log_info "Your Matrix homeserver is now running at:"
    log_info "  - Client API: https://$DOMAIN"
    log_info "  - Federation: https://$DOMAIN:8448"
    log_info "  - Element Web: https://$DOMAIN/"
    log_info ""
    log_info "================================"
    log_info "IMPORTANT: Save These Secrets!"
    log_info "================================"
    log_info ""
    log_info "Registration Token (REQUIRED for user registration):"
    log_info "  $REGISTRATION_TOKEN"
    log_info ""
    log_info "TURN Secret (for VoIP/video calls):"
    log_info "  $TURN_SECRET"
    log_info ""
    log_info "LiveKit API Key (for group video calls):"
    log_info "  $LIVEKIT_KEY"
    log_info ""
    log_info "LiveKit API Secret:"
    log_info "  $LIVEKIT_SECRET"
    log_info ""
    log_info "These secrets have been saved to:"
    log_info "  - Registration token: $MATRIX_DIR/registration_token"
    log_info "  - TURN secret: $MATRIX_DIR/turn_shared_secret"
    log_info "  - LiveKit API key: $MATRIX_DIR/livekit_api_key"
    log_info "  - LiveKit API secret: $MATRIX_DIR/livekit_api_secret"
    log_info ""
    log_info "File permissions set to 600 (owner read/write only)"
    log_info "================================"
    log_info ""
    log_info "To view logs:"
    log_info "  cd $MATRIX_DIR && docker compose logs -f"
    log_info ""
    log_info "To stop services:"
    log_info "  cd $MATRIX_DIR && docker compose down"
    log_info ""
    log_info "To restart services:"
    log_info "  cd $MATRIX_DIR && docker compose restart"
    log_info ""
    log_info "Next steps:"
    log_info "  1. SAVE THE REGISTRATION TOKEN ABOVE - You'll need it to register users"
    log_info "  2. Register your first user at https://$DOMAIN using the token"
    log_info "  3. Test federation with other Matrix servers"
    log_info "  4. Configure backup strategy for $MATRIX_DIR"
    log_info "================================================"
}

# Run main function
main
