ARG BASE_IMAGE=ghcr.io/canastawiki/canasta-base:1.3.12
FROM ${BASE_IMAGE} AS base

LABEL maintainers=""
LABEL org.opencontainers.image.source=https://github.com/CanastaWiki/Canasta

# Uncomment this if there are any skin or extension patches
COPY patches/* /tmp/
COPY contents.yaml /tmp/
COPY VERSION /tmp/
RUN printf '%s\n%s\n' '[https://canasta.wiki/ Canasta]' "$(cat /tmp/VERSION)" > /tmp/canasta-version && rm /tmp/VERSION
RUN php /tmp/extensions-skins.php "/tmp/contents.yaml"
