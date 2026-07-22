# Dokploy for LazyCat

This project packages Dokploy as an LPK v2 application for LazyCat OS.

## Architecture

- Dokploy and PostgreSQL run as normal LPK services.
- Dokploy controls only the isolated Playground Docker socket at `/data/playground/docker.sock`.
- Playground Docker is initialized as a single-node Swarm without touching the system or app-store Docker daemons.
- Traefik runs inside Playground Docker on host ports `30080` and `30443`.
- An LPK HAProxy service forwards LazyCat's external ports 80/443 to those internal Traefik ports.
- Runtime images use `docker.1ms.run` as the accelerator.

## Prerequisites

Install the official Dockge application and reboot LazyCat OS first. This enables Playground Docker and creates `/data/playground/docker.sock`.

The package requests the high-risk `compose.override` permission so it can mount the Playground Docker socket and share `/etc/dokploy` with containers created by Dokploy.

## Limitations

- SQLite is not supported by upstream Dokploy; this package uses PostgreSQL 16.
- Passwordless login is intentionally not configured. Create the first Dokploy account manually.
- The package is configured for MiaoMiao private-store publication only. Official LazyCat store publication is disabled.
- Do not use Dokploy's self-update command. GitHub Actions updates the LPK from upstream image tags.
- Dokploy-managed containers and `/etc/dokploy` survive LPK removal and must be cleaned up separately if no longer needed.
- HTTP/3 (UDP 443) is not forwarded; HTTP and HTTPS over TCP are supported.

## GitHub Actions

The scheduled workflow checks stable `dokploy/dokploy` tags, updates `package.yml` and the `dokploy` service image, builds a versioned GitHub Release asset, and submits it only to the MiaoMiao private store.

Configure these repository or authorized organization Secrets:

- `APPSTORE_URL`
- `APPSTORE_TOKEN`
- `APP_ID` (optional)
- `PRIVATE_STORE_GROUP_CODES` (optional, comma-separated)

The workflow uses `docker.1ms.run/dokploy/dokploy:{tag}` and requires its target-platform digest to match the upstream image.

Manual workflow runs default to dry-run mode. Clear the `dry_run` option only when an immediate update and MiaoMiao submission is intended; scheduled runs publish normally when a newer version is found.

## Local build

```bash
lzc-cli project release -o dist/application.lpk
lzc-cli lpk info dist/application.lpk
```
