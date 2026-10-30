#!/usr/bin/env bash
# Writes Raspberry Pi OS Lite (64-bit) to an SD card, ready to set up AlaVista
# on its own: on the first boot, the Pi joins the tailnet, installs everything,
# deploys the image of the current commit and sends a notification with ntfy.
# Usage: deploy/raspberry/flash.sh                 writes an SD card
#        deploy/raspberry/flash.sh --image <file>  writes an image file instead
# Runs on macOS. The settings are read from flash.env.local, next to this
# script, and asked for when missing: see deploy/raspberry/README.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
SETTINGS="${SCRIPT_DIR}/flash.env.local"
CACHE_DIR="${HOME}/Library/Caches/alavista"
OS_URL=https://downloads.raspberrypi.com/raspios_lite_arm64_latest
GHCR_REPOSITORY=carlosgude/alavista

fail() {
	echo "Error: $*" >&2
	exit 1
}

ask() { # ask <variable> <question> [secret]
	local answer
	if [[ ${3:-} == secret ]]; then
		read -r -s -p "$2: " answer
		echo
	else
		read -r -p "$2: " answer
	fi
	printf -v "$1" '%s' "${answer}"
}

image_exists() {
	local token
	token="$(curl -fsS "https://ghcr.io/token?scope=repository:${GHCR_REPOSITORY}:pull" | jq -r .token)"
	curl -fsS --head --output /dev/null --header "Authorization: Bearer ${token}" \
		--header 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
		"https://ghcr.io/v2/${GHCR_REPOSITORY}/manifests/$1"
}

load_settings() {
	if [[ -f ${SETTINGS} ]]; then
		# shellcheck source=/dev/null
		source "${SETTINGS}"
	fi

	PI_USER="${PI_USER:-$(id -un)}"
	[[ ${PI_USER} =~ ^[a-z_][a-z0-9_-]*$ ]] || fail "Invalid user name for the Pi: ${PI_USER}. Set PI_USER."
	if [[ -z ${SSH_PUBLIC_KEY:-} ]]; then
		local key
		for key in ~/.ssh/id_ed25519.pub ~/.ssh/id_ecdsa.pub ~/.ssh/id_rsa.pub; do
			if [[ -f ${key} ]]; then
				SSH_PUBLIC_KEY="$(cat "${key}")"
				break
			fi
		done
		[[ -n ${SSH_PUBLIC_KEY:-} ]] || fail "No SSH key found. Create one with: ssh-keygen -t ed25519"
	fi
	TIMEZONE="${TIMEZONE:-$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')}"

	# Set WIFI_SSID to an empty value in flash.env.local to use Ethernet without being asked
	if [[ -z ${WIFI_SSID+set} ]]; then
		ask WIFI_SSID "Wi-Fi network, 2.4 GHz only (leave it empty to use Ethernet)"
	fi
	if [[ -n ${WIFI_SSID} && -z ${WIFI_PASSWORD+set} ]]; then
		ask WIFI_PASSWORD "Password of ${WIFI_SSID}" secret
	fi
	WIFI_PASSWORD="${WIFI_PASSWORD:-}"
	WIFI_COUNTRY="${WIFI_COUNTRY:-$(defaults read -g AppleLocale | sed -E 's/^[a-z]+_([A-Z]{2}).*/\1/')}"
	if [[ -n ${WIFI_SSID} && ! ${WIFI_COUNTRY} =~ ^[A-Z]{2}$ ]]; then
		fail "Set WIFI_COUNTRY to the code of the country where the Pi is, such as ES"
	fi

	if [[ -z ${TS_AUTHKEY:-} ]]; then
		ask TS_AUTHKEY "Tailscale auth key, tagged tag:alavista" secret
	fi
	[[ ${TS_AUTHKEY} == tskey-* ]] || fail "A Tailscale auth key starts with tskey-"

	NTFY_URL="${NTFY_URL:-https://ntfy.sh}"
	if [[ -z ${NTFY_TOPIC:-} ]]; then
		# Anyone who knows the topic can read it: it must be hard to guess
		NTFY_TOPIC="alavista-$(openssl rand -hex 12)"
		(umask 077 && echo "NTFY_TOPIC=${NTFY_TOPIC}" >>"${SETTINGS}")
	fi
}

download_os() {
	local url name
	url="$(curl -fsSLI --output /dev/null --write-out '%{url_effective}' "${OS_URL}")"
	name="$(basename "${url}")"
	OS_IMAGE="${CACHE_DIR}/${name}"
	mkdir -p "${CACHE_DIR}"
	if [[ ! -f ${OS_IMAGE} ]]; then
		echo "==> Downloading ${name}"
		curl -fL --retry 3 --progress-bar --output "${OS_IMAGE}.part" "${url}"
		mv "${OS_IMAGE}.part" "${OS_IMAGE}"
		find "${CACHE_DIR}" -name '*.img.xz' ! -name "${name}" -delete
	fi
	echo "==> Verifying ${name}"
	if ! (cd "${CACHE_DIR}" && curl -fsSL "${url}.sha256" | shasum -a 256 --check --quiet); then
		rm -f "${OS_IMAGE}"
		fail "The download is corrupt, run it again"
	fi
}

select_disk() {
	local candidates="" disk info internal removable size
	echo "==> SD cards found:"
	for disk in $(diskutil list -plist physical | plutil -extract WholeDisks json -o - - | jq -r '.[]'); do
		info="$(diskutil info -plist "${disk}")"
		internal="$(plutil -extract Internal raw -o - - <<<"${info}" 2>/dev/null || echo true)"
		removable="$(plutil -extract RemovableMedia raw -o - - <<<"${info}" 2>/dev/null || echo false)"
		# Skips the internal disks of the Mac, but not its SD card slot
		if [[ ${internal} == true && ${removable} != true ]]; then
			continue
		fi
		size="$(plutil -extract TotalSize raw -o - - <<<"${info}")"
		echo "    ${disk}  $((size / 1000000000)) GB  $(plutil -extract MediaName raw -o - - <<<"${info}")"
		candidates="${candidates} ${disk}"
	done
	[[ -n ${candidates} ]] || fail "No SD card found: insert it and run it again"

	ask DISK "Disk to erase, everything on it will be lost (for example disk4)"
	case "${candidates} " in
	*" ${DISK} "*) ;;
	*) fail "${DISK} is not one of the SD cards found" ;;
	esac
}

write_sd() {
	select_disk
	echo "==> Writing to ${DISK}, sudo asks for your password"
	sudo -v
	diskutil unmountDisk "${DISK}" >/dev/null
	xz -dc "${OS_IMAGE}" | sudo dd of="/dev/r${DISK}" bs=4m status=progress
	sync
}

write_image_file() {
	echo "==> Writing ${OUTPUT}"
	xz -dc "${OS_IMAGE}" >"${OUTPUT}"
	DISK="$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "${OUTPUT}" | awk 'NR == 1 { sub("/dev/", "", $1); print $1 }')"
}

user_data() {
	echo '#cloud-config'
	jq -n --arg user "${PI_USER}" --arg key "${SSH_PUBLIC_KEY}" --arg timezone "${TIMEZONE}" '{
		hostname: "alavista",
		manage_etc_hosts: true,
		timezone: $timezone,
		enable_ssh: true,
		ssh_pwauth: false,
		users: [{
			name: $user,
			groups: "adm,sudo,users,video",
			shell: "/bin/bash",
			lock_passwd: true,
			sudo: "ALL=(ALL) NOPASSWD:ALL",
			ssh_authorized_keys: [$key]
		}],
		runcmd: [
			["cp", "/boot/firmware/alavista/alavista-firstboot.service", "/etc/systemd/system/"],
			["systemctl", "daemon-reload"],
			["systemctl", "enable", "--now", "--no-block", "alavista-firstboot.service"]
		]
	}'
}

network_config() {
	jq -n --arg ssid "${WIFI_SSID}" --arg password "${WIFI_PASSWORD}" --arg country "${WIFI_COUNTRY}" '{
		network: ({
			version: 2,
			renderer: "NetworkManager",
			ethernets: { eth0: { dhcp4: true, optional: true } }
		} + if $ssid == "" then {} else {
			wifis: { wlan0: {
				dhcp4: true,
				optional: true,
				"regulatory-domain": $country,
				"access-points": { ($ssid): (if $password == "" then {} else { password: $password } end) }
			} }
		} end)
	}'
}

config_env() {
	local name
	for name in IMAGE_TAG NTFY_URL NTFY_TOPIC TS_AUTHKEY ADMIN_EMAILS GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET BESZEL_KEY; do
		printf '%s=%q\n' "${name}" "${!name:-}"
	done
}

write_boot_files() {
	local boot
	echo "==> Preparing the first boot"
	for _ in $(seq 15); do
		diskutil mount "${DISK}s1" >/dev/null 2>&1 && break
		sleep 1
	done
	boot="$(diskutil info -plist "${DISK}s1" | plutil -extract MountPoint raw -o - -)"
	[[ -f ${boot}/cmdline.txt ]] || fail "The boot partition of ${DISK} is not mounted"

	user_data >"${boot}/user-data"
	network_config >"${boot}/network-config"
	mkdir -p "${boot}/alavista"
	config_env >"${boot}/alavista/config.env"
	cp -X "${SCRIPT_DIR}"/{firstboot.sh,alavista-firstboot.service,provision.sh,deploy.sh,compose.pi.yaml} \
		"${REPO_DIR}"/{compose.yaml,compose.prod.yaml} "${boot}/alavista/"
	# Removes the ._* files that macOS writes on FAT volumes
	dot_clean -m "${boot}"
}

main() {
	OUTPUT=""
	if [[ ${1:-} == --image ]]; then
		OUTPUT="${2:?Usage: $0 --image <file>}"
	fi
	[[ $(uname -s) == Darwin ]] || fail "flash.sh runs on macOS"

	local commit
	commit="$(git -C "${REPO_DIR}" rev-parse HEAD)"
	IMAGE_TAG="sha-${commit:0:7}"
	image_exists "${IMAGE_TAG}" ||
		fail "There is no image ${IMAGE_TAG} in GHCR: push the commit to main and wait for the CI"

	load_settings
	echo "Subscribe to ${NTFY_URL}/${NTFY_TOPIC} in the ntfy app to get the notifications of the Pi."
	download_os
	if [[ -n ${OUTPUT} ]]; then
		write_image_file
	else
		write_sd
	fi
	write_boot_files
	if [[ -n ${OUTPUT} ]]; then
		hdiutil detach "${DISK}" >/dev/null
		echo "Done: write ${OUTPUT} to an SD card."
	else
		diskutil eject "${DISK}" >/dev/null
		echo "Done: insert the SD card in the Pi and power it on."
	fi
	echo "You will get a notification on ${NTFY_URL}/${NTFY_TOPIC} when AlaVista is up, in about half an hour."
}

main "$@"
