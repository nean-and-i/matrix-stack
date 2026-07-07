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
- [x] External Keycloak SSO — `[[global.identity_provider]]` block (tuwunel + Ansible), gated by `keycloak_enabled`
- [x] Native OIDC auto-activation — Tuwunel next-gen OIDC server (both `identity_provider` + `well_known.client` set)
- [x] Caddy native-OIDC routing — proxy `/.well-known/openid-configuration` + `/_tuwunel/oidc/*` to Tuwunel before the static well-known file server (first-match-wins)
- [x] Refactored `secrets` role into idempotent stat/generate/write/slurp steps
- [x] Suppressed 💕 new-user display-name suffix (`new_user_displayname_suffix = ""`)
- [x] Dropped coturn IPv6 `external-ip` — deployment defaults are now IPv4-only (IPv6 optional)
- [x] element-config.json: identity server → matrix.org, removed stale scalar-staging widget URL
- [x] Documentation — added `docs/keycloak-integration.md`; reconciled README + Keycloak doc with actual code (secret mechanism, native OIDC, IPv6, file tree)

## Open

### Security
- [ ] Rate limiting on Matrix API endpoints (Caddy `rate_limit` directive)
- [ ] Ansible Vault for secrets instead of plaintext files — now also covers `keycloak_client_secret`, currently plaintext in `group_vars/matrix_servers.yml`
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
- [ ] LDAP authentication backend (external SSO now covered by Keycloak/OIDC)
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

### Config Hygiene / Known Issues
- [ ] `single_sso = true` is emitted inside the `[[global.identity_provider]]` block in `tuwunel.toml.j2` (and the commented example in root `tuwunel.toml`); it is a `[global]`-scope key and should be moved there
- [ ] Remove dead `secret_files` dict from `roles/secrets/defaults/main.yml` — unused after the stat/generate/write/slurp refactor
- [ ] Fix `keycloak_client_secret` placeholder typo (`KEAYCLOAK-CLIENT-SECRET`) in `group_vars/matrix_servers.yml`
- [ ] Reconcile identity server across files — root `element-config.json` uses `matrix.org` while `wellknown/matrix/client` and the `element_identity_server` default use `vector.im`
- [ ] Keep root/manual configs in sync with Ansible `.j2` templates (drift risk between hand-edited root files and templates)

### Known Limitations
- **Single-server only** — no distributed deployments yet
- **RocksDB** — limited to single machine, not horizontally scalable
- **No built-in monitoring** — requires external tools (Prometheus, etc.)
- **Backup** — manual process only (created by `update.sh`)
- **Rate limiting** — not yet implemented in Caddy
- **IPv6** — disabled by default (coturn `external-ip` dropped, `matrix_server_ipv6` commented out); requires manual re-enable across configs
