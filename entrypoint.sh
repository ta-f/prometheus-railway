#!/bin/sh
set -e

SCRAPE_INTERVAL="${SCRAPE_INTERVAL:-15s}"
EVALUATION_INTERVAL="${EVALUATION_INTERVAL:-15s}"
RETENTION_TIME="${RETENTION_TIME:-15d}"
LISTEN_PORT="${PORT:-9090}"

# Extra scrape targets:
# Format: "label=host:port label2=dns+host2:port2"
# Example: "myapp=myapp.railway.internal:8080 api=dns+api.railway.internal:3000"
# A `dns+` host is discovered through DNS: every address it resolves to (one per replica) is its own target.
SCRAPE_TARGETS="${SCRAPE_TARGETS:-}"
SCRAPE_DNS_RECORD_TYPE="${SCRAPE_DNS_RECORD_TYPE:-AAAA}"
SCRAPE_DNS_REFRESH_INTERVAL="${SCRAPE_DNS_REFRESH_INTERVAL:-30s}"

CONFIG_FILE="/etc/prometheus/prometheus.yml"

cat > "$CONFIG_FILE" <<EOF
global:
  scrape_interval:     ${SCRAPE_INTERVAL}
  evaluation_interval: ${EVALUATION_INTERVAL}

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${LISTEN_PORT}']
EOF

if [ -n "$SCRAPE_TARGETS" ]; then
  for target in $SCRAPE_TARGETS; do
    JOB_NAME="${target%%=*}"
    HOST="${target#*=}"
    case "$HOST" in
      dns+*)
        # One target per address the name resolves to, so every replica is scraped on its own
        DNS_HOST="${HOST#dns+}"
        DNS_NAME="${DNS_HOST%:*}"
        DNS_PORT="${DNS_HOST##*:}"
        if [ "$DNS_NAME" = "$DNS_HOST" ] || [ -z "$DNS_PORT" ]; then
          echo "SCRAPE_TARGETS: '${target}' needs a port, e.g. ${JOB_NAME}=dns+${DNS_HOST}:8080" >&2
          exit 1
        fi
        cat >> "$CONFIG_FILE" <<EOF

  - job_name: '${JOB_NAME}'
    dns_sd_configs:
      - names: ['${DNS_NAME}']
        type: ${SCRAPE_DNS_RECORD_TYPE}
        port: ${DNS_PORT}
        refresh_interval: ${SCRAPE_DNS_REFRESH_INTERVAL}
EOF
        ;;
      *)
        cat >> "$CONFIG_FILE" <<EOF

  - job_name: '${JOB_NAME}'
    static_configs:
      - targets: ['${HOST}']
EOF
        ;;
    esac
  done
fi

echo "──────────────────────────────────────"
echo " Prometheus starting"
echo " Scrape interval : ${SCRAPE_INTERVAL}"
echo " Retention       : ${RETENTION_TIME}"
echo " Listen port     : ${LISTEN_PORT}"
echo " Config file     :"
cat "$CONFIG_FILE"
echo "──────────────────────────────────────"

exec /bin/prometheus \
  --config.file="$CONFIG_FILE" \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time="${RETENTION_TIME}" \
  --web.console.libraries=/usr/share/prometheus/console_libraries \
  --web.console.templates=/usr/share/prometheus/consoles \
  --web.listen-address="0.0.0.0:${LISTEN_PORT}"
