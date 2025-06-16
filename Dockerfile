FROM ghcr.io/canastawiki/canasta-base AS base

LABEL maintainers=""
LABEL org.opencontainers.image.source=https://github.com/CanastaWiki/Canasta_1.43

# Uncomment this if there are any skin or extension patches
# COPY _sources/patches/* /tmp/
COPY contents.yaml /tmp/
RUN php /tmp/extensions-skins.php "/tmp/contents.yaml"

# Default values
ENV MW_MAINTENANCE_CIRRUSSEARCH_UPDATECONFIG=2 \
	MW_MAINTENANCE_CIRRUSSEARCH_FORCEINDEX=2

# Dirty hack for Semantic MediaWiki
RUN set -x; \
	sed -i "s/#wfLoadExtension('SemanticMediaWiki');/#enableSemantics('localhost');/g" $MW_ORIGIN_FILES/installedExtensions.txt

# Maintenance scripts for specific extensions
COPY cirrus-search-maintenance.sh _sources/scripts/maintenance-scripts/
COPY getSMWSettings.php _sources/canasta/
COPY smw-maintenance.sh _sources/scripts/maintenance-scripts/
