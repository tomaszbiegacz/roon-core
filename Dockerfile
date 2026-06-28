# Ubuntu LTS
FROM ubuntu:latest 

ARG ROON_UID=1010
ARG ROON_GID=1010

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    ICU_PKG="$(apt-cache search --names-only '^libicu[0-9]+$' | awk '{print $1}' | sort -V | tail -1)"; \
    test -n "${ICU_PKG}"; \
    apt-get install -y --no-install-recommends \
        ffmpeg cifs-utils alsa-utils lbzip2 tar \
        ca-certificates libfreetype6 "${ICU_PKG}"; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN groupadd --gid ${ROON_GID} roon \
    && useradd --uid ${ROON_UID} --gid roon --shell /usr/sbin/nologin --no-create-home roon

VOLUME [ "/app", "/data", "/music", "/backup" ]

ADD http://download.roonlabs.com/builds/RoonServer_linuxx64.tar.bz2 /tmp/RoonServer_linuxx64.tar.bz2
RUN mkdir -p /app \
    && tar -xf /tmp/RoonServer_linuxx64.tar.bz2 -C /app \
    && rm /tmp/RoonServer_linuxx64.tar.bz2 \
    && chown -R roon:roon /app

COPY --chown=roon:roon start.sh /start.sh
RUN chmod 755 /start.sh

USER roon

CMD ["/start.sh"]
