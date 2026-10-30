#!/usr/bin/env bash
# Deploys an AlaVista image tag on the Raspberry Pi and rolls back to the
# previously deployed tag if the new one does not become healthy.
# Usage: deploy.sh sha-<commit>
set -euo pipefail
# .env holds the production secrets
umask 077

cd "$(dirname "$0")"

tag="${1:-}"
if [[ ! ${tag} =~ ^sha-[0-9a-f]{7,40}$ ]]; then
	echo "Usage: $0 sha-<commit>" >&2
	exit 64
fi

env_value() {
	sed -n "s/^$1=//p" .env
}

previous="$(env_value IMAGE_TAG)"
https_port="$(env_value HTTPS_PORT)"
smoke_url="https://$(env_value SERVER_NAME):${https_port:-443}/login"

deploy() {
	echo "Deploying $1"
	# Chained with && because errexit is ignored inside the caller's if condition
	IMAGE_TAG="$1" docker compose pull --quiet &&
		IMAGE_TAG="$1" docker compose up --detach --no-build --wait --wait-timeout 300 --remove-orphans &&
		# The first request waits for Caddy to get the certificate from Tailscale
		curl --fail --silent --show-error --max-time 60 --retry 3 --retry-all-errors \
			--output /dev/null "${smoke_url}"
}

if deploy "${tag}"; then
	sed "s/^IMAGE_TAG=.*/IMAGE_TAG=${tag}/" .env >.env.new && mv .env.new .env
	# Old images are not kept: a rollback pulls them again from GHCR
	docker image prune --all --force >/dev/null
	echo "Deployed ${tag}"
	exit 0
fi

echo "Deployment of ${tag} failed" >&2
IMAGE_TAG="${tag}" docker compose logs --tail 50 php >&2 || true

if [[ -n ${previous} ]]; then
	echo "Rolling back to ${previous}" >&2
	deploy "${previous}" || echo "Rollback to ${previous} failed too" >&2
fi

exit 1
