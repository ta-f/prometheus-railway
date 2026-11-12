FROM prom/prometheus:v3.16.0

USER root

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9090

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
