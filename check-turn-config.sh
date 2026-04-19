#!/bin/bash

echo "=== TURN Configuration Diagnostics ==="
echo ""

# Check if coturn is running
echo "1. Coturn container status:"
docker ps | grep coturn || echo "   ❌ Coturn not running"
echo ""

# Check turn_shared_secret file
echo "2. TURN shared secret:"
if [ -f "turn_shared_secret" ]; then
    SECRET=$(cat turn_shared_secret)
    echo "   ✓ File exists, length: ${#SECRET} chars"
    echo "   Secret: $SECRET"
else
    echo "   ❌ turn_shared_secret file not found"
fi
echo ""

# Check if secret is in coturn.conf
echo "3. Secret in coturn.conf:"
if grep -q "PLACEHOLDER_TURN_SECRET" coturn.conf; then
    echo "   ❌ PLACEHOLDER still in coturn.conf - needs replacement!"
else
    grep "static-auth-secret" coturn.conf | head -1
fi
echo ""

# Check if coturn ports are listening
echo "4. Coturn ports:"
ss -ulnp 2>/dev/null | grep 3478 || echo "   Port 3478 UDP status unknown"
ss -tlnp 2>/dev/null | grep 3478 || echo "   Port 3478 TCP status unknown"
echo ""

# Check Matrix TURN endpoint
echo "5. Matrix TURN configuration endpoint:"
curl -s http://localhost:8008/_matrix/client/r0/voip/turnServer 2>&1 | head -20
echo ""

# Check coturn logs for errors
echo "6. Recent coturn log errors:"
docker-compose logs --tail=20 coturn 2>&1 | grep -i "error\|warning\|fail" | head -10 || echo "   No recent errors"
echo ""

# Test if TURN is reachable
echo "7. TURN server reachability (UDP 3478):"
timeout 2 nc -u -z -v localhost 3478 2>&1 || echo "   Cannot verify UDP connectivity"
echo ""

echo "=== Recommendations ==="
echo ""
echo "If video calls work directly (same network), TURN might not be needed."
echo "TURN is only used when direct peer-to-peer connection fails (NAT/firewall)."
echo ""
echo "To force TURN usage for testing:"
echo "  1. Test from different networks (mobile vs wifi)"
echo "  2. Use browser dev tools to check WebRTC stats"
echo "  3. Watch coturn logs during call: docker-compose logs -f coturn"
