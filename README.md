# DiwanSync - Private Cloud Blueprint

<img width="800" src="images/diwan.jpg">

```
Diwān - دِيوَان is a central official registry with a collection of written records.
```

# Summary

A thin opinionated wrapper of existing open source services. Modular flexible setup, keeping data in plain, browsable, and user controlled, folders instead of hidden Docker volumes.

Runs anywhere Docker does: Linux, macOS, VPS, ...

Default services:

- [Filebrowser Quantum](https://github.com/gtsteffaniak/filebrowser): Simple web-based file manager.
- [Immich](https://github.com/immich-app/immich): Self-hosted photo & video backup, mobile and web apps.

Optional [opt-in](#5-opt-in-features) services:

- [Syncthing](https://github.com/syncthing/syncthing): Continuous device sync.
- [Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager): Reverse proxy & auto certificate generation.
- [Authentik](https://github.com/goauthentik/authentik): Authentication.
- [ddns-updater](https://github.com/qdm12/ddns-updater): Automatically sends the host machine IP to DDNS services.

---

# Getting Started

**First time:**
1. Check out or download this repo.
2. Run [`setup.sh`](setup.sh).

The script walks you through choosing where `storage` lives, seeds it from [`storage.template/`](storage.template/), generates secrets under `storage/env`, and offers to bring the stack up with `docker compose up -d`.

**Redeployment or restore from backup:**
1. Check out or download this repo.
2. Run [`setup.sh`](setup.sh) and pick the *existing folder* option to point `storage` at your backup.

All configs, secrets, media, and databases are already in place; the script offers to bring the stack up.

---

# Architecture Overview

## 1. Media Organization

Core user data, files and photos, lives in a dedicated `media/` directory under the storage root, completely independent of the services that manage them.

```
storage/media/
  001-filebrowser/   files
  002-immich/        photos
```

Files are stored with flat, human-readable date-time naming: `2026-07-12_19-23-02_photo.jpg`. No subfolders, no album structures, no year/month organization on disk. The files themselves carry their own metadata and GPS coordinates. Only Immich's search indexes, facial recognition data, and album structures live in the database and are fully disposable. The database can be wiped with zero effect on the user's actual files. Data can be taken completely offline, moved to another service, browsed in any file manager, or migrated to a different photo platform.

Services are conveniences, not dependencies. You can stop using Immich and your photos are still right there in a folder, organized by date. You can stop using Filebrowser and your files are still right there.

## 2. Storage Architecture

The repo contains only code and templates. All persistent data lives in one folder you choose — the storage root — kept in plain sight rather than scattered across hidden Docker volumes, so nothing about your data is hard to find, move, or back up. It holds three folders:

- `storage/media` — your actual files and photos
- `storage/volumes` — service state the apps can rebuild: databases, caches, generated thumbnails and transcodes
- `storage/env` — configuration and secrets: database passwords, domains and URLs, OAuth credentials, email (SMTP) logins, DDNS tokens, and which services are enabled

A `storage` symlink at the repo root points to this directory, created by [`setup.sh`](setup.sh) and untracked so clones never carry a dangling link. This makes all Docker volume mounts resolvable relative to the repo regardless of where the actual data lives: a NAS mount, a second disk, a different machine, or just a regular folder. The symlink is the single point of configuration.

All persistent files live under one root, making backups trivial; back up the storage path and everything is captured. Each service's non-media data gets its own subdirectory under `volumes/` with no cross-contamination. The `storage.template/volumes/` mirrors this structure with `.gitkeep` files to preserve empty directories.

**Why this matters:**
- The repo stays clean: no `.gitignore` gymnastics for secrets, no accidental commits of disposable or user data.
- Persistent Docker data, media files, and user secrets are fully isolated, contained, and grouped under one root.
- The storage path is completely portable. Change the symlink target and everything follows.

### Volume mounts

Volume mounts use `../../storage/...` relative paths from the service directory. These are bind mounts; they map a host directory directly into the container, persisting whatever the service writes there. For example:

- `003-syncthing`: `../../storage:/storage` (full storage tree for backup)
- `002-immich`: `../../storage/media/002-immich:/usr/src/app/upload/library` (user photos)
- `002-immich`: `../../storage/volumes/002-immich/data:/var/lib/postgresql/data` (database files)
- `002-immich`: `../../storage/volumes/002-immich/instance-config.yml:/config/config.yml` (runtime config)

Volume breakdown by type:
- `volumes/NNN-name/data` (databases and service state, replaceable, can be rebuilt)
- `volumes/NNN-name/upload` (generated content: thumbs, profile, encoded video)
- `volumes/NNN-name/*.yml` (runtime configuration files)
- `volumes/NNN-name/certs` (SSL certificates and keys)
- `media/` (canonical home for user files and photos, portable, service-independent)

### Secrets & external configuration

Some services require secrets or config files that cannot be tracked in a public repository: database passwords, API keys, OAuth client credentials, and service-specific configuration like DDNS provider settings. These live in the persistent storage path under `storage/env/NNN-name.env` and `storage/volumes/NNN-name/`, mounted directly into the container. The service directory contains a `.env` symlink pointing to the corresponding file in `storage/env/`.

Secrets never enter the repository, so there is no risk of accidental exposure. All sensitive configuration is grouped under one root for backup and audit. The template files ([`storage.template/env/`](storage.template/env/)) contain placeholder values and documentation, serving as a reference for what each service expects.

The [`scripts/generate_secrets.sh`](scripts/generate_secrets.sh) script auto-generates strong random secrets for services that need them (authentik, immich) and writes them into the storage path. Database passwords use a URL-safe hex alphabet (`openssl rand -hex 24`) so they can't corrupt Postgres connection strings. Re-running it is safe; existing values are shown and kept unless you choose to rotate them.

## 3. Platform & Portability

This setup uses nothing but Docker Compose with standard `include:` directives. It deploys on any system that runs Docker, Mac, Linux, Windows, a potato.

## 4. Service Layout

Services are organized by numeric prefix:

- `001-filebrowser`
- `002-immich`
- `003-syncthing`
- `004-nginx`
- `005-authentik`
- `006-ddns`

The numbering is a cross-cutting identifier used consistently across directory names (`services/002-immich/`), port mappings (`8002:2283`), container names (`immich_server`), env file names (`storage.template/env/002-immich.env`), and volume paths (`storage/volumes/002-immich/`).

## 5. Opt-in Features

The stack ships minimal and lets you switch things on as you need them. There are two independent opt-in layers, both driven by plain text files under `storage/env/` — nothing hidden or magic.

### Which services run — Compose profiles

Every service is gated by its own Compose profile, named after its folder: [`001-filebrowser`](services/001-filebrowser/), [`002-immich`](services/002-immich/), [`003-syncthing`](services/003-syncthing/), [`004-nginx`](services/004-nginx/), [`005-authentik`](services/005-authentik/), [`006-ddns`](services/006-ddns/). A service starts only when its profile is active.

The active list is `COMPOSE_PROFILES` in [`000-diwanservices.env`](storage.template/env/000-diwanservices.env), which Docker Compose reads automatically through a repo-root `.env` symlink. The shipped default:

```
COMPOSE_PROFILES=001-filebrowser,002-immich
```

So a fresh install runs only Filebrowser and Immich. To add a service, append its name and re-run `docker compose up -d`:

- `003-syncthing` — Syncthing backups
- `004-nginx`, `005-authentik`, `006-ddns` — the remote-access stack (reverse proxy, SSO, dynamic DNS)

```
COMPOSE_PROFILES=001-filebrowser,002-immich,003-syncthing,004-nginx
```

### Which Immich features are on — config snippets

Immich reads one YAML config file. Rather than ship a giant file with everything half-filled (empty values can stop Immich from starting), it is assembled from parts:

- **Base** — [`config.yml`](services/002-immich/config.yml): a complete, working local config. This ships and runs out of the box.
- **Snippets** — [`config.oauth.snippet.yml`](services/002-immich/config.oauth.snippet.yml) and [`config.smtp.snippet.yml`](services/002-immich/config.smtp.snippet.yml): optional OAuth-login and SMTP-email blocks, kept apart so their empty placeholders can never break startup.

To turn one on, set its flag and fill its values in your `storage/env/002-immich.env` (seeded from [`002-immich.env`](storage.template/env/002-immich.env)) — e.g. `ENABLE_OAUTH=true` plus the `CONFIG_OAUTH_*` lines — then run [`scripts/compile-immich-config.sh`](scripts/compile-immich-config.sh).

That script rebuilds Immich's live config as **base + each enabled snippet**, substituting your values. Re-run it any time: it rebuilds from scratch, so flipping a flag back off cleanly drops that block. On a fresh install, [`scripts/generate_secrets.sh`](scripts/generate_secrets.sh) seeds the base for you, so plain local use needs no compile at all.

Both layers share one idea: the repo ships a working minimum, and everything beyond it is an explicit, file-driven opt-in.