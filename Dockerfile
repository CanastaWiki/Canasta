ARG BASE_IMAGE=ghcr.io/canastawiki/canasta-base:1.0.7
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

# Dirty hack for Semantic MediaWiki
RUN set -x; \
	sed -i "s/#wfLoadExtension('SemanticMediaWiki');/#enableSemantics('localhost');/g" $MW_ORIGIN_FILES/installedExtensions.txt

# Maintenance scripts for specific extensions
COPY cirrus-search-maintenance.sh _sources/scripts/maintenance-scripts/
COPY getSMWSettings.php _sources/canasta/
COPY smw-maintenance.sh _sources/scripts/maintenance-scripts/

# Create sitemap directory for web-accessible sitemaps
RUN mkdir -p /var/www/mediawiki/w/sitemap && \
    chmod 755 /var/www/mediawiki/w/sitemap
