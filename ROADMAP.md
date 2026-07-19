# Roadmap

Tracking the ongoing downsizing and hardening of the diwansync stack.

## Done

- Replaced nginx-proxy-manager + ddns-updater + authentik with a single ingress
  slot, `004-dyngress` (Caddy reverse proxy + `qmcgaw/ddns-updater`).
- Dropped Compose profiles — every service always starts.
- Caddy TLS is toggled by `CADDY_TLS`: `internal` (self-signed, quiet default) or
  an email address (free Let's Encrypt certificates).
- Caddy certificate/config state lives in Docker-managed volumes (regenerable),
  keeping `storage/` limited to irreplaceable data.

## Planned

- [ ] **Authentication hardening**
  - [ ] Filebrowser: replace `noauth` with password auth and enforce 2FA
    (`auth.methods.password.enforcedOtp: true`; TOTP key + admin password via env).
  - [ ] Immich: 2FA is a per-user setting (Account → Security) with no server-side
    enforcement — documented as a setup step.
- [ ] **Security hardening** — evaluate a Caddy-attached layer for filtering common
  attacks (e.g. CrowdSec, Coraza/OWASP WAF), kept minimal and essential.
- [ ] **Pinned versions → env** — move each service's image tag into its env file so
  versions are maintained per installation, at the user's pace.

## Deferred

- [ ] Rewrite the README around the downsized stack.
- [ ] Drop the Immich config compile step; move SMTP / external-domain settings to
  the Immich admin UI.
