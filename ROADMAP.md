# Roadmap

## Done

- Replaced nginx-proxy-manager + ddns-updater + authentik with a single ingress slot, `004-dyngress` (Caddy reverse proxy + `qmcgaw/ddns-updater`).
- Dropped Compose profiles — every service always starts.
- Caddy TLS toggled by `CADDY_TLS`: `internal` (self-signed) or an email address (Let's Encrypt).

## Planned

### Revisit Caddy state storage location

Caddy certificate/config state currently lives in Docker-managed volumes, keeping `storage/` clean. Re-evaluate after testing — storing in `storage/volumes/004-dyngress/` would make the state portable across hosts and survive volume recreation, but adds potentially replacable config to the user's storage directory. Decision depends on whether regeneration is reliable enough or if persistence matters more.

### Authentication — Authelia + Caddy forward-auth

Single Authelia instance in the ingress slot with Caddy's `forward_auth` middleware:

- **Remote authentication (port 443):** All connections through Caddy require 2FA, passkey primary and TOTP fallback. Enforced for Filebrowser, Syncthing, and Immich web UIs.
- **Out-of-the-box operation:** No external fetching or manual cert provisioning. `CADDY_TLS=internal` serves self-signed certs immediately.

### Immich OIDC & config strategy via Authelia

Immich login flows through Authelia's OIDC provider (mobile-app compatible), with 2FA enforced at the Authelia layer; Immich per-user 2FA disabled as redundant.

**Config injection problem:** Immich doesn't expand `${}` variables in its YAML config, and OAuth/OIDC settings (`issuer`, `clientSecret`, etc.) are instance-specific secrets:

- **Full config to untracked storage:** Move the entire `instance-config.yml` into `storage/volumes/002-immich/`. Template ships a base with safe defaults; setup or runtime writes the secret sections.
- **Secret snippets + concat:** Keep the committed config template with placeholders, store only OAuth/SMTP secrets as separate snippet files in storage, then concatenate on every `docker compose up`.
- **Automate existing compile:** Keep `compile-immich-config.sh` but invoke it automatically via a Compose init container on each `up`. The compiled output lives in a Docker-managed named volume (e.g., `compile-output`) mounted into the Immich server — no file touches the repo working tree or user storage. Template YAML + snippets stay committed; only the final `instance-config.yml` is ephemeral and regenerated on every `docker compose up`.
- **Drop compile step (static literal seed):** Ship a static `instance-config.yml` with safe defaults (`externalDomain: ''`, SMTP disabled). Users edit directly in storage for optional settings. Removes both the compile script and the `cp` block from `generate_secrets.sh`.

If Authelia OIDC isn't chosen, drop the OAuth/SSO block from Immich's config entirely — native password + TOTP 2FA covers auth with no loss beyond SSO convenience.

### Enforce auth on `/api` paths, keep `/share` public

Current forward-auth bypasses both `/api/*` and `/share/*`. Stop bypassing `/api/*` so API calls go through Authelia's 2FA gate. Share links (`/share/*`) remain public by design.

### User-management script

CLI utility to add / list / remove Authelia users with argon2id hashing, reading/writing the users database YAML in storage. Depends on Authelia being implemented first; for single-user homelabs editing the YAML directly may be sufficient.

### Security hardening

Evaluate a Caddy-attached layer for filtering common attacks:

- **CrowdSec:** Bot and brute-force detection via `crowdsecurity/crowdsec-caddy` plugin. Requires a separate CrowdSec agent container.
- **Coraza/OWASP WAF:** Injection/XSS attack blocking via Caddy module. Can be noisy with false positives on APIs like Immich's.
- **Fail2ban:** Simple, well-known rate-limiting and ban mechanism parsing Caddy access logs — lowest integration effort.

For a 1-2 user homelab the threat model is low — services already have their own auth behind Authelia. Likely deferred unless exposed long-term to the internet.

### Auto-update with Watchtower (exploratory)

Evaluate `containrrr/watchtower` for automated image updates. Initial approach: label-based filtering so only stable services (Caddy, ddns-updater) auto-update on a daily schedule, while breaking-change-prone services (Immich, Syncthing) remain manual. This balances convenience with data safety — Immich migrations and Syncthing protocol changes require user review before applying.

### Pinned versions → env

Move each service's image tag into `.env` (`IMMICH_VERSION`, `CADDY_VERSION`, etc.) so versions are maintained per installation at the user's pace. Deferred until the stack grows beyond 4 services or multiple installations need independent version tracking.

### LAN access by name

Optional TLS-less Caddy site (`*.localhost` or configurable `LAN_DOMAIN`) for named service access instead of `ip:port`. Caveat: `*.localhost` only resolves on the host; other LAN devices need mDNS/`.local`, a local DNS entry, or hosts-file entries.

Authelia's `networks` rule already skips auth for trusted subnets, so named access is purely UX — no security benefit over IP-based access behind Authelia.

### Rewrite README around the downsized stack

Update documentation to reflect: Docker Compose architecture, storage template + symlink model, `setup.sh` interactive flow, 4-service list, Authelia authentication plan. Defer until the stack is stable (after Authentication and Immich config strategy are decided).
