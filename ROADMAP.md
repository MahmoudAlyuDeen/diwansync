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

- [ ] **Authentication** — a single Authelia instance in the ingress slot, used two ways:
  - [ ] Forward-auth for Filebrowser and Syncthing: they stay unauthenticated
    internally; Authelia gates remote access while local networks bypass it.
  - [ ] OIDC for Immich: login flows through Authelia (mobile-app compatible) with
    2FA enforced there; Immich's own per-user 2FA is disabled as redundant.
  - [ ] Resting state: setup generates Authelia's secrets and seeds an admin user so
    it boots before configuration; the default policy requires 2FA from outside and
    bypasses local networks.
- [ ] **Bypass `/api` and `/share` paths** for both core services so mobile apps,
  API clients, and share links keep working, relying on each app's native auth.
- [ ] **User-management script** — add / list / remove Authelia users with secure
  (argon2) password hashing.
- [ ] **Security hardening** — evaluate a Caddy-attached layer for filtering common
  attacks (e.g. CrowdSec, Coraza/OWASP WAF), kept minimal and essential.
- [ ] **Pinned versions → env** — move each service's image tag into its env file so
  versions are maintained per installation, at the user's pace.
- [ ] **LAN access by name** — an optional TLS-less Caddy site (e.g. `*.localhost`
  or a configurable `LAN_DOMAIN`) so services are reachable by name without a public
  domain or certificates, instead of `ip:port`. Caveat: `*.localhost` only resolves
  on the host itself; reaching names from other LAN devices still needs client-side
  resolution (mDNS/`.local`, a local DNS entry, or hosts-file entries), which Caddy
  can't provide alone. Explore a parallel caddy LAN only setup for all sevices for an offline mode + local access even when online.

## Deferred

- [ ] Rewrite the README around the downsized stack.

- [ ] **Remove the Immich OAuth block** — orthogonal to how the config is built.
  Auth is covered by Immich-native password + TOTP 2FA, so the OAuth/SSO block can be
  dropped from the config with no loss beyond OAuth SSO (which the downsize intends).
  Ties into the Authentication-hardening item above.

- [ ] **Immich config — drop the compile step (static literal seed).**
  *Exploratory; mutually exclusive with the automate option below.*
  Immich does **not** expand `${}` inside its config file (the `envsubst` compile step
  exists only to inject values beforehand), so ship a static
  `storage.template/volumes/002-immich/instance-config.yml` with safe literal defaults
  (`externalDomain: ''`, SMTP disabled), placed by the normal template copy. SMTP is set
  by editing that YAML directly (settings in a mounted config file are read-only in the
  Immich UI — edit the file, or leave SMTP out and use the UI).
  *Why:* fewest moving parts, best fit for a downsizing stack; removes `envsubst`,
  `compile-immich-config.sh`, and the `cp` block in `generate_secrets.sh` (→ purely
  secrets). *Cost:* gives up `.env`-driven config; values live in YAML, not env.

- [ ] **Immich config — automate the compile via a Compose init container.**
  *Exploratory; mutually exclusive with drop-compile above.*
  Keep the `${}` template but run `envsubst` as a one-shot service on every `up`
  (`depends_on: { condition: service_completed_successfully }`), writing the result to a
  Docker-managed volume immich mounts at `/config`. Scope substitution to named vars
  (`envsubst '$CONFIG_EXTERNAL_DOMAIN $SMTP_PASSWORD'`).
  *Why:* keeps `.env` as the single control surface (SMTP/domain env-driven) while
  removing the *manual* compile; the regenerable-output-in-a-volume mirrors how Caddy
  state is already handled. Also drops the `cp` block from `generate_secrets.sh`.
  *Cost:* one extra init container — against the downsize grain.
  Explore having a fully committed config that's not init/setup time copied to instance config, with needed parameters injected.
