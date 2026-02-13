ARG BASE_IMAGE=ghcr.io/canastawiki/canasta-base:1.1.0
FROM ${BASE_IMAGE} AS base

LABEL maintainers=""
LABEL org.opencontainers.image.source=https://github.com/CanastaWiki/Canasta

# Uncomment this if there are any skin or extension patches
COPY patches/* /tmp/
COPY contents.yaml /tmp/
RUN php /tmp/extensions-skins.php "/tmp/contents.yaml"

# Default values
ENV MW_MAINTENANCE_CIRRUSSEARCH_UPDATECONFIG=2 \
	MW_MAINTENANCE_CIRRUSSEARCH_FORCEINDEX=2

# Maintenance scripts for specific extensions
COPY cirrus-search-maintenance.sh /_sources/scripts/maintenance-scripts/
COPY getSMWSettings.php /_sources/canasta/
COPY smw-maintenance.sh /_sources/scripts/maintenance-scripts/
