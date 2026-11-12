# Prometheus + Grafana for Railway (private template)

Two Railway services built from this one repo, wired over the private network:

```
prometheus/   Prometheus, scrape config generated from env vars at startup
grafana/      Grafana, Prometheus datasource + dashboards provisioned at startup
  dashboards/ dashboard JSON, loaded into the "1mage" folder
```

Based on [pagetree/prometheus-railway](https://github.com/pagetree/prometheus-railway) and [pagetree/grafana-railway](https://github.com/pagetree/grafana-railway), with these changes:

- Both live in one repo, one service per directory (Railway Root Directory).
- Image versions are pinned (`prom/prometheus:v3.16.0`, `grafana/grafana:13.3.1`) so a redeploy never upgrades by surprise.
- `SCRAPE_TARGETS` accepts `dns+host:port`, which scrapes every replica of a service as its own target.
- Dashboards are files in `grafana/dashboards/`, provisioned on every boot, so a rebuilt Grafana comes back with them.
- Grafana refuses to start without `GF_SECURITY_ADMIN_PASSWORD` (its domain is public) and has sign-up off.
- The datasource has the fixed uid `prometheus`.

---

## Creating the template in Railway

Railway keeps templates in the dashboard, not in the repo: Workspace → **Templates** → **New Template**, then add two services from this GitHub repo with the settings below. (Or set up a project by hand once and use project **Settings → Generate Template from Project**.) The template stays private to the workspace until it is published.

### Service `prometheus-railway`

| Setting | Value |
|---|---|
| Source | this repo, branch `main` |
| Root Directory | `/prometheus` |
| Railway Config File | `/prometheus/railway.json` (the config file path does not follow the Root Directory) |
| Public networking | none, private network only |
| Volume | mount path `/prometheus` |

| Variable | Value |
|---|---|
| `PORT` | `9090` |
| `SCRAPE_TARGETS` | `api=dns+${{1mage-api.RAILWAY_PRIVATE_DOMAIN}}:4000` |
| `RETENTION_TIME` | `15d` |

### Service `grafana-railway`

| Setting | Value |
|---|---|
| Source | this repo, branch `main` |
| Root Directory | `/grafana` |
| Railway Config File | `/grafana/railway.json` |
| Public networking | HTTP, port `3000` |
| Volume | mount path `/var/lib/grafana` |

| Variable | Value |
|---|---|
| `PORT` | `3000` |
| `PROMETHEUS_URL` | `http://${{prometheus-railway.RAILWAY_PRIVATE_DOMAIN}}:${{prometheus-railway.PORT}}` |
| `GF_SECURITY_ADMIN_USER` | `admin` |
| `GF_SECURITY_ADMIN_PASSWORD` | `${{secret(32)}}` |

The service names matter: `PROMETHEUS_URL` references `prometheus-railway`, and `SCRAPE_TARGETS` references `1mage-api`, so deploy the template into the project that already runs `1mage-api` (or adjust the reference).

### After deploying

1. Grafana → Explore → Prometheus → `up{job="api"}`: one series per replica (`instance="[<ip>]:4000"`), each `1`.
2. Dashboards → folder **1mage** → **1mage-api**.

Each `railway.json` sets `watchPatterns` to its own directory, so a commit that only touches `grafana/` does not redeploy Prometheus, and the other way round.

---

## Prometheus (`prometheus/`)

| Variable | Default | Description |
|---|---|---|
| `PORT` | `9090` | Keep it `9090`; Grafana's `PROMETHEUS_URL` references it |
| `SCRAPE_TARGETS` | _(empty)_ | Space separated `label=host:port` or `label=dns+host:port` |
| `SCRAPE_DNS_RECORD_TYPE` | `AAAA` | DNS record looked up for `dns+` targets: `AAAA` (IPv6) or `A` (IPv4) |
| `SCRAPE_DNS_REFRESH_INTERVAL` | `30s` | How often `dns+` targets are looked up again |
| `SCRAPE_INTERVAL` | `15s` | How often targets are scraped |
| `EVALUATION_INTERVAL` | `15s` | How often rules are evaluated |
| `RETENTION_TIME` | `15d` | How long metrics are kept (needs the `/prometheus` volume to mean anything) |

Each `label=` entry becomes its own scrape job. Without the `dns+` prefix the host is a single static target.

### Services with more than one replica

A plain `host:port` target is one target: every scrape lands on whichever replica the connection reaches, so the replicas' counters interleave and `rate()` reads each switch as a counter reset. Prefix the host with `dns+` to scrape every replica on its own:

```
api=dns+api.railway.internal:3000
```

Prometheus resolves the name every `SCRAPE_DNS_REFRESH_INTERVAL` (a `dns_sd_configs` job) and scrapes each address as its own target. Replicas added or removed are picked up on the next lookup. Railway private DNS answers with one record per replica; use `SCRAPE_DNS_RECORD_TYPE=A` if the service only has IPv4 private networking.

Health check: `/-/healthy`.

---

## Grafana (`grafana/`)

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | Port Grafana listens on |
| `PROMETHEUS_URL` | _(empty)_ | Provisions Prometheus (uid `prometheus`) as the default datasource |
| `PROMETHEUS_SCRAPE_INTERVAL` | `15s` | The datasource's scrape interval hint; keep it equal to Prometheus `SCRAPE_INTERVAL` |
| `GF_SECURITY_ADMIN_USER` | `admin` | Admin username |
| `GF_SECURITY_ADMIN_PASSWORD` | _(required)_ | Admin password; use a Railway generated secret |

Any other `GF_*` variable is passed through to Grafana unchanged.

### Changing a dashboard

Provisioned dashboards are read-only in the UI (`allowUiUpdates: false`); the file in `grafana/dashboards/` is the source of truth. To change one:

1. In Grafana, open the dashboard → Edit → change it → **Save as copy** (or edit in place and discard).
2. Export → **Export as JSON** (do not tick "Export for sharing externally").
3. Replace `grafana/dashboards/<name>.json`, drop the top-level `id` and `version`, keep `uid`.
4. Commit. Grafana picks the file up on the next deploy.

A new dashboard is a new `.json` file in the same folder with its own `uid`.

Health check: `/api/health`.

---

## Volumes

Attach volumes in the Railway dashboard (project canvas → right-click the service → **Attach Volume**), not with a Dockerfile `VOLUME` instruction, which Railway rejects. Without them, a redeploy wipes Prometheus' metrics and Grafana's users, sessions and anything not provisioned from files.
