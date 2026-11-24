# CI builds on the canasta-base it builds from the top-level Dockerfile in the
# same run; a build outside CI uses the latest published canasta-base.
ARG BASE_IMAGE=ghcr.io/canastawiki/canasta-base:latest
FROM ${BASE_IMAGE} AS base

LABEL maintainers=""
LABEL org.opencontainers.image.source=https://github.com/CanastaWiki/Canasta

COPY extended/contents.yaml /tmp/
RUN php /tmp/extensions-skins.php "/tmp/contents.yaml"
COPY VERSION /tmp/
RUN printf '%s\n%s\n' '[https://canasta.wiki/ Canasta]' "$(cat /tmp/VERSION)" > /tmp/canasta-version && rm /tmp/VERSION
