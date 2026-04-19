#!/bin/bash

################################################################################
# Quick TURN Server Test Script
# Tests if coturn is properly configured and working
################################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Testing TURN Server Configuration..."
echo ""

# Check if coturn is running
if docker ps | grep -q coturn; then
    echo -e "${GREEN}✓${NC} Coturn container is running"
else
    echo -e "${RED}✗${NC} Coturn container is NOT running"
    exit 1
fi

# Check ports
echo ""
echo "Checking TURN ports..."
if netstat -ulnp 2>/dev/null | grep -q ":3478"; then
    echo -e "${GREEN}✓${NC} UDP Port 3478 (TURN) is listening"
else
    echo -e "${RED}✗${NC} UDP Port 3478 is NOT listening"
fi

if netstat -tlnp 2>/dev/null | grep -q ":3478"; then
    echo -e "${GREEN}✓${NC} TCP Port 3478 (TURN) is listening"
else
    echo -e "${RED}✗${NC} TCP Port 3478 is NOT listening"
fi

# Check coturn logs for errors
echo ""
echo "Checking coturn logs for errors..."
if docker-compose logs coturn 2>&1 | tail -50 | grep -i "error\|warning" | grep -v "pid file\|TLS 1.3\|DTLS 1.2"; then
    echo -e "${YELLOW}⚠${NC} Found warnings/errors in coturn logs (see above)"
else
    echo -e "${GREEN}✓${NC} No critical errors in coturn logs"
fi

# Check external IP configuration
echo ""
echo "Checking external IP configuration..."
if docker-compose logs coturn 2>&1 | grep -q "Relay address to use"; then
    echo -e "${GREEN}✓${NC} Coturn has relay addresses configured"
    docker-compose logs coturn 2>&1 | grep "Relay address to use"
else
    echo -e "${YELLOW}⚠${NC} Could not verify relay addresses"
fi

# Check if TLS is disabled (expected)
echo ""
echo "Checking TLS configuration..."
if docker-compose logs coturn 2>&1 | grep -q "cannot find certificate"; then
    echo -e "${YELLOW}⚠${NC} TLS certificates missing (expected - TLS should be disabled)"
    echo "    Make sure tls-listening-port is commented out in coturn.conf"
else
    echo -e "${GREEN}✓${NC} No TLS certificate warnings"
fi

# Check turn_shared_secret exists
echo ""
echo "Checking TURN shared secret..."
if [[ -f "/opt/matrix/turn_shared_secret" ]]; then
    echo -e "${GREEN}✓${NC} turn_shared_secret file exists"
    SECRET=$(cat /opt/matrix/turn_shared_secret)
    if [[ ${#SECRET} -eq 64 ]]; then
        echo -e "${GREEN}✓${NC} Secret has correct length (64 chars)"
    else
        echo -e "${YELLOW}⚠${NC} Secret length is ${#SECRET} (expected 64)"
    fi
else
    echo -e "${RED}✗${NC} turn_shared_secret file NOT found"
fi

# Test Matrix TURN endpoint
echo ""
echo "Testing Matrix TURN config endpoint..."
if curl -s http://localhost:8008/_matrix/client/r0/voip/turnServer 2>&1 | grep -q "uris"; then
    echo -e "${GREEN}✓${NC} Matrix TURN endpoint is responding"
    echo "TURN configuration from Matrix:"
    curl -s http://localhost:8008/_matrix/client/r0/voip/turnServer 2>&1 | jq '.' 2>/dev/null || curl -s http://localhost:8008/_matrix/client/r0/voip/turnServer
else
    echo -e "${YELLOW}⚠${NC} Could not retrieve TURN config from Matrix"
fi

echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. If you see errors above, fix them first"
echo "2. Restart services: cd /opt/matrix && docker-compose restart coturn tuwunel"
echo "3. Test with online tool: https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/"
echo "4. Add TURN server: turn:YOUR_DOMAIN:3478?transport=udp"
echo "5. Make a test video call in Matrix"
echo ""
echo "To watch TURN activity during a call:"
echo "  docker-compose logs -f coturn"
