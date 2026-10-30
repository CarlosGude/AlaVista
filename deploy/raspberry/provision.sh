#!/usr/bin/env bash
# Prepares a fresh Raspberry Pi OS Lite (64-bit) to run AlaVista.
# Every step checks its current state first, so it is safe to run it again.
# Usage: sudo ./provision.sh
set -euo pipefail

APP_DIR=/opt/alavista
DEPLOY_USER=deploy
TS_HOSTNAME="${TS_HOSTNAME:-alavista}"
TS_TAG="${TS_TAG:-tag:alavista}"

if [[ $(id -u) -ne 0 ]]; then
	echo "Run it as root: sudo $0" >&2
	exit 1
fi

if [[ $(uname -m) != aarch64 ]]; then
	echo "A 64-bit OS is required, found $(uname -m)" >&2
	exit 1
fi

echo "==> System packages"
apt-get update
apt-get upgrade --yes
apt-get install --yes --no-install-recommends ca-certificates curl jq openssl

echo "==> Docker"
if ! command -v docker >/dev/null; then
	curl -fsSL https://get.docker.com | sh
fi
if [[ ! -f /etc/docker/daemon.json ]]; then
	# Rotate container logs so they do not fill the SD card
	echo '{"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "3"}}' >/etc/docker/daemon.json
	systemctl restart docker
fi

echo "==> Swap in compressed RAM (zram)"
if ! swapon --show=NAME --noheadings | grep -q zram; then
	apt-get install --yes --no-install-recommends zram-tools
	printf 'ALGO=zstd\nPERCENT=50\nPRIORITY=100\n' >/etc/default/zramswap
	systemctl restart zramswap
fi
# A swap file on the SD card is slow and wears it out
if systemctl is-enabled --quiet dphys-swapfile 2>/dev/null; then
	systemctl disable --now dphys-swapfile
fi

echo "==> Tailscale"
if ! command -v tailscale >/dev/null; then
	curl -fsSL https://tailscale.com/install.sh | sh
fi
# Lets the php container (www-data, uid 33) get the certificate of the *.ts.net name
if ! grep -q '^TS_PERMIT_CERT_UID=33$' /etc/default/tailscaled; then
	echo 'TS_PERMIT_CERT_UID=33' >>/etc/default/tailscaled
	systemctl restart tailscaled
fi
if [[ $(tailscale status --json | jq -r .BackendState) != Running ]]; then
	# Prints a link to authenticate the Pi in your tailnet
	tailscale up --ssh --hostname "${TS_HOSTNAME}" --advertise-tags "${TS_TAG}"
fi
server_name="$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')"

echo "==> Deploy user"
if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
	useradd --create-home --shell /bin/bash --groups docker "${DEPLOY_USER}"
fi

echo "==> Application directory"
install --directory --owner "${DEPLOY_USER}" --group "${DEPLOY_USER}" --mode 750 "${APP_DIR}"
if [[ ! -f ${APP_DIR}/.env ]]; then
	install --owner "${DEPLOY_USER}" --group "${DEPLOY_USER}" --mode 600 /dev/null "${APP_DIR}/.env"
	cat >"${APP_DIR}/.env" <<EOF
# Read by docker compose in ${APP_DIR}. It holds the production secrets: keep it private.
COMPOSE_FILE=compose.yaml:compose.prod.yaml:compose.pi.yaml
# Updated by deploy.sh after each successful deployment
IMAGE_TAG=
SERVER_NAME=${server_name}
APP_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 24)
CADDY_MERCURE_JWT_SECRET=$(openssl rand -hex 32)
# Fill in to enable the admin login
ADMIN_EMAILS=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
EOF
fi

cat <<EOF

The Pi is ready. Remaining steps (see deploy/raspberry/README.md):
- GitHub environment "raspberry": set the PI_HOST secret to ${server_name}
- Google sign-in: fill in ${APP_DIR}/.env and add the authorized redirect URI
https://${server_name}/connect/google/check
EOF
