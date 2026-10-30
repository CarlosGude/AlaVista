# Deploying to the Raspberry Pi

AlaVista runs on a Raspberry Pi 3 Model B (1 GB of RAM) as a playground for constrained hardware. Every push to `main` that passes the CI is built, published and deployed without manual steps.

## How it works

[`flash.sh`](flash.sh) writes an SD card that sets up the Pi on its own. On the first boot, the Pi joins the tailnet, installs Docker, deploys the image of the commit you flashed from, and sends a notification with [ntfy](https://ntfy.sh). After that, every push to `main` is deployed:

1. The `build` job of the [CI](../../.github/workflows/ci.yaml) builds the production image on a native arm64 runner and pushes it to GHCR as `ghcr.io/carlosgude/alavista:sha-<commit>`.
2. The [Deploy workflow](../../.github/workflows/deploy.yaml) joins the tailnet as `tag:ci`, copies the Compose files and [`deploy.sh`](deploy.sh) to `/opt/alavista` over Tailscale SSH, and runs it.
3. `deploy.sh` pulls the image, starts the containers, waits until they are healthy and requests `/login` over HTTPS. If any step fails, it deploys the previous tag again and the workflow fails.
4. Caddy gets the certificate of the `*.ts.net` name of the Pi from Tailscale, so browser geolocation and the Google sign-in work.

The app is only reachable from your tailnet, nothing is exposed to the internet.

Migrations run when the php container starts. Keep them backward compatible, so that a rollback can run on the new schema.

## One-time setup

### 1. Tailscale

1. In the [DNS settings](https://login.tailscale.com/admin/dns), enable MagicDNS and HTTPS certificates.
2. Add these tags and rules to the [access controls](https://login.tailscale.com/admin/acls), keeping the rules that give your own devices access:

   ```json
   {
     "tagOwners": {
       "tag:alavista": ["autogroup:admin"],
       "tag:ci": ["autogroup:admin"]
     },
     "acls": [
       { "action": "accept", "src": ["tag:ci"], "dst": ["tag:alavista:22"] }
     ],
     "ssh": [
       {
         "action": "accept",
         "src": ["tag:ci"],
         "dst": ["tag:alavista"],
         "users": ["deploy"]
       }
     ]
   }
   ```

3. Create an [OAuth client](https://login.tailscale.com/admin/settings/oauth) with the `auth_keys` write scope and the `tag:ci` tag. Keep its ID and secret for GitHub.

### 2. Raspberry Pi

1. Install the [ntfy app](https://ntfy.sh) on your phone, or use its web app, to get the notifications of the Pi.
2. Generate an [auth key](https://login.tailscale.com/admin/settings/keys) for the Pi, pre-approved and with the `tag:alavista` tag. The Pi only uses it on the first boot, so a one-off key that expires in a day is enough.
3. Insert the SD card in your Mac and run:

   ```console
   deploy/raspberry/flash.sh
   ```

   It asks for the Wi-Fi network and the auth key, downloads Raspberry Pi OS Lite (64-bit), asks which disk to erase and writes the SD card. The first time, it generates a ntfy topic: subscribe to the one it prints.

4. Insert the SD card in the Pi and power it on. In about half an hour, you get a notification with the address of AlaVista and the `*.ts.net` name of the Pi.
5. Add `https://<ts.net name>/connect/google/check` to the authorized redirect URIs of the Google OAuth client.

The Pi deploys the image of the commit you run `flash.sh` from, so that commit must be on `main` and built by the CI.

If the setup fails, the notification shows the last lines of the log, and rebooting the Pi tries again. If no notification arrives, the Pi has no network: check the Wi-Fi settings and write the SD card again. To read the log, run `journalctl -u alavista-firstboot` on the Pi, over `ssh <your user>@alavista.local`.

#### Settings

To avoid typing the settings every time, write them in `deploy/raspberry/flash.env.local`. Git ignores this file:

```shell
# An empty value uses Ethernet. The Pi 3 only connects to 2.4 GHz networks.
WIFI_SSID='My network'
WIFI_PASSWORD='...'
# Enables the admin login
ADMIN_EMAILS=you@example.com
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
# Enables the monitoring, see below
BESZEL_KEY='ssh-ed25519 ...'
```

`flash.sh` also reads `PI_USER` (your macOS user by default), `SSH_PUBLIC_KEY` (`~/.ssh/id_ed25519.pub` by default), `TIMEZONE` and `WIFI_COUNTRY` (taken from your Mac), `TS_AUTHKEY`, `NTFY_URL` (`https://ntfy.sh` by default) and `NTFY_TOPIC`, which it saves to this file the first time.

Until the first boot finishes, the boot partition of the SD card holds the auth key and the Google secret in plain text. The Pi removes them when the setup succeeds. The Wi-Fi password stays in its `network-config` file.

To set up a Pi that already runs Raspberry Pi OS instead, copy [`provision.sh`](provision.sh) to it and run `sudo ./provision.sh`. It prints a link to add the Pi to your tailnet. Then fill in `/opt/alavista/.env`.

### 3. GitHub

1. Create a `raspberry` environment in the repository settings, with these secrets:
   - `TS_OAUTH_CLIENT_ID` and `TS_OAUTH_SECRET`: the Tailscale OAuth client.
   - `PI_HOST`: the `*.ts.net` name of the Pi, sent in the notification.
2. Add the `RASPBERRY_DEPLOY_ENABLED` repository variable with the value `true`. Until then, the CI builds and publishes the image but does not deploy it.
3. The Pi pulls the image without credentials, so the `alavista` package must stay public.

### 4. Monitoring with Beszel (optional)

[Beszel](https://beszel.dev) keeps the history of the CPU, memory, swap, disk, network and temperature of the Pi, and of the usage of each container. The dashboard (the hub) runs on your computer and only a small agent runs on the Pi, so that the monitoring does not skew the measurements.

1. Start the hub on your computer, then open <http://localhost:8090> and create your account:

   ```console
   docker compose -f deploy/raspberry/beszel/compose.yaml up -d
   ```

2. Select **Add system**, with the `*.ts.net` name of the Pi as host and `45876` as port, and copy the public key it shows. The key is the same for every system.
3. Set `BESZEL_KEY` to that key in `flash.env.local` before you write the SD card. On a Pi that is already set up, run the provisioning script again with the key:

   ```console
   scp deploy/raspberry/provision.sh <your user>@alavista.local:
   ssh -t <your user>@alavista.local "sudo BESZEL_KEY='<public key>' ./provision.sh"
   ```

The hub connects to the agent over Tailscale, so Tailscale must be running on your computer. If your access controls do not let your devices reach every port of the Pi, allow `tag:alavista:45876`. If the hub cannot resolve the `*.ts.net` name, use the Tailscale IP of the Pi instead (`tailscale ip -4 alavista`). The agent only accepts connections from the hub that owns the key.

## Operations

- **Roll back:** run the Deploy workflow manually from the Actions tab, with an older `sha-<commit>` tag.
- **Inspect:** `sudo -iu deploy`, then `cd /opt/alavista` and use `docker compose ps`, `docker compose logs php` or `docker stats`.
- **Measure:** the Beszel dashboard keeps the history. For a quick look on the Pi, use `free -h`, `vcgencmd measure_temp` and `vcgencmd get_throttled`. Any value other than `throttled=0x0` means under-voltage or thermal throttling, which skews the measurements.
- **Tune:** the number of workers and the PostgreSQL settings are in [`compose.pi.yaml`](compose.pi.yaml).
- **Start from scratch:** run `flash.sh` again. The database starts empty. Remove the old `alavista` machine from the [Tailscale admin console](https://login.tailscale.com/admin/machines) first, or the new one gets another `*.ts.net` name and `PI_HOST` must change.
- **Update Beszel:** change the version in [`provision.sh`](provision.sh) and in [`beszel/compose.yaml`](beszel/compose.yaml). Then run `provision.sh` again on the Pi, and `docker compose -f deploy/raspberry/beszel/compose.yaml up -d` on your computer.
