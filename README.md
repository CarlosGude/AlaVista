# AlaVista

**What's flying overhead?**

AlaVista is a web app for discovering the aircraft flying near you. Open it in your browser, choose a location and a search radius, and see what's passing overhead.

The project is designed to run on a Raspberry Pi and use flight data from external APIs, without requiring an ADS-B receiver or antenna.

> **Status: planning.** This README describes the intended application. The local environment and the automated deployment to the Raspberry Pi are in place, and features will be documented as they are implemented.

## First version

- [ ] Choose a location manually or use browser geolocation.
- [ ] Set a search radius.
- [ ] Display nearby aircraft on a map and in a list.
- [ ] Show callsign, altitude, speed and heading when available.
- [ ] Refresh aircraft positions periodically and show when the data was last updated.
- [ ] Handle unavailable or stale flight data explicitly.

## Planned stack

| Component                    | Technology                                                           |
| ---------------------------- | -------------------------------------------------------------------- |
| Backend                      | PHP, Symfony and FrankenPHP                                          |
| Web interface                | Twig with JavaScript for the map and browser interactions            |
| External API integration     | [IntegrationEngine](https://github.com/CarlosGude/integrationEngine) |
| Development environment      | Docker Compose and Xdebug                                            |
| CI and deployment automation | GitHub Actions                                                       |
| Deployment target            | Raspberry Pi 3 Model B                                               |

## Flight data

The data provider has not been selected yet. The first technical milestone is to validate coverage, update frequency, rate limits and usage terms for the intended deployment.

The application will consume aircraft positions reported by that provider. Coverage and freshness will depend on the source; it will not detect every aircraft or provide continuous, real-time tracking.

Route, airline and aircraft details may be added where the selected data sources make them available.

## Approach

External flight data will be mapped into an application model behind a gateway, keeping provider-specific formats outside the proximity and display logic.

The initial scope is a small application for personal use: one location, a configurable radius and a clear view of nearby aircraft.

## Later ideas

- Notifications when an aircraft enters the selected area.
- Aircraft and airline details.
- Progressive Web App support.

These ideas will be considered after the first usable version is running.

## Running locally

The development environment runs on Docker Compose: FrankenPHP with Symfony, and PostgreSQL. You need Docker, and ports 80 and 443 free.

1. Build the images and start the containers. The first build takes a few minutes:

   ```console
   docker compose build --pull
   docker compose up --wait
   ```

2. Open <https://localhost> and accept the self-signed certificate. To trust it once and for all on macOS:

   ```console
   docker compose cp php:/data/caddy/pki/authorities/local/root.crt /tmp/alavista-root.crt
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/alavista-root.crt
   ```

The migrations run when the php container starts. The code is mounted in the container, and FrankenPHP reloads it when it changes.

To sign in to the admin at <https://localhost/admin>, create a `.env.local` file, which Git ignores, with your Google account and a Google OAuth client. Add `https://localhost/connect/google/check` to the authorized redirect URIs of the client:

```shell
ADMIN_EMAILS=you@example.com
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
```

Other tasks:

- **Console:** `docker compose exec php bin/console <command>`, such as `make:migration`.
- **Tests:** create the test database the first time, and migrate it after each new migration. Then run PHPUnit and Behat:

  ```console
  docker compose exec php bin/console -e test doctrine:database:create --if-not-exists
  docker compose exec php bin/console -e test doctrine:migrations:migrate --no-interaction
  docker compose exec php bin/phpunit
  docker compose exec php vendor/bin/behat
  ```

- **Debugging:** Xdebug is off by default, because in worker mode it connects on every request. Start the containers with `XDEBUG_MODE=develop,debug docker compose up --wait`, and in PhpStorm, create a server named `alavista` that maps the project directory to `/app`.
- **Other ports:** if 80 or 443 are taken, start it with `HTTP_PORT=8000 HTTPS_PORT=8443 HTTP3_PORT=8443 docker compose up --wait` and open <https://localhost:8443>.
- **Stop:** `docker compose down --remove-orphans`.

## Deployment

Every push to `main` that passes the CI is deployed to a Raspberry Pi over Tailscale. The [deployment guide](deploy/raspberry/README.md) explains how it works, and [`steps.md`](deploy/raspberry/steps.md) lists every step to set up the Pi from scratch.

## Author

[Carlos Gude](https://github.com/CarlosGude)
