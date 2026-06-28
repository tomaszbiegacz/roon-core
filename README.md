# roon-core

Community-maintained Docker image for [Roon Server](https://roon.app) on Linux. Roon Server is baked into the image at build time and runs as a dedicated non-root user.

This project is **not affiliated with or endorsed by Roon Labs**. For the official image and support channel, see [RoonLabs/roon-docker](https://github.com/RoonLabs/roon-docker).

Pre-built images are published on Docker Hub as [`tbiegacz/roon-core`](https://hub.docker.com/r/tbiegacz/roon-core). Each tag matches the Roon Server version it contains (for example `2.67.1661`).

---

## Introduction

### How this image differs from the official one

The [official Roon Docker image](https://github.com/RoonLabs/roon-docker/blob/main/Dockerfile) downloads Roon Server on **first container start** and keeps application files under a writable volume. This image takes a **closed-package** approach: Roon Server is downloaded during the **image build** and lives inside the image under `/app`. Persistent state is limited to the mounted data, music, and backup paths.

| | This image (`tbiegacz/roon-core`) | Official image (`RoonLabs/roon-docker`) |
|---|---|---|
| Roon install | Baked in at build time | Downloaded on first run (and on branch change) |
| Version | Fixed by image tag | Managed by entrypoint / self-update |
| Runtime user | `roon` (UID/GID **1010**) | root |
| Base image | Ubuntu LTS | Debian slim |
| Data volume | `/data` | `/Roon/database` |
| Backup volume | `/backup` | `/RoonBackups` |
| Music volume | `/music` | `/Music` |
| App binaries | `/app` (inside image) | `/Roon/app` (on volume) |
| Branch switching | Not supported — use a new image tag | `production` / `earlyaccess` via env |

### When to use this image

**Good fit if you want:**

- A pinned, reproducible Roon version (the Docker tag *is* the version)
- No first-run download from the internet inside the container
- Roon Server running as a non-root user
- A simple volume layout (`/data`, `/music`, `/backup`)

**Consider the official image if you want:**

- Roon-maintained entrypoint behavior, health checks, and branch selection
- In-container install/update logic without rebuilding or publishing a new tag

### Trade-offs of the closed package

- **Pros:** Predictable startup, works offline after `docker pull`, no dependency on Roon download servers at runtime.
- **Cons:** Upgrading Roon means pulling (or building) a new image tag. There is no automatic in-container branch switch or self-update of the application bundle.

---

## Getting started

### Prerequisites

- Linux host with Docker (and Docker Compose v2)
- **`network_mode: host`** — Roon discovery and RAAT rely on host networking; bridge mode is not covered here
- Writable host paths for `/data` and `/backup`, and a path for `/music` (read-only is recommended)

### Quick start

1. Create a `version.env` file:

```env
ROON_IMAGE=tbiegacz/roon-core
ROON_VERSION=2.67.1661
```

Replace `ROON_VERSION` with the tag you want from [Docker Hub](https://hub.docker.com/r/tbiegacz/roon-core/tags).

2. Prepare the data directory (once):

```bash
sudo mkdir -p /mnt/data/RoonServer
sudo chown -R 1010:1010 /mnt/data/RoonServer
```

The container runs as UID **1010**. Roon must be able to read and write `/data`.

3. Create `docker-compose.yml`:

```yaml
services:
  core:
    image: ${ROON_IMAGE}:${ROON_VERSION}
    restart: unless-stopped
    network_mode: host
    volumes:
      - /mnt/data/RoonServer:/data:rw
      - /mnt/RoonBackup:/backup:rw
      - /mnt/music:/music:ro
    environment:
      - TZ=Europe/Warsaw
      - ROON_DATAROOT=/data
      - ROON_ID_DIR=/data
      - ROON_DEFAULT_MUSIC_FOLDER_WATCH_PATH=/music
```

Adjust host paths and `TZ` for your environment. Mount points on the host can differ; what matters is the container paths (`/data`, `/backup`, `/music`).

4. Start the core:

```bash
docker compose --env-file version.env pull
docker compose --env-file version.env up -d
docker compose --env-file version.env logs -f
```

5. Open the Roon desktop or mobile app on the same LAN and connect to the new core. On first run, point the library watch folder at `/music` if it is not picked up automatically.

### Volume summary

| Container path | Mount mode | Purpose |
|---|---|---|
| `/data` | **rw** | Database, cache, analysis, machine identity |
| `/backup` | **rw** | Roon scheduled backups |
| `/music` | **ro** (recommended) | Music library — Roon only needs read access |
| `/app` | *(not mounted)* | Roon binaries; provided by the image |

Do not mount over `/app` unless you are developing a custom build. Production use expects the baked-in application.

### Permissions cheat sheet

| Path | Typical ownership / options | Notes |
|---|---|---|
| `/data` | Host dir owned by `1010:1010` | Required. Run `chown` once before first start. |
| `/music` | NFS/SMB exported read-only, mounted `:ro` in Compose | No write access needed on the host for Roon. |
| `/backup` | CIFS/NFS with `uid=1010,gid=1010` (or host dir `1010:1010`) | Roon must create and update backup files here. |

If you migrated from an image that ran as root, re-own the data directory:

```bash
sudo chown -R 1010:1010 /mnt/data/RoonServer
```

### Upgrading Roon

1. Set `ROON_VERSION` in `version.env` to the new tag.
2. Pull and recreate:

```bash
docker compose --env-file version.env pull
docker compose --env-file version.env up -d
```

Your `/data` volume is preserved. Back up before major upgrades if you rely on production library metadata.

### Building your own image (optional)

This repository contains the `Dockerfile` and `start.sh` used to publish `tbiegacz/roon-core`. To build locally, pass the same build args the Dockerfile expects (defaults: `ROON_UID=1010`, `ROON_GID=1010`) and tag the result yourself. The build downloads the current production tarball from Roon’s servers; the resulting tag should match the Roon version inside the tarball.

---

## Working configuration details

The following describes a setup that works well in production: fast local storage for Roon’s database, a read-only music library on the network, and backups on a NAS share that is separately archived to cloud cold storage.

### Storage layout

```
Host                         Container    Access
─────────────────────────────────────────────────
Local SSD                    /data        rw  — DB, cache, analysis
NAS NFS export (music)       /music       ro  — library files
NAS Samba share (backups)    /backup      rw  — Roon backup sets
```

**Why split storage this way**

- **`/data` on local SSD** — Roon is I/O heavy (database, artwork cache, audio analysis). Keeping this off spinning NAS disks or remote shares improves responsiveness and avoids locking issues.
- **`/music` read-only over NFS** — The library is large and shared; NFS with `:ro` prevents accidental writes from the container and matches a “published library” model.
- **`/backup` on Samba** — Roon’s backup browser writes backup sets to `/backup`. A dedicated NAS folder is easy to snapshot and replicate. Cloud archival (for example AWS Glacier on the NAS or a sync job) is an **operator concern** outside the container; Roon only needs a writable mount at `/backup`.

### Non-root user (UID 1010)

The image creates user `roon` with UID/GID **1010** and starts Roon Server as that user.

**Benefits**

- Reduced impact if a process in the container were compromised
- Clear ownership on host files: everything under `/data` and `/backup` should be owned by `1010:1010`
- Easier reasoning about permissions on CIFS mounts

**Setup required**

1. **Data directory** — before first run:

   ```bash
   sudo chown -R 1010:1010 /mnt/data/RoonServer
   ```

2. **Optional matching host user** — helps when inspecting files or writing fstab mounts:

   ```bash
   sudo groupadd -g 1010 roon 2>/dev/null || true
   sudo useradd -u 1010 -g 1010 -M -s /usr/sbin/nologin roon 2>/dev/null || true
   ```

3. **Samba backup share** — the CIFS mount must map remote files to UID 1010 on the Linux host. Use `uid=` and `gid=` in `/etc/fstab` (or equivalent mount options). Without this, Roon will fail to write backups even if the share is writable for other users.

   After changing `uid`/`gid`, remount:

   ```bash
   sudo umount /mnt/RoonBackup
   sudo mount -a
   ```

The Dockerfile sets `USER roon`; you do not need `user: "1010:1010"` in Compose unless you override the image user for local testing.

### Host packages and mounts

Install client tools on the Docker host (not inside the container):

```bash
sudo apt install nfs-common cifs-utils
sudo systemctl enable remote-fs.target
```

#### Samba credentials

Store credentials outside the world-readable path:

```bash
sudo nano /etc/samba/credentials
```

```
username=YOUR_SAMBA_USER
password=YOUR_SAMBA_PASSWORD
```

```bash
sudo chmod 600 /etc/samba/credentials
```

#### Example `/etc/fstab` entries

Replace placeholders with your NAS address, export paths, and mount points. **`uid` and `gid` must be 1010** for the backup share.

```
# Music library (read-only NFS)
NAS_HOST:/export/music    /mnt/music       nfs   defaults,_netdev,nfsvers=4,rsize=131072,wsize=131072   0  0

# Roon backups (read-write CIFS, owned by container user)
//NAS_HOST/backup/roon    /mnt/RoonBackup  cifs  credentials=/etc/samba/credentials,uid=1010,gid=1010   0  0
```

Apply mounts:

```bash
sudo mount -a
```

Compose then bind-mounts these host paths:

```yaml
volumes:
  - /mnt/data/RoonServer:/data:rw
  - /mnt/RoonBackup:/backup:rw
  - /mnt/music:/music:ro
```

#### Manual mount (testing only)

```bash
sudo mount -t nfs NAS_HOST:/export/music /mnt/music
sudo mount -t cifs //NAS_HOST/backup/roon /mnt/RoonBackup \
  -o credentials=/etc/samba/credentials,uid=1010,gid=1010
```

### Firewall (UFW example)

Adjust the LAN CIDR for your network. Roon ARC requires a port forward on your router to the host running the core.

```bash
LAN="192.168.1.0/24"

# Roon Remote / Core (LAN only)
sudo ufw allow from $LAN to any port 9150 proto tcp comment 'Roon Appliance'
sudo ufw allow from $LAN to any port 9330:9339 proto tcp comment 'Roon Core'

# Discovery (LAN only)
sudo ufw allow from $LAN to any port 9003 proto udp comment 'Roon discovery'

# Roon ARC (internet + LAN — port-forward on router)
sudo ufw allow 45534/tcp comment 'Roon ARC'
```

### Troubleshooting

| Symptom | Likely cause | What to check |
|---|---|---|
| Permission denied under `/data` | Directory owned by root or wrong UID | `ls -ln /mnt/data/RoonServer` → expect `1010 1010`; run `chown -R 1010:1010` |
| Backups fail, music works | CIFS mount not mapped to 1010 | fstab `uid=1010,gid=1010`; remount after changes |
| Remotes cannot find core | Network isolation | Compose must use `network_mode: host`; check UDP 9003 and TCP 9330–9339 on LAN |
| Empty or wrong library | Watch path mismatch | Set `ROON_DEFAULT_MUSIC_FOLDER_WATCH_PATH=/music` or add `/music` in Roon settings |
| Upgrade did not change version | Old container still running | `docker compose pull` then `up -d`; confirm tag in `version.env` |

### References

- [Roon Linux install — package layout](https://help.roonlabs.com/portal/en/kb/articles/linux-install#Package_Layout)
- [Roon software release notes](https://community.roonlabs.com/c/roon/software-release-notes)
- [Official Roon Docker image](https://github.com/RoonLabs/roon-docker)
