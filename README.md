# DiwanSync - Private Cloud Blueprint

<img width="800" src="images/diwan.jpg">

```
Diwān - دِيوَان is a central official registry with a collection of written records.
```

# At a Glance

- A free blueprint for a private personal server hosting photos and files.
- Automatic photo backup and sharing capabilities.
- Runs on cheap refurbished hardware and scales to enterprise systems if required.
- Securely accessible everywhere. Open source. 100% free.

---

# Getting Started

**First time:**
1. Run `scripts/init.sh`. It creates the storage directory, copies templates, and generates secrets.
2. Run `docker compose up -d`.

Or manually:
1. Create a storage directory and point the `storage` symlink to it (defaults to `/storage`).
2. Copy the contents of `storage.template/` into it.
3. Generate a password for the Immich database:
   ```
   echo "DB_PASSWORD=$(openssl rand -base64 36)" >> /storage/env/002-immich.env
   ```
4. Run `docker compose up -d`.

**Redeployment or restore from backup.** Point the `storage` symlink at your existing data directory and start the services. All configs, secrets, media, and databases are already in place.

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

Remote access services (nginx, authentik, ddns) are optional. The setup runs fully locally without them by omitting those services from the compose file.

## 2. Storage Architecture

The repo contains only code and templates. All runtime data (secrets, uploads, databases, configs) lives outside the repo under a configurable storage path, defaulting to `/storage/`.

A `storage` symlink at the repo root points to the persistent data directory. This makes all Docker volume mounts resolvable relative to the repo regardless of where the actual data lives: a NAS mount, a second disk, a different machine, or just a regular folder. The symlink is the single point of configuration.

All persistent files live under one root, making backups trivial; back up the storage path and everything is captured. Each service's non-media data gets its own subdirectory under `volumes/` with no cross-contamination. The `storage.template/volumes/` mirrors this structure with `.gitkeep` files to preserve empty directories.

**Why this matters:**
- The repo stays clean: no `.gitignore` gymnastics for secrets, no accidental commits of disposable or user data.
- Persistent Docker data, media files, and user secrets are fully isolated, contained, and grouped under one root.
- The storage path is completely portable. Change the symlink target and everything follows.

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

## 5. Secrets & External Configuration

Some services require secrets or config files that cannot be tracked in a public repository: database passwords, API keys, OAuth client credentials, and service-specific configuration like DDNS provider settings. These live in the persistent storage path under `storage/env/NNN-name.env` and `storage/volumes/NNN-name/`, mounted directly into the container. The service directory contains a `.env` symlink pointing to the corresponding file in `storage/env/`.

Secrets never enter the repository, so there is no risk of accidental exposure. All sensitive configuration is grouped under one root for backup and audit. The template files (`storage.template/env/`) contain placeholder values and documentation, serving as a reference for what each service expects.

The `init.sh` convenience script auto-generates strong random secrets (`openssl rand -base64 36`) for services that need them (authentik, immich) and writes them into the storage path. Re-running init.sh is safe; it checks for existing values before overwriting.

## 6. Immich Config Pipeline (Template, Seed, Compile)

Immich requires a YAML config file for runtime settings (OAuth, machine learning, storage templates, etc.). This pipeline provides a working local setup out of the box with optional remote access as an explicit opt-in step.

**Stage 1: Template (`services/002-immich/config.yml`).**
Ships with OAuth disabled by default (`enabled: ${CONFIG_OAUTH_ENABLED:-false}`). Works immediately for local access.

**Stage 2: Seed (`init.sh`).**
On first run, copies `config.yml` to `/storage/volumes/002-immich/instance-config.yml`. Gives a working local setup with zero configuration. Idempotent: checks for existing file before copying.

**Stage 3: Compile (`services/002-immich/compile-remote-access.sh`).**
Fills in OAuth env vars and runs `envsubst` to replace template variables. Overwrites the seeded config with the compiled remote-access version. Single command, no manual YAML editing.

Local access works immediately with no configuration. Remote access requires explicit opt-in (security by default). The config is mounted as a volume, not baked into the image; changes apply on restart.