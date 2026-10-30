# AlaVista

**What's flying overhead?**

AlaVista is a web app for discovering the aircraft flying near you. Open it in your browser, choose a location and a search radius, and see what's passing overhead.

The project is designed to run on a Raspberry Pi and use flight data from external APIs, without requiring an ADS-B receiver or antenna.

> **Status: planning.** This README describes the intended application. Features, setup instructions and deployment workflows will be documented as they are implemented.

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
- Automated deployment to the Raspberry Pi.

These ideas will be considered after the first usable version is running.

## Running locally

The application scaffold is not available yet. Installation, configuration and development commands will be added alongside the implementation.

## Author

[Carlos Gude](https://github.com/CarlosGude)
