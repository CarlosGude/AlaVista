# Deploying to the Raspberry Pi

AlaVista runs on a Raspberry Pi 3 Model B (1 GB of RAM) as a playground for constrained hardware. Every push to `main` that passes the CI is built, published and deployed without manual steps.

## How it works

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

1. Flash Raspberry Pi OS Lite (64-bit) with Raspberry Pi Imager. In its settings, set the hostname, a user, and SSH with your public key.
2. Copy the provisioning script to the Pi and run it:

   ```console
   scp deploy/raspberry/provision.sh <user>@<hostname>.local:
   ssh -t <user>@<hostname>.local sudo ./provision.sh
   ```

   It installs Docker, swap in compressed RAM and Tailscale, and creates the `deploy` user and `/opt/alavista/.env` with generated secrets. Open the link it prints to add the Pi to your tailnet. At the end, it prints the `*.ts.net` name of the Pi.

3. To enable the admin, fill in `ADMIN_EMAILS`, `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `/opt/alavista/.env`, and add `https://<ts.net name>/connect/google/check` to the authorized redirect URIs of the Google OAuth client. The values are applied on the next deployment.

### 3. GitHub

1. Create a `raspberry` environment in the repository settings, with these secrets:
   - `TS_OAUTH_CLIENT_ID` and `TS_OAUTH_SECRET`: the Tailscale OAuth client.
   - `PI_HOST`: the `*.ts.net` name printed by `provision.sh`.
2. Add the `RASPBERRY_DEPLOY_ENABLED` repository variable with the value `true`. Until then, the CI builds and publishes the image but does not deploy it.
3. The Pi pulls the image without credentials, so the `alavista` package must be public. Check its visibility in the package settings after the first build.

### 4. Monitoring with Beszel (optional)

[Beszel](https://beszel.dev) keeps the history of the CPU, memory, swap, disk, network and temperature of the Pi, and of the usage of each container. The dashboard (the hub) runs on your computer and only a small agent runs on the Pi, so that the monitoring does not skew the measurements.

1. Start the hub on your computer, then open <http://localhost:8090> and create your account:

   ```console
   docker compose -f deploy/raspberry/beszel/compose.yaml up -d
   ```

2. Select **Add system**, with the `*.ts.net` name of the Pi as host and `45876` as port, and copy the public key it shows.
3. Run the provisioning script again with that key:

   ```console
   ssh -t <user>@<hostname>.local "sudo BESZEL_KEY='<public key>' ./provision.sh"
   ```

The hub connects to the agent over Tailscale, so Tailscale must be running on your computer. If your access controls do not let your devices reach every port of the Pi, allow `tag:alavista:45876`. If the hub cannot resolve the `*.ts.net` name, use the Tailscale IP of the Pi instead (`tailscale ip -4 alavista`). The agent only accepts connections from the hub that owns the key.

## Operations

- **Roll back:** run the Deploy workflow manually from the Actions tab, with an older `sha-<commit>` tag.
- **Inspect:** `sudo -iu deploy`, then `cd /opt/alavista` and use `docker compose ps`, `docker compose logs php` or `docker stats`.
- **Measure:** the Beszel dashboard keeps the history. For a quick look on the Pi, use `free -h`, `vcgencmd measure_temp` and `vcgencmd get_throttled`. Any value other than `throttled=0x0` means under-voltage or thermal throttling, which skews the measurements.
- **Tune:** the number of workers and the PostgreSQL settings are in [`compose.pi.yaml`](compose.pi.yaml).
- **Update Beszel:** change the version in [`provision.sh`](provision.sh) and in [`beszel/compose.yaml`](beszel/compose.yaml). Then run `provision.sh` again on the Pi, and `docker compose -f deploy/raspberry/beszel/compose.yaml up -d` on your computer.
