#!/usr/bin/env python3
"""Test if STUN binding requests are blocked (amplification mitigation check)."""
import socket
import struct

host = "YOUR_DOMAIN"
port = 3478

# STUN Binding Request (RFC 5389)
pkt = struct.pack(">HHI", 0x0001, 0x0000, 0x2112A442) + b"\x00" * 12

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
s.sendto(pkt, (host, port))

try:
    data, addr = s.recvfrom(1024)
    print(f"VULNERABLE: got {len(data)} byte STUN response from {addr}")
except socket.timeout:
    print("SECURE: no STUN response (amplification blocked)")
finally:
    s.close()
