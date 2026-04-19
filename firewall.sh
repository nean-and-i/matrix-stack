#!/bin/bash

################################################################################
# Matrix Homeserver — Firewall Rules (UFW)
#
# Applies all required UFW rules for the Matrix stack.
# Safe to re-run — UFW deduplicates identical rules.
#
# Usage:
#   sudo ./firewall.sh          Apply all rules
#   sudo ./firewall.sh status   Show current UFW status
#   sudo ./firewall.sh check    Verify required rules are present
################################################################################

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

################################################################################
# Rule Definitions
################################################################################

apply_rules() {
    log_info "Applying UFW rules for Matrix stack..."

    # ── SSH ────────────────────────────────────────────────────────
    ufw allow 22/tcp comment 'SSH'

    # ── Caddy (reverse proxy) ─────────────────────────────────────
    ufw allow 80/tcp   comment 'HTTP'
    ufw allow 443/tcp  comment 'HTTPS'
    ufw allow 443/udp  comment 'QUIC (HTTP/3)'

    # ── Matrix Federation ─────────────────────────────────────────
    ufw allow 8448/tcp comment 'Matrix Federation'

    # ── Coturn (TURN relay for 1:1 calls) ─────────────────────────
    ufw allow 3478/tcp comment 'TURN TCP'
    ufw allow 3478/udp comment 'TURN UDP'
    ufw allow 5349/tcp comment 'TURNS TCP'
    ufw allow 60001:65535/udp comment 'Coturn relay ports'

    # ── LiveKit SFU (group video calls) ───────────────────────────
    # Port 7880: LiveKit API/WebSocket — only reachable from Docker
    # bridge networks (Caddy → host.docker.internal). Not exposed to
    # the internet.
    ufw allow from 172.16.0.0/12 to any port 7880 proto tcp comment 'LiveKit API from Docker'
    ufw allow 7881/tcp         comment 'LiveKit WebRTC TCP fallback'
    ufw allow 50000:60000/udp  comment 'LiveKit SFU media ports'

    ufw reload
    log_info "All rules applied"
}

################################################################################
# Status / Check
################################################################################

show_status() {
    ufw status verbose
}

check_rules() {
    log_info "Checking required firewall rules..."
    local missing=0
    local status
    status=$(ufw status)

    check_port() {
        local desc="$1"
        local pattern="$2"
        if echo "$status" | grep -qE "$pattern"; then
            log_info "✓ $desc"
        else
            log_error "✗ $desc — MISSING"
            missing=$((missing + 1))
        fi
    }

    check_port "SSH (22/tcp)"                  "22/tcp.*ALLOW"
    check_port "HTTP (80/tcp)"                 "80/tcp.*ALLOW"
    check_port "HTTPS (443/tcp)"               "443/tcp.*ALLOW"
    check_port "QUIC (443/udp)"                "443/udp.*ALLOW"
    check_port "Federation (8448/tcp)"         "8448/tcp.*ALLOW"
    check_port "TURN TCP (3478/tcp)"           "3478/tcp.*ALLOW"
    check_port "TURN UDP (3478/udp)"           "3478/udp.*ALLOW"
    check_port "TURNS TCP (5349/tcp)"          "5349/tcp.*ALLOW"
    check_port "Coturn relay (60001:65535)"    "60001:65535/udp.*ALLOW"
    check_port "LiveKit API (7880 Docker)"     "7880/tcp.*ALLOW.*172\."
    check_port "LiveKit TCP (7881/tcp)"        "7881/tcp.*ALLOW"
    check_port "LiveKit media (50000:60000)"   "50000:60000/udp.*ALLOW"

    if [[ $missing -eq 0 ]]; then
        log_info "All required rules are present"
    else
        log_error "$missing rule(s) missing — run: sudo ./firewall.sh"
    fi
    return $missing
}

################################################################################
# Main
################################################################################

case "${1:-apply}" in
    apply)   apply_rules ;;
    status)  show_status ;;
    check)   check_rules ;;
    *)
        echo "Usage: sudo $0 [apply|status|check]"
        exit 1
        ;;
esac
