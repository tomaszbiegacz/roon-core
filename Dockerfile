# Ubuntu LTS
FROM --platform=linux/amd64 ubuntu:latest 

ARG ROON_UID=1010
ARG ROON_GID=1010

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    ICU_PKG="$(apt-cache search --names-only '^libicu[0-9]+$' | awk '{print $1}' | sort -V | tail -1)"; \
    test -n "${ICU_PKG}"; \
    apt-get install -y --no-install-recommends \
        ffmpeg tzdata cifs-utils alsa-utils lbzip2 tar \
        ca-certificates libfreetype6 "${ICU_PKG}"; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN groupadd --gid ${ROON_GID} roon \
    && useradd --uid ${ROON_UID} --gid roon --shell /usr/sbin/nologin --no-create-home roon

VOLUME [ "/app", "/data", "/music", "/backup" ]

# Informational only — requires --net=host for multicast discovery
EXPOSE 9003/udp 9100-9200/tcp 9200-9250/tcp 9330-9339/tcp 55000/tcp

ADD http://download.roonlabs.com/builds/RoonServer_linuxx64.tar.bz2 /tmp/RoonServer_linuxx64.tar.bz2
RUN mkdir -p /app \
    && tar -xf /tmp/RoonServer_linuxx64.tar.bz2 -C /app \
    && rm /tmp/RoonServer_linuxx64.tar.bz2 \
    && chown -R roon:roon /app

COPY --chown=roon:roon start.sh /start.sh
RUN chmod 755 /start.sh

# Healthcheck uses /proc directly instead of pgrep to avoid procps dependency
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD grep -ql '[R]oonServer.dll' /proc/[0-9]*/cmdline 2>/dev/null || exit 1

USER roon

CMD ["/start.sh"]
