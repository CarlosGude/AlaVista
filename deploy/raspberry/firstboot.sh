#!/usr/bin/env bash
# Sets up AlaVista on the first boot of an SD card written by flash.sh: it
# provisions the Pi, deploys the image and sends a notification with ntfy.
# It runs from the alavista-firstboot service, which runs it again on every
# boot until it succeeds.
set -euo pipefail

BOOT_DIR="$(cd "$(dirname "$0")" && pwd)"

notify() { # notify <title> <message> <priority> <tags> [<click URL>]
	curl --silent --show-error --max-time 30 --retry 3 --output /dev/null \
		--header "Title: $1" --header "Priority: $3" --header "Tags: $4" \
		${5:+--header "Click: $5"} --data "$2" "${NTFY_URL}/${NTFY_TOPIC}" || true
}

on_exit() {
	local status=$?
	if ((status != 0)); then
		notify "AlaVista setup failed" "$(journalctl --unit alavista-firstboot --lines 15 --output cat)
Reboot the Pi to try again." high warning
	fi
}

wait_for_network() {
	for _ in $(seq 60); do
		if curl --silent --output /dev/null --max-time 10 "${NTFY_URL}"; then
			return 0
		fi
		sleep 10
	done
	echo "No network after 10 minutes" >&2
	return 1
}

# A function, so that bash has read all of it before the script removes itself
main() {
	# Written by flash.sh: the image tag, the notification topic and the secrets
	set -a
	# shellcheck source=/dev/null
	source "${BOOT_DIR}/config.env"
	set +a
	trap on_exit EXIT

	wait_for_network
	notify "Setting up AlaVista" "The Pi is online. Setting it up can take half an hour." low hourglass_flowing_sand

	bash "${BOOT_DIR}/provision.sh"

	echo "==> Deploying ${IMAGE_TAG}"
	cd "${BOOT_DIR}"
	install --owner deploy --group deploy --mode 644 compose.yaml compose.prod.yaml compose.pi.yaml /opt/alavista/
	install --owner deploy --group deploy --mode 755 deploy.sh /opt/alavista/
	runuser --user deploy -- /opt/alavista/deploy.sh "${IMAGE_TAG}"

	echo "==> Removing the secrets from the boot partition"
	cd /
	systemctl disable alavista-firstboot.service
	rm -rf "${BOOT_DIR}"

	local server_name
	server_name="$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')"
	notify "AlaVista is up" "https://${server_name}
To deploy every push to main, set the PI_HOST secret of the raspberry environment in GitHub to ${server_name}" \
		default white_check_mark "https://${server_name}"
}

main "$@"
