#!/bin/sh
set -eu

log() {
  echo "[dokploy-bootstrap] $*"
}

fail() {
  echo "[dokploy-bootstrap] ERROR: $*" >&2
  exit 1
}

DOCKER_SOCKET=/var/run/docker.sock
TRAEFIK_VERSION=3.6.7
TRAEFIK_MIRROR_IMAGE="docker.1ms.run/library/traefik:v${TRAEFIK_VERSION}"
TRAEFIK_RUNTIME_IMAGE="traefik:v${TRAEFIK_VERSION}"
TRAEFIK_HTTP_PORT="${TRAEFIK_PORT:-30080}"
TRAEFIK_HTTPS_PORT="${TRAEFIK_SSL_PORT:-30443}"

[ -S "$DOCKER_SOCKET" ] || fail "Playground Docker socket is unavailable. Install Dockge and reboot LazyCat OS first."
docker version >/dev/null 2>&1 || fail "Cannot connect to Playground Docker."

mkdir -p /etc/dokploy/traefik/dynamic
chmod 755 /etc/dokploy
touch /etc/dokploy/traefik/dynamic/acme.json
chmod 600 /etc/dokploy/traefik/dynamic/acme.json

if ! docker swarm inspect >/dev/null 2>&1; then
  log "initializing Playground Docker as a single-node Swarm"
  docker swarm init --advertise-addr 127.0.0.1 >/dev/null
else
  log "Playground Docker Swarm is already active"
fi

if ! docker network inspect dokploy-network >/dev/null 2>&1; then
  log "creating dokploy-network"
  docker network create --driver overlay --attachable dokploy-network >/dev/null
fi

if [ ! -f /etc/dokploy/traefik/traefik.yml ]; then
  log "creating Traefik configuration"
  cat > /etc/dokploy/traefik/traefik.yml <<EOF
global:
  sendAnonymousUsage: false
providers:
  swarm:
    exposedByDefault: false
    watch: true
  docker:
    exposedByDefault: false
    watch: true
    network: dokploy-network
  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true
entryPoints:
  web:
    address: ":${TRAEFIK_HTTP_PORT}"
  websecure:
    address: ":${TRAEFIK_HTTPS_PORT}"
    http:
      tls:
        certResolver: letsencrypt
api:
  dashboard: true
  insecure: true
certificatesResolvers:
  letsencrypt:
    acme:
      email: test@localhost.com
      storage: /etc/dokploy/traefik/dynamic/acme.json
      httpChallenge:
        entryPoint: web
EOF
fi

if [ ! -f /etc/dokploy/traefik/dynamic/middlewares.yml ]; then
  cat > /etc/dokploy/traefik/dynamic/middlewares.yml <<'EOF'
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
        permanent: true
EOF
fi

if ! docker image inspect "$TRAEFIK_RUNTIME_IMAGE" >/dev/null 2>&1; then
  log "pulling Traefik through docker.1ms.run"
  if docker pull "$TRAEFIK_MIRROR_IMAGE"; then
    docker tag "$TRAEFIK_MIRROR_IMAGE" "$TRAEFIK_RUNTIME_IMAGE"
  else
    log "mirror pull failed; falling back to Docker Hub"
    docker pull "$TRAEFIK_RUNTIME_IMAGE"
  fi
fi

if docker container inspect dokploy-traefik >/dev/null 2>&1; then
  log "starting existing dokploy-traefik container"
  docker start dokploy-traefik >/dev/null 2>&1 || true
else
  log "creating dokploy-traefik container"
  docker run -d \
    --name dokploy-traefik \
    --restart always \
    -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
    -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    -p "${TRAEFIK_HTTP_PORT}:${TRAEFIK_HTTP_PORT}/tcp" \
    -p "${TRAEFIK_HTTPS_PORT}:${TRAEFIK_HTTPS_PORT}/tcp" \
    "$TRAEFIK_RUNTIME_IMAGE" >/dev/null
fi

docker network connect dokploy-network dokploy-traefik >/dev/null 2>&1 || true
log "Playground Docker and Traefik are ready"
