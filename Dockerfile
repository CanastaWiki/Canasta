FROM debian:11.5 as base

LABEL maintainers=""
LABEL org.opencontainers.image.source=https://github.com/CanastaWiki/Canasta

ENV MW_VERSION=REL1_39 \
	MW_CORE_VERSION=1.39.0-rc.1 \
	WWW_ROOT=/var/www/mediawiki \
	MW_HOME=/var/www/mediawiki/w \
	MW_ORIGIN_FILES=/mw_origin_files \
	MW_VOLUME=/mediawiki \
	WWW_USER=www-data \
    WWW_GROUP=www-data \
    APACHE_LOG_DIR=/var/log/apache2

# System setup
RUN set x; \
	apt-get clean \
	&& apt-get update \
	&& apt-get install -y aptitude \
	&& aptitude -y upgrade \
	&& aptitude install -y \
	git \
	apache2 \
	software-properties-common \
	gpg \
	apt-transport-https \
	ca-certificates \
	wget \
	imagemagick  \
	librsvg2-bin \
	python3-pygments \
	msmtp \
	msmtp-mta \
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
	poppler-utils \
	&& aptitude update \
	&& aptitude install -y \
	php7.4 \
	php7.4-mysql \
	php7.4-cli \
	php7.4-gd \
	php7.4-mbstring \
	php7.4-xml \
	php7.4-mysql \
	php7.4-intl \
	php7.4-opcache \
	php7.4-apcu \
	php7.4-redis \
	php7.4-curl \
	php7.4-zip \
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
    # Create directories
    && mkdir -p $MW_HOME \
    && mkdir -p $MW_ORIGIN_FILES \
    && mkdir -p $MW_VOLUME

# Composer
RUN set -x; \
	curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer self-update 2.1.3

FROM base as source

# MediaWiki Core
RUN set -x; \
	git clone --depth 1 -b $MW_CORE_VERSION https://gerrit.wikimedia.org/r/mediawiki/core.git $MW_HOME \
	&& cd $MW_HOME \
	&& git submodule update --init --recursive \
    # VisualEditor
    && cd extensions/VisualEditor \
    && git submodule update --init

# Skins
# The MonoBook, Timeless and Vector skins are bundled into MediaWiki and do not need to be separately installed.
# The Chameleon skin is downloaded via Composer and also does not need to be installed.
RUN set -x; \
	cd $MW_HOME/skins \
	# CologneBlue
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/CologneBlue $MW_HOME/skins/CologneBlue \
	&& cd $MW_HOME/skins/CologneBlue \
	&& git checkout -q 4d588eb78d7e64e574f631c5897579537305437d \
	# MinervaNeue
	#&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/MinervaNeue $MW_HOME/skins/MinervaNeue \
	#&& cd $MW_HOME/skins/MinervaNeue \
	#&& git checkout -q e4741ff2c4375c2befee0d9f350aff6eb6e1a4da \
	# Modern
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/Modern $MW_HOME/skins/Modern \
	&& cd $MW_HOME/skins/Modern \
	&& git checkout -q fb6c2831b5f150e9b82d98d661710695a2d0f8f2 \
	# Pivot
	&& git clone -b v2.3.0 https://github.com/wikimedia/mediawiki-skins-Pivot $MW_HOME/skins/pivot \
	&& cd $MW_HOME/skins/pivot \
	&& git checkout -q d79af7514347eb5272936243d4013118354c85c1 \
	# Refreshed
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/Refreshed $MW_HOME/skins/Refreshed \
	&& cd $MW_HOME/skins/Refreshed \
	&& git checkout -q 86f33620f25335eb62289aa18d342ff3b980d8b8

# Composer dependencies
COPY _sources/configs/composer.canasta.json $MW_HOME/composer.local.json
RUN set -x; \
	cd $MW_HOME \
	&& composer update --no-dev \
	# We need the 2nd update for SMW dependencies
	&& composer update --no-dev \
    # Fix up future use of canasta-extensions directory for composer autoload
    && sed -i 's/extensions/canasta-extensions/g' $MW_HOME/vendor/composer/autoload_static.php \
    && sed -i 's/extensions/canasta-extensions/g' $MW_HOME/vendor/composer/autoload_files.php \
    && sed -i 's/extensions/canasta-extensions/g' $MW_HOME/vendor/composer/autoload_classmap.php \
    && sed -i 's/extensions/canasta-extensions/g' $MW_HOME/vendor/composer/autoload_psr4.php \
    && sed -i 's/skins/canasta-skins/g' $MW_HOME/vendor/composer/autoload_static.php \
    && sed -i 's/skins/canasta-skins/g' $MW_HOME/vendor/composer/autoload_files.php \
    && sed -i 's/skins/canasta-skins/g' $MW_HOME/vendor/composer/autoload_classmap.php \
    && sed -i 's/skins/canasta-skins/g' $MW_HOME/vendor/composer/autoload_psr4.php

# Patches


# TODO send to upstream, see https://wikiteq.atlassian.net/browse/MW-64 and https://wikiteq.atlassian.net/browse/MW-81
#COPY _sources/patches/skin-refreshed.patch /tmp/skin-refreshed.patch
#RUN set -x; \
#	cd $MW_HOME/skins/Refreshed \
#	&& patch -u -b includes/RefreshedTemplate.php -i /tmp/skin-refreshed.patch

# Allow to modify headelement in the Vector skin, see https://wikiteq.atlassian.net/browse/FAM-7
#COPY _sources/patches/skin-vector-addVectorGeneratedSkinDataHook.patch /tmp/skin-vector-addVectorGeneratedSkinDataHook.patch
#RUN set -x; \
#	cd $MW_HOME/skins/Vector \
#	&& git apply /tmp/skin-vector-addVectorGeneratedSkinDataHook.patch


# WikiTeq's patch allowing to manage fields visibility site-wide
#COPY _sources/patches/SocialProfile-disable-fields.patch /tmp/SocialProfile-disable-fields.patch
#RUN set -x; \
#    cd $MW_HOME/extensions/SocialProfile \
#    && git apply /tmp/SocialProfile-disable-fields.patch

#COPY _sources/patches/bootstrap-path.patch /tmp/bootstrap-path.patch
#RUN set -x; \
#    cd $MW_HOME/extensions/Bootstrap \
#    && patch -p1 < /tmp/bootstrap-path.patch

#COPY _sources/patches/chameleon-path.patch /tmp/chameleon-path.patch
#RUN set -x; \
#    cd $MW_HOME/skins/chameleon \
#    && git apply /tmp/chameleon-path.patch


# Cleanup all .git leftovers
RUN set -x; \
    cd $MW_HOME \
    && find . \( -name ".git" -o -name ".gitignore" -o -name ".gitmodules" -o -name ".gitattributes" \) -exec rm -rf -- {} +

# Generate list of installed extensions
RUN set -x; \
	cd $MW_HOME/extensions \
    && for i in $(ls -d */); do echo "#cfLoadExtension('${i%%/}');"; done > $MW_ORIGIN_FILES/installedExtensions.txt \
    # Dirty hack for SemanticMediawiki
    && sed -i "s/#cfLoadExtension('SemanticMediaWiki');/#enableSemantics('localhost');/g" $MW_ORIGIN_FILES/installedExtensions.txt \
    && cd $MW_HOME/skins \
    && for i in $(ls -d */); do echo "#cfLoadSkin('${i%%/}');"; done > $MW_ORIGIN_FILES/installedSkins.txt \
    #Loads Vector skin by default in the LocalSettings.php
    && sed -i "s/#cfLoadSkin('Vector');/cfLoadSkin('Vector');/" $MW_ORIGIN_FILES/installedSkins.txt

# Move files around
RUN set -x; \
	# Move files to $MW_ORIGIN_FILES directory
    mv $MW_HOME/images $MW_ORIGIN_FILES/ \
    && mv $MW_HOME/cache $MW_ORIGIN_FILES/ \
    # Move extensions and skins to prefixed directories not intended to be volumed in
    && mv $MW_HOME/extensions $MW_HOME/canasta-extensions \
    && mv $MW_HOME/skins $MW_HOME/canasta-skins \
    # Permissions
    && chown $WWW_USER:$WWW_GROUP -R $MW_HOME/canasta-extensions \
    && chmod g+w -R $MW_HOME/canasta-extensions \
    && chown $WWW_USER:$WWW_GROUP -R $MW_HOME/canasta-skins \
    && chmod g+w -R $MW_HOME/canasta-skins \
    # Create symlinks from $MW_VOLUME to the wiki root for images and cache directories
    && ln -s $MW_VOLUME/images $MW_HOME/images \
    && ln -s $MW_VOLUME/cache $MW_HOME/cache

# Create place where extensions and skins symlinks will live
RUN set -x; \
    mkdir $MW_HOME/extensions/ \
    && mkdir $MW_HOME/skins/

FROM base as final

COPY --from=source $MW_HOME $MW_HOME
COPY --from=source $MW_ORIGIN_FILES $MW_ORIGIN_FILES

# Default values
ENV MW_ENABLE_JOB_RUNNER=true \
	MW_JOB_RUNNER_PAUSE=2 \
	MW_ENABLE_TRANSCODER=true \
	MW_JOB_TRANSCODER_PAUSE=60 \
	MW_ENABLE_SITEMAP_GENERATOR=false \
	MW_SITEMAP_PAUSE_DAYS=1 \
	MW_SITEMAP_SUBDIR="" \
	MW_SITEMAP_IDENTIFIER="mediawiki" \
	PHP_UPLOAD_MAX_FILESIZE=10M \
	PHP_POST_MAX_SIZE=10M \
	PHP_MAX_INPUT_VARS=1000 \
	PHP_MAX_EXECUTION_TIME=60 \
	PHP_MAX_INPUT_TIME=60 \
	LOG_FILES_COMPRESS_DELAY=3600 \
	LOG_FILES_REMOVE_OLDER_THAN_DAYS=10

COPY _sources/configs/msmtprc /etc/
COPY _sources/configs/mediawiki.conf /etc/apache2/sites-enabled/
COPY _sources/configs/status.conf /etc/apache2/mods-available/
COPY _sources/configs/php_error_reporting.ini _sources/configs/php_upload_max_filesize.ini /etc/php/7.4/cli/conf.d/
COPY _sources/configs/php_error_reporting.ini _sources/configs/php_upload_max_filesize.ini /etc/php/7.4/apache2/conf.d/
COPY _sources/configs/php_max_input_vars.ini _sources/configs/php_max_input_vars.ini /etc/php/7.4/apache2/conf.d/
COPY _sources/configs/php_timeouts.ini /etc/php/7.4/apache2/conf.d/
COPY _sources/scripts/*.sh /
COPY _sources/scripts/*.php $MW_HOME/maintenance/
COPY _sources/configs/robots.txt $WWW_ROOT/
COPY _sources/configs/.htaccess $WWW_ROOT/
COPY _sources/images/favicon.ico $WWW_ROOT/
COPY _sources/canasta/LocalSettings.php _sources/canasta/CanastaUtils.php _sources/canasta/CanastaDefaultSettings.php $MW_HOME/
COPY _sources/canasta/getMediawikiSettings.php /
COPY _sources/configs/mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf

RUN set -x; \
	chmod -v +x /*.sh \
	# Sitemap directory
	&& ln -s $MW_VOLUME/sitemap $MW_HOME/sitemap \
	# Comment out ErrorLog and CustomLog parameters, we use rotatelogs in mediawiki.conf for the log files
	&& sed -i 's/^\(\s*ErrorLog .*\)/# \1/g' /etc/apache2/apache2.conf \
	&& sed -i 's/^\(\s*CustomLog .*\)/# \1/g' /etc/apache2/apache2.conf \
    # Make web installer work with Canasta
    && cp "$MW_HOME/includes/NoLocalSettings.php" "$MW_HOME/includes/CanastaNoLocalSettings.php" \
    && sed -i 's/MW_CONFIG_FILE/CANASTA_CONFIG_FILE/g' "$MW_HOME/includes/CanastaNoLocalSettings.php" \
    # Modify config
    && sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
    && a2enmod expires

COPY _sources/images/Powered-by-Canasta.png /var/www/mediawiki/w/resources/assets/

EXPOSE 80
WORKDIR $MW_HOME

HEALTHCHECK --interval=1m --timeout=10s \
	CMD wget -q --method=HEAD localhost/w/api.php

CMD ["/run-apache.sh"]
