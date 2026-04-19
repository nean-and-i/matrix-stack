# Matrix Stack — TODO

## Completed

- [x] STUN amplification fix — added `no-stun` to coturn (Shadowserver CVE)
- [x] Removed STUN URIs from TURN config (tuwunel + Ansible)
- [x] Fixed Caddy well-known routing (`handle_path /.well-known/*`)
- [x] Caddy logging switched to `output stdout` for Docker log collection
- [x] Cache-Control headers on `.well-known` responses
- [x] Fixed tuwunel.toml TOML structure (flat TURN keys under `[global]`)
- [x] Enabled MatrixRTC / Element Call via `[global.well_known]` + `rtc_transports`
- [x] Added `use_exclusively: true` to Element Call config
- [x] Added UFW rule: LiveKit API port 7880 from Docker only (172.16.0.0/12)
- [x] Created `firewall.sh` — dedicated UFW management script
- [x] Fixed relay port range in `setup.sh` (60001-65535 matching coturn.conf)
- [x] Synced all Ansible templates with local configs
- [x] Architecture diagram and README updated
- [x] Docker log rotation configured
- [x] IPv6 support — enabled `external-ip` in coturn, LiveKit auto-discovers via `use_external_ip`
- [x] TLS for Coturn (TURNS) — shared Caddy's Let's Encrypt certs via caddy_data volume
- [x] Added `turns:` URI to TURN config (tuwunel + Ansible)
- [x] Fixed TODO.md inaccurate `node_ip_v6` claim
- [x] Weekly coturn restart cron for TLS cert renewal (setup.sh + Ansible)
- [x] Reduced TURN TTL from 24h to 1h (tuwunel + Ansible)
- [x] Restricted `/_synapse/` admin API to server IPs only (Caddyfile + Ansible)
- [x] Synced coturn Ansible template — `max-bps` and `coturn_verbose` now match local config
- [x] Fixed Ansible SSH key path (was pointing to `.pub` public key)
- [x] Narrowed CORS OPTIONS handler to `/_matrix/*` and `/.well-known/*` only
- [x] Ansible handler: `--force-recreate` instead of `down + up` (reduces downtime)
- [x] Docker log rotation: `json-file` driver, 1m × 3 (5m for tuwunel)
- [x] Synced Ansible docker-compose log sizes to `1m`
- [x] Reverted LiveKit Ansible template `bind_addresses` to `""` (127.0.0.1 doesn't work)
- [x] Added `email mtx@unbox.at` global block to Caddyfile for LE cert expiry warnings
- [x] Added `depends_on: caddy` to lk-jwt-service (needs Caddy for OpenID callback)
- [x] Added `response_header_timeout 300s` to federation transport block
- [x] Federation fallback changed from 200 to 404 (no info leak to scanners)

## Open

### Security
- [ ] Rate limiting on Matrix API endpoints (Caddy `rate_limit` directive)
- [ ] Ansible Vault for secrets instead of plaintext files
- [ ] Automated coturn TLS cert reload (without weekly restart)
- [ ] Brute-force protection on login endpoints

### Operations
- [ ] Monitoring / alerting (Prometheus + Grafana integration)
- [ ] Backup strategy for `tuwunel_data` volume (RocksDB snapshots)
- [ ] Automated database compaction (RocksDB maintenance)
- [ ] Uptime monitoring and alerting

### Features
- [ ] S3 / object storage for media uploads (vs local volume)
- [ ] Email notifications (registration, password reset)
- [ ] LDAP / SSO authentication backend
- [ ] Admin console UI (web-based admin panel)
- [ ] Synapse admin API compatibility layer (if needed for tooling)

### Scaling
- [ ] Multi-server federation redundancy
- [ ] Load balancing across multiple Tuwunel instances
- [ ] Shared database (PostgreSQL) instead of RocksDB

### Development
- [ ] CI pipeline for config validation (GitHub Actions / GitLab CI)
- [ ] Automated security scanning (container, dependencies)
- [ ] Integration tests for Matrix spec compliance
- [ ] Helm charts for Kubernetes deployments

### Known Limitations
- **Single-server only** — no distributed deployments yet
- **RocksDB** — limited to single machine, not horizontally scalable
- **No built-in monitoring** — requires external tools (Prometheus, etc.)
- **Backup** — manual process only (created by `update.sh`)
- **Rate limiting** — not yet implemented in Caddy
