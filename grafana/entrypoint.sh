#!/bin/sh
set -e

GF_SECURITY_ADMIN_USER="${GF_SECURITY_ADMIN_USER:-admin}"
GF_SECURITY_ADMIN_PASSWORD="${GF_SECURITY_ADMIN_PASSWORD:-}"
PROMETHEUS_URL="${PROMETHEUS_URL:-}"
LISTEN_PORT="${PORT:-3000}"

# The domain is public: never start with Grafana's default admin/admin
if [ -z "$GF_SECURITY_ADMIN_PASSWORD" ]; then
  echo "GF_SECURITY_ADMIN_PASSWORD is required" >&2
  exit 1
fi

DATASOURCES_DIR="/etc/grafana/provisioning/datasources"
mkdir -p "$DATASOURCES_DIR"

# A fixed uid keeps dashboard links and alert rules stable across redeploys
if [ -n "$PROMETHEUS_URL" ]; then
  cat > "${DATASOURCES_DIR}/prometheus.yml" <<YAML
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: ${PROMETHEUS_URL}
    isDefault: true
    editable: false
    jsonData:
      httpMethod: POST
      timeInterval: ${PROMETHEUS_SCRAPE_INTERVAL:-15s}
YAML
  echo "Prometheus datasource -> ${PROMETHEUS_URL}"
else
  echo "PROMETHEUS_URL is not set; no datasource provisioned" >&2
fi

echo "──────────────────────────────────────"
echo " Grafana starting"
echo " Admin user : ${GF_SECURITY_ADMIN_USER}"
echo " Port       : ${LISTEN_PORT}"
echo " Dashboards : $(ls /etc/grafana/dashboards | tr '\n' ' ')"
echo "──────────────────────────────────────"

export GF_SECURITY_ADMIN_USER
export GF_SECURITY_ADMIN_PASSWORD
export GF_SERVER_HTTP_ADDR="0.0.0.0"
export GF_SERVER_HTTP_PORT="${LISTEN_PORT}"
export GF_ANALYTICS_REPORTING_ENABLED=false
export GF_ANALYTICS_CHECK_FOR_UPDATES=false
export GF_USERS_ALLOW_SIGN_UP=false

exec /run.sh
