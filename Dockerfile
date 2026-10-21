FROM mirror.gcr.io/library/debian:13.7 AS base

LABEL maintainers=""
LABEL org.opencontainers.image.source=https://github.com/CanastaWiki/CanastaBase

ARG MW_VERSION=REL1_43
ARG MW_CORE_VERSION=1.43.12

ENV MW_VERSION=${MW_VERSION} \
	MW_CORE_VERSION=${MW_CORE_VERSION} \
	WWW_ROOT=/var/www/mediawiki \
	MW_HOME=/var/www/mediawiki/w \
	MW_LOG=/var/log/mediawiki \
	MW_ORIGIN_FILES=/mw_origin_files \
	MW_VOLUME=/mediawiki \
	WWW_USER=www-data \
    WWW_GROUP=www-data \
    LINKS_USER=canasta-links \
    APACHE_LOG_DIR=/var/log/apache2

LABEL wiki.canasta.mediawiki.version="$MW_CORE_VERSION" \
      wiki.canasta.mediawiki.branch="$MW_VERSION"

# Cache-bust the package-refresh layer below so a rebuild actually pulls current
# Debian security updates instead of reusing a stale cached apt layer. CI passes a
# value that changes daily (APT_REFRESH build-arg); when it changes, this layer and
# everything after it rebuild against current mirrors. Referencing it inside the RUN
# is what makes it part of the layer's cache key.
ARG APT_REFRESH=unset

# System setup
# Pinning system package versions is impractical on Debian
# hadolint ignore=DL3008
RUN set -x; \
	echo "apt refresh token: ${APT_REFRESH}" \
	&& apt-get clean \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends aptitude \
	&& aptitude -y upgrade \
	&& aptitude install -y --without-recommends \
	git \
	inotify-tools \
	apache2 \
	gpg \
	ca-certificates \
	wget \
	lsb-release \
	poppler-utils \
	imagemagick  \
	librsvg2-bin \
	ghostscript \
	python3-pygments \
	patch \
	vim \
	mc \
	ffmpeg \
	curl \
	iputils-ping \
	unzip \
	gnupg \
	default-mysql-client \
	rsync \
	lynx \
	php \
	php-mysql \
	php-cli \
	php-gd \
	php-mbstring \
	php-xml \
	php-intl \
	php-opcache \
	php-apcu \
	php-redis \
	php-curl \
	php-zip \
	php8.4-fpm \
	php-yaml \
	php-ldap \
	php-bcmath \
	php-luasandbox \
	libapache2-mod-fcgid \
	&& aptitude clean \
	&& rm -rf /var/lib/apt/lists/*

# Post install configuration
RUN set -x; \
	# Remove default config
	rm /etc/apache2/sites-enabled/000-default.conf \
	&& rm /etc/apache2/sites-available/000-default.conf \
	&& rm -rf /var/www/html \
	# Enable rewrite module
    && a2enmod rewrite \
	# enabling mpm_event and php-fpm
	&& a2dismod mpm_prefork \
	&& a2enconf php8.4-fpm \
	&& a2enmod mpm_event \
	&& a2enmod proxy_fcgi \
    # Create directories
    && mkdir -p "$MW_HOME" \
	&& mkdir -p "$MW_LOG" \
    && mkdir -p "$MW_ORIGIN_FILES" \
    && mkdir -p "$MW_VOLUME"

# Composer — verify the installer against the published SHA-384 before running
# it, then track the latest 2.x line instead of a long-outdated pin.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -x; \
	curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php \
	&& EXPECTED_CHECKSUM="$(curl -sS https://composer.github.io/installer.sig)" \
	&& ACTUAL_CHECKSUM="$(sha384sum /tmp/composer-setup.php | cut -d' ' -f1)" \
	&& [ "$EXPECTED_CHECKSUM" = "$ACTUAL_CHECKSUM" ] \
	&& php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
	&& rm /tmp/composer-setup.php \
	&& composer self-update --2

FROM base AS source

# MediaWiki core
# The submodules come from Gerrit, which refuses requests carrying git's
# default user agent under Wikimedia's User-Agent policy.
# cd is used within a multi-command && chain
# hadolint ignore=DL3003
RUN set -x; \
	export GIT_HTTP_USER_AGENT="CanastaBase (https://github.com/CanastaWiki/CanastaBase)" \
	&& git clone --depth 1 -b "$MW_CORE_VERSION" https://github.com/wikimedia/mediawiki "$MW_HOME" \
	&& cd "$MW_HOME" \
	&& git submodule update --init --recursive

# Generate gitinfo.json for core, extensions, and skins so that
# Special:Version can display git commit hashes after .git is removed
# cd is used within a loop that returns to $MW_HOME
# hadolint ignore=DL3003,SC2164
RUN set -x; \
    cd "$MW_HOME" || exit \
    && for dir in . extensions/*/ skins/*/; do \
        if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then \
            cd "$MW_HOME/$dir" \
            && hash=$(git rev-parse HEAD) \
            && date=$(git log -1 --format=%ct HEAD) \
            && branch=$(git rev-parse --abbrev-ref HEAD) \
            && remote=$(git config --get remote.origin.url || echo "") \
            && printf '{"head":"%s","headSHA1":"%s","headCommitDate":"%s","branch":"%s","remoteURL":"%s"}\n' \
                "$hash" "$hash" "$date" "$branch" "$remote" \
                > gitinfo.json \
            && cd "$MW_HOME"; \
        fi; \
    done

# Cleanup all .git leftovers and the unused MediaWiki web installer.
# mw-config/ is the web installer UI; Canasta installs via maintenance/install.php
# (CLI installer), so mw-config/ is dead weight and should not be web-reachable.
# cd is used within a multi-command && chain
# hadolint ignore=DL3003
RUN set -x; \
    cd "$MW_HOME" \
    && find . \( -name ".git" -o -name ".gitignore" -o -name ".gitmodules" -o -name ".gitattributes" \) -exec rm -rf -- {} + \
    && rm -rf mw-config

# Move files around
RUN set -x; \
	# Move files to $MW_ORIGIN_FILES directory
    mv "$MW_HOME/images" "$MW_ORIGIN_FILES/" \
    && mv "$MW_HOME/cache" "$MW_ORIGIN_FILES/" \
    # Move extensions and skins to prefixed directories not intended to be volumed in
    && mv "$MW_HOME/extensions" "$MW_HOME/canasta-extensions" \
    && mv "$MW_HOME/skins" "$MW_HOME/canasta-skins" \
    # Code stays root-owned: the web server user only needs to read it
    && chown -R root:root "$MW_HOME/canasta-extensions" "$MW_HOME/canasta-skins" \
    && chmod -R u=rwX,go=rX "$MW_HOME/canasta-extensions" "$MW_HOME/canasta-skins" \
    # Create symlinks from $MW_VOLUME to the wiki root for images, cache, and public_assets directories
    && ln -s "$MW_VOLUME/images" "$MW_HOME/images" \
    && ln -s "$MW_VOLUME/cache" "$MW_HOME/cache" \
    && ln -s "$MW_VOLUME/public_assets" "$MW_HOME/public_assets"

# Create place where extensions and skins symlinks will live
RUN set -x; \
    mkdir -m 0755 "$MW_HOME/extensions/" \
    && mkdir -m 0755 "$MW_HOME/skins/"

FROM base AS final

COPY --from=source $MW_HOME $MW_HOME
COPY --from=source $MW_ORIGIN_FILES $MW_ORIGIN_FILES

# Default values
ENV MW_AUTOUPDATE=true \
	MW_MAINTENANCE_UPDATE=0 \
	APACHE_REMOTE_IP_HEADER=X-Forwarded-For \
	MW_ENABLE_JOB_RUNNER=true \
	MW_JOB_RUNNER_PAUSE=2 \
	MW_JOB_RUNNER_MEMORY_LIMIT=512M \
	MW_JOB_RUNNER_MAXTIME=60 \
	MW_JOB_RUNNER_MAXJOBS= \
	MW_ENABLE_TRANSCODER=true \
	MW_ENABLE_LOG_ROTATOR=true \
	MW_JOB_TRANSCODER_PAUSE=60 \
	MW_MAP_DOMAIN_TO_DOCKER_GATEWAY=true \
	MW_SITEMAP_PAUSE_DAYS=1 \
	MW_SITEMAP_URL_PATH=/public_assets/sitemap \
	PHP_UPLOAD_MAX_FILESIZE=10M \
	PHP_POST_MAX_SIZE=10M \
	PHP_MAX_INPUT_VARS=1000 \
	PHP_MAX_EXECUTION_TIME=60 \
	PHP_MAX_INPUT_TIME=60 \
	PHP_MEMORY_LIMIT=256M \
	PM_MAX_CHILDREN=25 \
	PM_START_SERVERS=10 \
	PM_MIN_SPARE_SERVERS=5 \
	PM_MAX_SPARE_SERVERS=15 \
	PM_MAX_REQUESTS=2500 \
	LOG_FILES_COMPRESS_DELAY=3600 \
	LOG_FILES_REMOVE_OLDER_THAN_DAYS=10

COPY _sources/configs/mediawiki.conf /etc/apache2/sites-enabled/
COPY _sources/configs/writable-dirs.conf /etc/apache2/conf-available/
COPY _sources/configs/status.conf /etc/apache2/mods-available/
COPY _sources/configs/php_error_reporting.ini _sources/configs/php_upload_max_filesize.ini _sources/configs/php_memory_limit.ini /etc/php/8.4/cli/conf.d/
COPY _sources/configs/php_error_reporting.ini _sources/configs/php_upload_max_filesize.ini _sources/configs/php_memory_limit.ini /etc/php/8.4/fpm/conf.d/
COPY _sources/configs/php_max_input_vars.ini /etc/php/8.4/fpm/conf.d/
COPY _sources/configs/php_timeouts.ini /etc/php/8.4/fpm/conf.d/
COPY _sources/configs/php-fpm-www.conf /etc/php/8.4/fpm/pool.d/www.conf
COPY _sources/scripts/*.sh /
COPY _sources/scripts/maintenance-scripts/*.sh /maintenance-scripts/
COPY _sources/scripts/*.php $MW_HOME/maintenance/
COPY _sources/scripts/extensions-skins.php /tmp/
COPY _sources/configs/robots-main.txt _sources/configs/robots.php _sources/configs/sitemap.php _sources/configs/canasta-sitemaps.php $WWW_ROOT/
COPY _sources/configs/.htaccess $WWW_ROOT/
COPY _sources/images/favicon.ico $WWW_ROOT/
COPY _sources/canasta/LocalSettings.php _sources/canasta/CanastaDefaultSettings.php _sources/canasta/canasta_sessions.sql _sources/canasta/FarmConfigLoader.php _sources/canasta/CanastaFarm404.php $MW_HOME/
COPY _sources/canasta/getMediawikiSettings.php /
COPY _sources/configs/mpm_event.conf /etc/apache2/mods-available/mpm_event.conf

RUN set -x; \
	chmod -v +x /*.sh \
	&& chmod -v +x /maintenance-scripts/*.sh \
	# The directory monitor maintains the links in extensions/ and skins/ as
	# this user, which owns only those two directories
	&& useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$LINKS_USER" \
	&& chown "$LINKS_USER:$LINKS_USER" "$MW_HOME/extensions" "$MW_HOME/skins" \
	# Comment out ErrorLog and CustomLog parameters, we use rotatelogs in mediawiki.conf for the log files
	&& sed -i 's/^\(\s*ErrorLog .*\)/# \1/g' /etc/apache2/apache2.conf \
	&& sed -i 's/^\(\s*CustomLog .*\)/# \1/g' /etc/apache2/apache2.conf \
	# Make web installer work with Canasta
	&& cp "$MW_HOME/includes/Output/NoLocalSettings.php" "$MW_HOME/includes/CanastaNoLocalSettings.php" \
	&& sed -i 's/MW_CONFIG_FILE/CANASTA_CONFIG_FILE/g' "$MW_HOME/includes/CanastaNoLocalSettings.php" \
	# Modify config
	&& sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
	&& sed -i '/<Directory \/var\/www\/>/i RewriteCond %{THE_REQUEST} \\s(.*?)\\s\nRewriteRule ^ - [E=ORIGINAL_URL:%{REQUEST_SCHEME}://%{HTTP_HOST}%1]' /etc/apache2/apache2.conf \
	&& echo "Alias /w/images/ /var/www/mediawiki/w/img_auth.php/" >> /etc/apache2/apache2.conf \
    && echo "Alias /w/images /var/www/mediawiki/w/img_auth.php" >> /etc/apache2/apache2.conf \
	# Public assets are served directly from the per-wiki filesystem
	# location at /mediawiki/public_assets/<wiki_id>/. The per-wiki
	# rewrite rules are generated at startup by config-subdir-wikis.sh
	# (which knows the wiki IDs from wikis.yaml). Here we just allow
	# Apache to serve files from that path tree.
	&& printf '\n<Directory /mediawiki/public_assets>\n    Require all granted\n    Options -Indexes\n</Directory>\n' >> /etc/apache2/apache2.conf \
	&& a2enmod expires remoteip\
	&& a2enconf writable-dirs \
	&& a2disconf other-vhosts-access-log \
	# Fail the build rather than the container start on an Apache config error
	&& apachectl -t \
	# Enable environment variables for FPM workers
	&& sed -i '/clear_env/s/^;//' /etc/php/8.4/fpm/pool.d/www.conf

COPY _sources/images/Powered-by-Canasta.png /var/www/mediawiki/w/resources/assets/

EXPOSE 80
WORKDIR $MW_HOME

# 127.0.0.1, not localhost: the name resolves to ::1 first on some
# runtimes, and wget does not retry the other family once a connection
# succeeds — so the check reached Apache over IPv6 and got MediaWiki's
# 404 instead of the status handler.
HEALTHCHECK --interval=1m --timeout=10s --start-period=5m \
	CMD wget -q --method=HEAD 127.0.0.1/server-status

# SIGWINCH is Apache's graceful stop: in-flight requests finish before it
# exits, where SIGTERM would cut them off.
STOPSIGNAL SIGWINCH

CMD ["/run-all.sh"]
