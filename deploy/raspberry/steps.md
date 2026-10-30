# Setting up the Raspberry Pi, step by step

Every step to go from nothing to AlaVista running on the Pi and deployed on every push to `main`, in order. Tick them off as you go. [`startup.md`](startup.md) explains what happens behind the scenes, and the [deployment guide](README.md) has more details about each part.

Replace `<tailnet>` with the tailnet DNS name that you note down in step 1, such as `tail1234.ts.net`. The Pi gets the name `alavista.<tailnet>`.

## What you need

- [ ] A Raspberry Pi 3 Model B, a microSD card of 16 GB or more, and a 5 V, 2.5 A power supply. A weaker supply causes under-voltage, which slows the Pi down and skews the measurements.
- [ ] A microSD card reader for your Mac.
- [ ] A 2.4 GHz Wi-Fi network, or an Ethernet cable to the router.
- [ ] An SSH key on your Mac, in `~/.ssh/id_ed25519.pub`. Create it with `ssh-keygen -t ed25519` if you do not have one.
- [ ] Docker Desktop on your Mac, only for the Beszel dashboard.

## 1. Tailscale

- [ ] [Install Tailscale](https://tailscale.com/download) on your Mac and sign in. AlaVista is only reachable from your tailnet, so install it on your phone too if you want to open AlaVista from it.
- [ ] In the [DNS settings](https://login.tailscale.com/admin/dns), enable MagicDNS and HTTPS certificates, and note down the tailnet DNS name.
- [ ] Add the tags and rules of the [deployment guide](README.md#1-tailscale) to the [access controls](https://login.tailscale.com/admin/acls).
- [ ] Create an [OAuth client](https://login.tailscale.com/admin/settings/oauth) for GitHub, with the `auth_keys` write scope and the `tag:ci` tag. Keep its ID and secret for step 8.

## 2. Google sign-in (optional)

Without it, AlaVista runs but nobody can sign in to the admin.

- [ ] In the [Google Cloud console](https://console.cloud.google.com/), create a project, such as `AlaVista`.
- [ ] In [Google Auth Platform](https://console.cloud.google.com/auth/overview), select **Get started**. Give the app a name, choose your account as the support email and **External** as the audience.
- [ ] In **Audience**, add your Google account to the test users. While the app is in testing, only test users can sign in, which is enough for the admin.
- [ ] In **Clients**, create a client of the **Web application** type, with the authorized redirect URI `https://alavista.<tailnet>/connect/google/check`. Copy the client ID and the secret right away.
- [ ] In `deploy/raspberry/flash.env.local`, fill in `ADMIN_EMAILS` with your Google account, and `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.

## 3. Notifications

- [ ] Install the [ntfy app](https://ntfy.sh) on your phone, or open its [web app](https://ntfy.sh/app).
- [ ] Subscribe to the topic in `NTFY_TOPIC` of `deploy/raspberry/flash.env.local`, on the `ntfy.sh` server.

## 4. Monitoring with Beszel (optional)

- [ ] Start the dashboard on your Mac, then open <http://localhost:8090> and create your account:

  ```console
  docker compose -f deploy/raspberry/beszel/compose.yaml up -d
  ```

- [ ] Select **Add system**, with `alavista` as name, `alavista.<tailnet>` as host and `45876` as port. Copy the public key to `BESZEL_KEY` in `deploy/raspberry/flash.env.local`, then add the system. It shows as down until the Pi is up.

## 5. Write the SD card

- [ ] Fill in `WIFI_SSID` and `WIFI_PASSWORD` in `deploy/raspberry/flash.env.local`, or leave them empty to use Ethernet.
- [ ] Generate an [auth key](https://login.tailscale.com/admin/settings/keys) for the Pi: pre-approved, with the `tag:alavista` tag, not reusable and with an expiry of one day.
- [ ] Update `main`. The Pi deploys the image of the commit you are on, which the CI must have built:

  ```console
  git switch main && git pull
  ```

- [ ] Insert the SD card in your Mac and run `flash.sh`. Paste the auth key, type the disk of the SD card and your password when it asks for them:

  ```console
  deploy/raspberry/flash.sh
  ```

- [ ] Wait until it says `Done`. It ejects the SD card.

## 6. First boot

- [ ] Insert the SD card in the Pi, plug in the Ethernet cable if you use it, and connect the power supply.
- [ ] Wait for the _Setting up AlaVista_ notification, a few minutes later.
- [ ] Wait for the _AlaVista is up_ notification, about half an hour later. If you get _AlaVista setup failed_ or nothing at all, see [what to do](startup.md#notifications).

## 7. Check that it works

- [ ] Open `https://alavista.<tailnet>` on your Mac: the browser shows the sign-in page without certificate warnings.
- [ ] Sign in with Google, and check that you reach the admin.
- [ ] In the Beszel dashboard, check that `alavista` is up.
- [ ] Check that the power supply is enough. Any value other than `throttled=0x0` means under-voltage or overheating:

  ```console
  ssh <your user>@alavista.local vcgencmd get_throttled
  ```

## 8. Deploy every push from GitHub

- [ ] Create the `raspberry` environment, its secrets and the variable that enables the deployment. Each `gh secret set` asks for the value:

  ```console
  gh api --method PUT 'repos/{owner}/{repo}/environments/raspberry'
  gh secret set TS_OAUTH_CLIENT_ID --env raspberry
  gh secret set TS_OAUTH_SECRET --env raspberry
  gh secret set PI_HOST --env raspberry --body alavista.<tailnet>
  gh variable set RASPBERRY_DEPLOY_ENABLED --body true
  ```

- [ ] Test the deployment from GitHub with the current commit, and follow it until it finishes:

  ```console
  gh workflow run deploy.yaml -f image_tag="sha-$(git rev-parse HEAD | cut -c1-7)"
  gh run watch
  ```

From then on, the CI tests, builds and deploys every push to `main`, and rolls back by itself if the new version does not start.

## Later

- **Roll back by hand:** run the Deploy workflow from the Actions tab with an older `sha-<commit>` tag.
- **Start from scratch:** remove the `alavista` machine from the [Tailscale admin console](https://login.tailscale.com/admin/machines) and repeat from step 5, with a new auth key. The database starts empty.
