# External Keycloak Integration

This guide covers how to integrate an external Keycloak instance as an SSO
identity provider for your Tuwunel-based Matrix platform. Users will be able
to sign in to Matrix via "Sign in with single sign-on" on their Element (or
other Matrix) client, which redirects them to your Keycloak login page.

## Prerequisites

- This Matrix stack deployed and working (Tuwunel, Caddy, Element, etc.)
- An external Keycloak instance reachable over HTTPS (e.g. `https://auth.example.com`)
- Admin access to both your Keycloak realm and your Matrix server

## Architecture Overview

```
Element Client
    │
    ▼  "Sign in with SSO"
Tuwunel  ──────────►  Keycloak (external)
    │                      │
    │   ◄── callback ──────┘
    │       (authorization code)
    ▼
Matrix session created
```

Tuwunel acts as an OAuth 2.0 / OpenID Connect Relying Party. When a user
clicks "Sign in with single sign-on", Tuwunel redirects them to Keycloak's
authorization endpoint. After the user authenticates, Keycloak redirects back
to Tuwunel's callback URL with an authorization code. Tuwunel exchanges
the code for tokens, reads user claims, and creates or matches a Matrix
account.

### Native OIDC vs legacy SSO — and why Caddy routing matters

Configuring **both** an `[[global.identity_provider]]` block **and**
`[global.well_known.client]` (which this stack always sets, for Element Call)
automatically activates Tuwunel's **next-gen native OIDC server**. Tuwunel then
publishes its own OpenID discovery document at
`/.well-known/openid-configuration` and serves OIDC endpoints under
`/_tuwunel/oidc/*`. This drives the **"Sign In"** button.

The **"Register"** button still uses the older SSO redirect flow, which only
needs `/_matrix/client/v3/login/sso/redirect/*` (already covered by the generic
`/_matrix/*` proxy rule).

> **Critical for reverse proxies (see [Step 3.5](#step-35--caddy-routing-for-native-oidc-required))**:
> `/.well-known/openid-configuration` must be proxied to Tuwunel **before** any
> static `/.well-known/*` file handler. Caddy uses first-match-wins routing, so
> if the static well-known file server matches first, the discovery document
> 404s and native OIDC "Sign In" breaks — while "Register" keeps working, which
> makes this failure easy to misdiagnose. The Caddyfile shipped with this repo
> already handles this; the step below documents it for custom proxies.

Both buttons ultimately delegate upstream to Keycloak using the same
`callback_url`, so **no extra Keycloak redirect URI is required** for native
OIDC beyond the one registered in Step 1.2.

---

## Step 1 — Configure Keycloak

### 1.1 Create a Realm (or use existing)

If you don't already have a realm for your Matrix users, create one in
Keycloak Admin Console → Realm Settings. For example: `matrix`.

### 1.2 Create an OpenID Connect Client

1. Go to **Clients → Create client**
2. Set:
   - **Client type**: OpenID Connect
   - **Client ID**: Choose a unique ID, e.g. `matrix-tuwunel`
     (this becomes `client_id` in Tuwunel config)
3. Click **Next** and enable:
   - **Client authentication**: ON (confidential client)
   - **Standard flow**: ON
4. Click **Next** and set:
   - **Valid redirect URIs**:
     ```
     https://YOUR_DOMAIN/_matrix/client/unstable/login/sso/callback/matrix-tuwunel
     ```
     Replace `YOUR_DOMAIN` with your Matrix domain and `matrix-tuwunel` with
     your chosen Client ID.
   - **Web origins**: `https://YOUR_DOMAIN`
5. Click **Save**

### 1.3 Copy the Client Secret

Go to the **Credentials** tab of your new client and copy the **Client secret**.
You will need this for the Tuwunel configuration.

### 1.4 Note the Issuer URL

Your Keycloak issuer URL follows this pattern:

```
https://auth.example.com/realms/REALM_NAME
```

For example, if your Keycloak is at `auth.example.com` and the realm is
`matrix`, the issuer URL is:

```
https://auth.example.com/realms/matrix
```

Verify it by checking the discovery document:

```bash
curl https://auth.example.com/realms/matrix/.well-known/openid-configuration | jq
```

You should see `authorization_endpoint`, `token_endpoint`, `userinfo_endpoint`,
etc.

### 1.5 Configure User Claims (Optional)

By default, Tuwunel derives the Matrix username from standard OIDC claims
(e.g. `preferred_username`). If you want specific claim behavior:

- Ensure the `preferred_username` claim is included in the ID token
  (it is by default in Keycloak)
- Optionally add a `Client Scope` for custom claims if needed

---

## Step 2 — Provide the Client Secret

How you supply the secret from Step 1.3 depends on your deployment path.

### Ansible path (recommended)

The Ansible template renders the secret **inline** into `tuwunel.toml` from the
`keycloak_client_secret` variable — it does **not** read a
`keycloak_client_secret` file, and the `secrets` role does **not** generate one.
Set the variable in `ansible/inventory/group_vars/matrix_servers.yml`:

```yaml
keycloak_client_secret: "the-secret-from-step-1.3"
```

> **Security**: The shipped default is a plaintext placeholder. Storing a live
> client secret as plaintext in `group_vars` is not ideal — encrypt it with
> [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html):
> ```bash
> ansible-vault encrypt_string 'the-secret-from-step-1.3' --name 'keycloak_client_secret'
> ```
> and paste the resulting block into `group_vars`, then run the playbook with
> `--ask-vault-pass`.

### Manual path (non-Ansible)

If you edit `tuwunel.toml` by hand, you can instead keep the secret in a
file-mounted secret (see Step 3, Option A, and Step 4):

```bash
# On the Matrix server
echo -n 'the-secret-from-step-1.3' | sudo tee /opt/matrix/keycloak_client_secret > /dev/null
sudo chmod 600 /opt/matrix/keycloak_client_secret
```

---

## Step 3 — Configure Tuwunel

### Option A: Manual Configuration (tuwunel.toml)

Add the following identity provider block at the end of your `tuwunel.toml`:

```toml
# ── Keycloak SSO ──────────────────────────────────────────────────
[[global.identity_provider]]
brand = "keycloak"
client_id = "matrix-tuwunel"
client_secret_file = "/etc/tuwunel/keycloak_client_secret"
issuer_url = "https://auth.example.com/realms/matrix"
callback_url = "https://YOUR_DOMAIN/_matrix/client/unstable/login/sso/callback/matrix-tuwunel"
name = "Keycloak"
default = true
trusted = true
registration = true
```

> **Inline secret vs file**: The example above uses `client_secret_file` (paired
> with the file mount in Step 4). Alternatively, use `client_secret = "..."`
> inline. The Ansible template (`tuwunel.toml.j2`) uses the **inline** form,
> sourced from the `keycloak_client_secret` variable (Step 2) — it does not use
> `client_secret_file`.

> **`single_sso` placement**: `single_sso` is a top-level `[global]` key (see
> [Optional: Single SSO Button](#optional-single-sso-button)), **not** a field
> of the `[[global.identity_provider]]` block. Place it under `[global]`.

**Configuration fields explained:**

| Field | Description |
|-------|-------------|
| `brand` | Must be `"keycloak"` so Tuwunel applies Keycloak-specific defaults |
| `client_id` | The Client ID from Keycloak (Step 1.2). Also used in the callback URL path |
| `client_secret_file` | Path to the file containing the client secret (mounted into Docker) |
| `issuer_url` | The Keycloak realm's issuer URL (Step 1.4) |
| `callback_url` | Must match the redirect URI registered in Keycloak exactly |
| `name` | Display name shown on the login page |
| `default` | Set `true` if this is the only/primary SSO provider |
| `trusted` | Set `true` **only** for providers you self-host — allows matching existing Matrix accounts by username |
| `registration` | Set `true` to allow new Matrix accounts to be created on first SSO login |

> **Security note on `trusted`**: When `trusted = true`, Keycloak usernames
> can match and grant access to existing Matrix accounts. Only enable this for
> identity providers you fully control. Never enable it for public providers
> like GitHub or Google.

### Option B: Ansible Configuration

See [Ansible Deployment](#ansible-deployment) below.

---

## Step 3.5 — Caddy routing for native OIDC (required)

As explained in the [Architecture Overview](#native-oidc-vs-legacy-sso--and-why-caddy-routing-matters),
enabling the identity provider activates Tuwunel's native OIDC server, whose
discovery document lives at `/.well-known/openid-configuration`. Your reverse
proxy **must** route that path and `/_tuwunel/oidc/*` to Tuwunel **before** any
static `/.well-known/*` file handler.

**The Caddyfile in this repo already does this** — no action needed if you
deploy the shipped `Caddyfile` (or the Ansible `Caddyfile.j2`). This step is
only relevant if you maintain a custom Caddyfile or a different reverse proxy.

The required Caddy block, which must appear **before** the
`handle_path /.well-known/*` file-server block:

```caddy
# Tuwunel OIDC endpoints — must be matched before the static well-known handler
@oidc path /.well-known/openid-configuration /_tuwunel/oidc/*
handle @oidc {
    reverse_proxy tuwunel:8008 {
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

To confirm the discovery document is reachable (should return JSON, not 404):

```bash
curl -s https://YOUR_DOMAIN/.well-known/openid-configuration | jq .issuer
```

---

## Step 4 — Mount the Secret in Docker (manual/file path only)

> Skip this step on the **Ansible path** — the secret is rendered inline into
> `tuwunel.toml` from the `keycloak_client_secret` variable (Step 2), and the
> shipped `docker-compose.yml` does not mount a `keycloak_client_secret` file.
> This step applies only if you used `client_secret_file` in Step 3, Option A.

Add the secret file as a volume mount for the Tuwunel container. In your
`docker-compose.yml`, add to the `tuwunel` service's `volumes`:

```yaml
volumes:
  - tuwunel_data:/var/lib/tuwunel
  - ./tuwunel.toml:/etc/tuwunel/tuwunel.toml:ro
  - ./turn_shared_secret:/etc/tuwunel/turn_shared_secret:ro
  - ./keycloak_client_secret:/etc/tuwunel/keycloak_client_secret:ro   # ← add this
```

---

## Step 5 — Restart Tuwunel

```bash
cd /opt/matrix
docker compose restart tuwunel
```

Check logs for errors:

```bash
docker compose logs -f tuwunel 2>&1 | head -100
```

Look for lines referencing `identity_provider` or `sso`. If the OIDC
discovery succeeds you should see no errors related to the provider.

---

## Step 6 — Verify the Integration

### 6.1 Check Login Flows

```bash
curl -s https://YOUR_DOMAIN/_matrix/client/v3/login | jq
```

You should see `m.login.sso` in the `flows` array and your Keycloak
provider listed under `identity_providers`:

```json
{
  "flows": [
    { "type": "m.login.password" },
    { "type": "m.login.sso", "identity_providers": [
      { "id": "matrix-tuwunel", "name": "Keycloak", "brand": "keycloak" }
    ]},
    { "type": "m.login.token" }
  ]
}
```

### 6.2 Test Login in Element

1. Open Element Web at `https://YOUR_DOMAIN`
2. Click **Sign In**
3. You should see a **"Sign in with single sign-on"** button (or a
   **"Keycloak"** button if `single_sso` is not enabled)
4. Click it → you are redirected to your Keycloak login page
5. Log in with Keycloak credentials
6. You are redirected back to Element with an active Matrix session

### 6.3 Verify the User

After a successful SSO login, check the user exists:

```bash
# In Element, open Settings → General to see the Matrix User ID
# e.g. @jane:YOUR_DOMAIN
```

---

## Ansible Deployment

If you use the Ansible playbook to manage your Matrix deployment, configure
Keycloak through Ansible variables instead of editing files directly.

### Pre-Deployment Requirement

Unlike TURN/registration/LiveKit secrets, the client secret is **not**
generated by the `secrets` role and is **not** stored as a file on the host.
It is supplied as the `keycloak_client_secret` variable and rendered inline
into `tuwunel.toml` (see [Step 2, Ansible path](#ansible-path-recommended)).
No `keycloak_client_secret` file needs to exist on the target.

### Variables (group_vars/matrix_servers.yml)

Set the Keycloak variables in
`ansible/inventory/group_vars/matrix_servers.yml` (they ship commented/disabled
with `keycloak_enabled: false`):

```yaml
# ── Keycloak SSO (External Identity Provider) ────────────────────
keycloak_enabled: true
keycloak_brand: "keycloak"
keycloak_client_id: "matrix-tuwunel"
keycloak_issuer_url: "https://auth.example.com/realms/matrix"
keycloak_provider_name: "Keycloak"
keycloak_trusted: true
keycloak_registration: true
keycloak_default: true
keycloak_client_secret: "the-secret-from-step-1.3"   # prefer an Ansible Vault value
```

> **Do not commit a live secret in plaintext.** Encrypt `keycloak_client_secret`
> with Ansible Vault (see the [Security note in Step 2](#ansible-path-recommended)).

### Template (tuwunel.toml.j2)

The Ansible template `tuwunel.toml.j2` includes a conditional Keycloak
block that renders only when `keycloak_enabled` is `true`. The
`Caddyfile.j2` template already contains the [native OIDC routing](#step-35--caddy-routing-for-native-oidc-required)
unconditionally, so no Caddy changes are needed.

> **Known template issue**: the shipped `tuwunel.toml.j2` currently emits
> `single_sso = true` **inside** the `[[global.identity_provider]]` block.
> `single_sso` is a `[global]`-scope key, so it should live under `[global]`
> instead. Track/fix this if single-button behavior doesn't take effect.

### Deploy

```bash
cd ansible
ansible-playbook site.yml
```

---

## Optional: SSO-Only Login (Disable Passwords)

To force all users to sign in via Keycloak (disabling password login),
add this to `tuwunel.toml` (or the Ansible template):

```toml
login_with_password = false
```

> **Warning**: Ensure SSO is fully working before disabling password login.
> Keep `emergency_password` configured so you can always recover access via
> the server bot account.

---

## Optional: Single SSO Button

If Keycloak is your only identity provider and you want a cleaner login
page with a single "Sign in with single sign-on" button instead of listing
providers:

```toml
single_sso = true
```

---

## Coexistence with Existing Users

When integrating Keycloak into a server that already has password-registered
users:

1. **Existing password users** continue to work — `login_with_password`
   defaults to `true`, so both login methods are available side by side.

2. **Linking existing accounts via SSO**: If `trusted = true` and the
   Keycloak `preferred_username` matches an existing Matrix localpart,
   the SSO login will grant access to that existing account. This is
   the intended way to associate existing users with Keycloak.

3. **Staged rollout**: Start with both methods enabled, have users test
   SSO login, then optionally disable password login later with
   `login_with_password = false`.

4. **Admin association**: For targeted linking without `trusted = true`,
   use the admin command:
   ```
   !admin query oauth associate @user:YOUR_DOMAIN <provider_client_id>
   ```

---

## Troubleshooting

### SSO button does not appear in Element

- Verify the `/_matrix/client/v3/login` response contains `m.login.sso`
  (see Step 6.1)
- Check Tuwunel logs for identity provider discovery errors:
  ```bash
  docker compose logs tuwunel 2>&1 | grep -i 'identity_provider\|sso\|oidc\|oauth'
  ```

### Redirect URI mismatch

- The `callback_url` in `tuwunel.toml` must **exactly** match the
  "Valid redirect URIs" in Keycloak
- Format: `https://YOUR_DOMAIN/_matrix/client/unstable/login/sso/callback/<client_id>`
- Common mistakes: trailing slash, wrong protocol, wrong client_id

### "issuer mismatch" or discovery failure

- Verify `issuer_url` matches what Keycloak reports:
  ```bash
  curl -s https://auth.example.com/realms/matrix/.well-known/openid-configuration | jq .issuer
  ```
- The value must match **exactly** (no trailing slash difference)
- Ensure your Keycloak is reachable from the Tuwunel container (DNS
  resolution, no firewall blocking)

### User created with random/garbled username

- Keycloak's `preferred_username` claim may be missing or empty
- Check the ID token claims in Keycloak → Client Scopes → Evaluate
- Consider setting `userid_claims = ["preferred_username"]` explicitly
  in the identity provider config

### SSO login works but user cannot join rooms / federation broken

- SSO integration does not affect federation — check federation
  independently
- Verify the user's Matrix ID is well-formed (no illegal characters)

### Cannot log in after disabling password login

- Use the `emergency_password` to access the admin bot account:
  ```toml
  emergency_password = "some-secure-emergency-password"
  ```
- Restart Tuwunel, then log in to the `@conduit` (server bot) account
  with that password to re-enable password login or fix the SSO config

---

## Rollback

To disable Keycloak SSO and return to password-only login:

1. Remove or comment out the `[[global.identity_provider]]` block from
   `tuwunel.toml`
2. Ensure `login_with_password = true` (or remove the line, as it
   defaults to true)
3. Restart Tuwunel:
   ```bash
   docker compose restart tuwunel
   ```
4. Verify:
   ```bash
   curl -s https://YOUR_DOMAIN/_matrix/client/v3/login | jq
   ```
   The response should no longer contain `m.login.sso`.

Existing users who registered via SSO can still log in if you set a
password for them via the admin API, or they can use a login token from
an existing session.

---

## Reference: All Identity Provider Options

These are the available fields for `[[global.identity_provider]]` in
`tuwunel.toml`. Most deployments only need the fields shown in Step 3.

| Option | Default | Description |
|--------|---------|-------------|
| `brand` | — | Provider brand: `"keycloak"`, `"github"`, `"google"`, etc. |
| `client_id` | — | OAuth Client ID (required, also serves as provider ID) |
| `client_secret` | — | OAuth Client Secret (inline, prefer `client_secret_file`) |
| `client_secret_file` | — | Path to file containing the client secret |
| `issuer_url` | — | OIDC Issuer URL (required for self-hosted providers) |
| `callback_url` | — | Redirect URI registered with the provider |
| `name` | brand | Display name on the login page |
| `default` | `false` | Use as default provider for SSO redirect |
| `trusted` | `false` | Allow matching existing Matrix users by username |
| `registration` | `true` | Allow new Matrix account creation from this provider |
| `icon` | — | MXC URL for a provider icon |
| `scope` | `[]` | Restrict OAuth scopes |
| `userid_claims` | `[]` | Claims used to derive Matrix username |
| `unique_id_fallbacks` | `true` | Generate random username if claims conflict |
| `discovery` | `true` | Use OIDC discovery (`.well-known/openid-configuration`) |
| `base_path` | `""` | Extra path after issuer_url for discovery |
| `authorization_url` | — | Override authorization endpoint |
| `token_url` | — | Override token endpoint |
| `userinfo_url` | — | Override userinfo endpoint |
| `revocation_url` | — | Override revocation endpoint |
| `introspection_url` | — | Override introspection endpoint |
| `discovery_url` | — | Override discovery document URL |
| `grant_session_duration` | `300` | Authorization session timeout (seconds) |
| `check_cookie` | `true` | Validate redirect cookie (security feature) |

Global SSO options in `[global]`:

| Option | Default | Description |
|--------|---------|-------------|
| `single_sso` | `false` | Show a single SSO button instead of listing providers |
| `sso_custom_providers_page` | `false` | Use a custom providers page via reverse proxy |
| `login_with_password` | `true` | Enable/disable password login |
| `login_via_token` | `true` | Enable login token flow (required for SSO) |
