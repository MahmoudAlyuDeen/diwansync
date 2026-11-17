# DiwanSync - Private Cloud Blueprint

<img width="800" src="images/diwan.jpg">

*Diwān - دِيوَان is a central official registry with a collection of written records.*

# Getting Started

**First time:**
1. Read this readme, really.
2. Check out or download this repo on a machine with docker.
3. Run [`setup.sh`](setup.sh)
4. Select a `storage` path for your data.
5. Create a user (only needed for remote access, can be done later).
6. Run `docker compose up -d` on the repo folder.

**Redeployment or restore from backup:**
1. Check out or download this repo on a machine with docker.
2. Run [`setup.sh`](setup.sh) and pick the *existing folder* and select your `storage` path.
3. Run `docker compose up -d` on the repo folder.

All scripts are idempotent; re-run any of them at any time.

# Accessing services locally

Direct host ports work on the same machine:
- [localhost:8001](http://localhost:8001): [Filebrowser Quantum](https://github.com/gtsteffaniak/filebrowser).
- [localhost:8002](http://localhost:8002): [Immich](https://github.com/immich-app/immich)
- [localhost:8003](http://localhost:8003): [Syncthing](https://github.com/syncthing/syncthing)
- [localhost:8004](http://localhost:8004): [ddns-updater](https://github.com/qdm12/ddns-updater)
- [localhost:9004](http://localhost:9004): [Authelia](https://github.com/authelia-dev/authelia)

To access services from other devices, replace `localhost` with the machine's LAN IP, its Tailscale IP (VPN), or your DDNS domain (reverse proxy).

# Remote access

### VPN
VPN is straightforward to setup and works without port forwarding.
- Install Tailscale on both the host machine and the device you want to access from.
- Services are remotely accessible **as long as you're on VPN**.

### Reverse proxy
Reverse proxy is more involved to setup and needs port forwarding and a real email for 2FA. The benefit is accessing services from any phone or browser without needing VPN.

[Caddy](https://github.com/caddyserver/caddy) fronts every service under your domain and issues the certificates; routes live in [`services/004-dyngress/Caddyfile`](services/004-dyngress/Caddyfile)

Don't skip 2FA if you'll have a public DDNS domain pointing to your server. Authelia resists brute force attacks but 2FA is more secure. Biometric-enabled devices can use WebAuthn passkeys as a second factor, and if desired it can be used for a one step login.

- Configure your server and router to assign the same LAN IP to the server and forward port 443 to it.
- Get a DDNS domain from any provider; Dynu has a solid free tier.
- If you skipped user or secret generation during setup, run [scripts/setup_authelia_user.sh](scripts/setup_authelia_user.sh) and [scripts/generate_secrets.sh](scripts/generate_secrets.sh).
- Fill all fields under `storage/env/004-dyngress.env`, replacing `CADDY_TLS=internal` with a valid email for SSL certificates.
- Restart the docker stack from the repo root folder: `docker compose up -d --force-recreate`
- Use `storage/keys/002-immich-mobile.p12` in the immich app, the password is "immich". Tip: use filebrowser from the phone.

# Storage structure

Everything persistent lives in one folder you choose at setup time, the storage root. Backing up is copying that one folder; to move it, run [`setup.sh`](setup.sh) again.

- `media/`: your files and photos, one folder per service:
  - `001-filebrowser/` files.
  - `002-immich/` photos.
- `volumes/`: service state (databases, caches, thumbnails, transcodes)
- `env/`: configuration and installation unique secrets generated during setup, stored in `storage` and never in the repo.
- `keys/`: mTLS pair for the Immich mobile app.

Immich stores photos flat with date-time names like `2026-07-12_19-23-02_photo.jpg`; metadata and GPS live in the files themselves. Search indexes, faces and albums live only in Immich's database, which is disposable if you stop using it: your photos remain a plain folder you can browse anywhere.
