FROM grafana/grafana:13.3.1

USER root

COPY provisioning/ /etc/grafana/provisioning/
COPY dashboards/ /etc/grafana/dashboards/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
