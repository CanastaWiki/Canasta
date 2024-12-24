FROM debian:12.5 AS base

LABEL maintainers="pavel@wikiteq.com,alexey@wikiteq.com"
LABEL org.opencontainers.image.source=https://github.com/WikiTeq/Taqasta

ENV MW_VERSION=REL1_43 \
	MW_CORE_VERSION=1.43.0 \
	WWW_ROOT=/var/www/mediawiki \
	MW_HOME=/var/www/mediawiki/w \
	MW_LOG=/var/log/mediawiki \
	MW_ORIGIN_FILES=/mw_origin_files \
	MW_VOLUME=/mediawiki \
	MW_IMPORT_VOLUME=/import \
	WWW_USER=www-data \
	WWW_GROUP=www-data \
	APACHE_LOG_DIR=/var/log/apache2

# System setup
RUN set x; \
	apt-get clean \
	&& apt-get update \
	&& apt-get --no-install-recommends install -y aptitude \
	&& aptitude -y upgrade \
	&& aptitude --without-recommends install -y \
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
	nano \
	ffmpeg \
	curl \
	iputils-ping \
	unzip \
	gnupg \
	default-mysql-client \
	rsync \
	lynx \
	poppler-utils \
	lsb-release \
	&& wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg \
	&& echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list \
	&& aptitude update \
	&& aptitude install -y \
	php8.1 \
	php8.1-mysql \
	php8.1-cli \
	php8.1-gd \
	php8.1-mbstring \
	php8.1-xml \
	php8.1-mysql \
	php8.1-intl \
	php8.1-opcache \
	php8.1-apcu \
	php8.1-redis \
	php8.1-curl \
	php8.1-tidy \
	php8.1-zip \
	php8.1-tideways \
# Lua sandbox
	php-pear \
	php8.1-dev \
	liblua5.1-0 \
	liblua5.1-0-dev \
	monit \
	zip \
	weasyprint \
	pandoc \
	clamav \
	exiv2 \
	libimage-exiftool-perl \
	ploticus \
	djvulibre-bin \
	fonts-hosny-amiri \
	jq \
#	xvfb \ + 14.9 MB
#	lilypond \ + 301 MB
	&& pecl -d php_suffix=8.1 install luasandbox \
	&& pecl -d php_suffix=8.1 install excimer \
	&& aptitude -y remove php-pear php8.1-dev liblua5.1-0-dev \
	&& aptitude clean \
	&& rm -rf /var/lib/apt/lists/*

# FORCE USING PHP 8.1 (same for phar)
# For some reason sury provides other versions, see
# https://github.com/oerdnj/deb.sury.org/wiki/Frequently-Asked-Questions
RUN set -x; \
	update-alternatives --set php /usr/bin/php8.1 \
	&& update-alternatives --set phar /usr/bin/phar8.1 \
	&& update-alternatives --set phar.phar /usr/bin/phar.phar8.1

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
	&& mkdir -p $MW_LOG \
	&& mkdir -p $MW_ORIGIN_FILES \
	&& mkdir -p $MW_VOLUME

# Composer
RUN set -x; \
	curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
	&& composer self-update 2.1.3

FROM base AS core
# MediaWiki core
RUN set -x; \
	git clone --depth 1 -b $MW_CORE_VERSION https://gerrit.wikimedia.org/r/mediawiki/core.git $MW_HOME \
	&& cd $MW_HOME \
	&& git submodule update --init --recursive

# Add Bootstrap to LocalSettings.php if the web installer added the Chameleon skin
COPY _sources/patches/core-local-settings-generator.patch /tmp/core-local-settings-generator.patch
RUN set -x; \
	cd $MW_HOME \
	&& git apply /tmp/core-local-settings-generator.patch

# Cleanup all .git leftovers
RUN set -x; \
	cd $MW_HOME \
	&& find . \( -name ".git" -o -name ".gitignore" -o -name ".gitmodules" -o -name ".gitattributes" \) -exec rm -rf -- {} +

FROM base AS skins
# Skins
# The Minerva Neue, MonoBook, Timeless, Vector and Vector 2022 skins are bundled into MediaWiki and do not need to be
# separately installed.
# The Chameleon skin is downloaded via Composer and also does not need to be installed.
RUN set -x; \
	mkdir $MW_HOME/skins \
	&& cd $MW_HOME/skins \
	# CologneBlue
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/CologneBlue $MW_HOME/skins/CologneBlue \
	&& cd $MW_HOME/skins/CologneBlue \
	&& git checkout -q d7c8d45093c82460fe80c98ce9fa775315fd3e30 \
	# Modern
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/Modern $MW_HOME/skins/Modern \
	&& cd $MW_HOME/skins/Modern \
	&& git checkout -q 5597681b7f0423a7e71cda64929c9d60dc999b8c \
	# Pivot
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/Pivot $MW_HOME/skins/pivot \
	&& cd $MW_HOME/skins/pivot \
	&& git checkout -q f6b35ca2b8b07ced0e467d8b99421a41b0af3fa3 \
	# Refreshed
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/Refreshed $MW_HOME/skins/Refreshed \
	&& cd $MW_HOME/skins/Refreshed \
	&& git checkout -q 2570c3ee3996cd8ca3f766131b301c33695f68e6

# TODO send to upstream, see https://wikiteq.atlassian.net/browse/MW-64 and https://wikiteq.atlassian.net/browse/MW-81
COPY _sources/patches/skin-refreshed.patch /tmp/skin-refreshed.patch
COPY _sources/patches/skin-refreshed-737080.diff /tmp/skin-refreshed-737080.diff
RUN set -x; \
	cd $MW_HOME/skins/Refreshed \
	&& patch -u -b includes/RefreshedTemplate.php -i /tmp/skin-refreshed.patch \
	# TODO remove me when https://gerrit.wikimedia.org/r/c/mediawiki/skins/Refreshed/+/737080 merged
	# Fix PHP Warning in RefreshedTemplate::makeElementWithIconHelper()
	&& git apply /tmp/skin-refreshed-737080.diff

# Cleanup all .git leftovers
RUN set -x; \
	cd $MW_HOME/skins \
	&& find . \( -name ".git" -o -name ".gitignore" -o -name ".gitmodules" -o -name ".gitattributes" \) -exec rm -rf -- {} +

FROM base AS extensions
# Extensions
#
# The following extensions are bundled into MediaWiki and do not need to be separately installed (though in some cases
# they are modified): AbuseFilter, CategoryTree, Cite, CiteThisPage, CodeEditor, ConfirmEdit, DiscussionTools, Echo,
# Gadgets, ImageMap, InputBox, Interwiki, Linter, LoginNotify, Math, MultimediaViewer, Nuke, OATHAuth, PageImages,
# ParserFunctions, PdfHandler, Poem, ReplaceText, Scribunto, SecureLinkFixer, SpamBlacklist, SyntaxHighlight_GeSHi
# TemplateData, TextExtracts, Thanks, TitleBlacklist, VisualEditor, WikiEditor
#
# The following extensions are downloaded via Composer and also do not need to be downloaded here: Bootstrap,
# BootstrapComponents, Maps, Mermaid, Semantic Breadcrumb Links, Semantic Compound Queries, Semantic Extra Special
# Properties, Semantic MediaWiki (along with all its helper library extensions, like DataValues), Semantic Result
# Formats, Semantic Scribunto, SimpleBatchUpload, SubPageList.

# A
RUN set -x; \
	mkdir $MW_HOME/extensions \
	&& cd $MW_HOME/extensions \
	# AdminLinks (v. 0.6.1)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/AdminLinks $MW_HOME/extensions/AdminLinks \
	&& cd $MW_HOME/extensions/AdminLinks \
	&& git checkout -q 60eda7201636218b80d83a637b70e5c753900e41 \
	# AdvancedSearch
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/AdvancedSearch $MW_HOME/extensions/AdvancedSearch \
	&& cd $MW_HOME/extensions/AdvancedSearch \
	&& git checkout -q fc7079d49fba845d786d97e4980c8d8fb522bd71 \
	# AJAXPoll
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/AJAXPoll $MW_HOME/extensions/AJAXPoll \
	&& cd $MW_HOME/extensions/AJAXPoll \
	&& git checkout -q fbfd07ef43063e806026d5bd3f95493e2b189378 \
	# AntiSpoof
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/AntiSpoof $MW_HOME/extensions/AntiSpoof \
	&& cd $MW_HOME/extensions/AntiSpoof \
	&& git checkout -q 29d219c52f412d84182f979a202405664b9424e6 \
	# ApprovedRevs (v. 1.8.2)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/ApprovedRevs $MW_HOME/extensions/ApprovedRevs \
	&& cd $MW_HOME/extensions/ApprovedRevs \
	&& git checkout -q 53b67bf7e1e8ac3d20c2fd41ad2ab1c708c045a6 \
	# Arrays
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Arrays $MW_HOME/extensions/Arrays \
	&& cd $MW_HOME/extensions/Arrays \
	&& git checkout -q 96357a3708ec36ae4b6deebb63991c86268d0e2a

# B
RUN set -x; \
	cd $MW_HOME/extensions \
 	# BetaFeatures
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/BetaFeatures $MW_HOME/extensions/BetaFeatures \
	&& cd $MW_HOME/extensions/BetaFeatures \
	&& git checkout -q e2dc57ca67ca7d4188f3b921d5883ee532754724 \
	# BreadCrumbs2
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/BreadCrumbs2 $MW_HOME/extensions/BreadCrumbs2 \
	&& cd $MW_HOME/extensions/BreadCrumbs2 \
	&& git checkout -q 28e82570da8d7e9e8a422a9a3f55392cf6166e0f

# C
RUN set -x; \
	cd $MW_HOME/extensions \
	# Cargo (v. 3.5.1)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/Cargo $MW_HOME/extensions/Cargo \
	&& cd $MW_HOME/extensions/Cargo \
	&& git checkout -q a2865938165c1389d852df762f8c85073859e5dd \
	# CharInsert
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CharInsert $MW_HOME/extensions/CharInsert \
	&& cd $MW_HOME/extensions/CharInsert \
	&& git checkout -q ee7b17910ece1ebaf6ad53857926d797b0ff374d \
	# CheckUser
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CheckUser $MW_HOME/extensions/CheckUser \
	&& cd $MW_HOME/extensions/CheckUser \
	&& git checkout -q 53f7c98d3fd003aef8faf95dd08ee05139079fab \
	# CirrusSearch
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CirrusSearch $MW_HOME/extensions/CirrusSearch \
	&& cd $MW_HOME/extensions/CirrusSearch \
	&& git checkout -q 209efea8657680d855eb5495550af26ee60cea82 \
	# CodeMirror
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CodeMirror $MW_HOME/extensions/CodeMirror \
	&& cd $MW_HOME/extensions/CodeMirror \
	&& git checkout -q 5b6096aaed463519b8f99aa79fadb4498b474905 \
	# Collection
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Collection $MW_HOME/extensions/Collection \
	&& cd $MW_HOME/extensions/Collection \
	&& git checkout -q 85442735f3b05c6b92f44183d4d043f430f1e889 \
	# CommentStreams
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CommentStreams $MW_HOME/extensions/CommentStreams \
	&& cd $MW_HOME/extensions/CommentStreams \
	&& git checkout -q 25340d9d06a7547ba31d9dc4ef0ac100a48f70ed \
	# CommonsMetadata
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CommonsMetadata $MW_HOME/extensions/CommonsMetadata \
	&& cd $MW_HOME/extensions/CommonsMetadata \
	&& git checkout -q 133fd7511eff158456e194315e5f477166ef3206 \
	# ConfirmAccount
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ConfirmAccount $MW_HOME/extensions/ConfirmAccount \
	&& cd $MW_HOME/extensions/ConfirmAccount \
	&& git checkout -q de9733a4bd8a3b26a2aed6b56eab56197026d116 \
	# ContactPage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ContactPage $MW_HOME/extensions/ContactPage \
	&& cd $MW_HOME/extensions/ContactPage \
	&& git checkout -q ad2cdd6a5bb1676dd42215f7585125a78140b121 \
	# ContributionScores
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ContributionScores $MW_HOME/extensions/ContributionScores \
	&& cd $MW_HOME/extensions/ContributionScores \
	&& git checkout -q 6370730e6cec3ccff17d2ea988dd414fa87f1e16 \
	# CookieWarning
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CookieWarning $MW_HOME/extensions/CookieWarning \
	&& cd $MW_HOME/extensions/CookieWarning \
	&& git checkout -q f697459d94ac1aa8c9d3e417a9b0e04f92640447 \
	# Cloudflare
	&& git clone --single-branch -b master https://github.com/harugon/mediawiki-extensions-cloudflare.git $MW_HOME/extensions/Cloudflare \
	&& cd $MW_HOME/extensions/Cloudflare \
	&& git checkout -q 9df89f3f5e0ace26b07d146167bab72540082fc8

# D
RUN set -x; \
	cd $MW_HOME/extensions \
	# DataTransfer
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/DataTransfer $MW_HOME/extensions/DataTransfer \
	&& cd $MW_HOME/extensions/DataTransfer \
	&& git checkout -q 2cc7e74d4922c8dc375dfcc9391c1b6d21195995 \
	# DeleteBatch
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/DeleteBatch $MW_HOME/extensions/DeleteBatch \
	&& cd $MW_HOME/extensions/DeleteBatch \
	&& git checkout -q 55ec7006ba073f16942ffa91620485b8f6cfc241 \
	# Description2
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Description2 $MW_HOME/extensions/Description2 \
	&& cd $MW_HOME/extensions/Description2 \
	&& git checkout -q 50e2aef88053be12a66b617657c414a665e2d38e \
	# Disambiguator
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Disambiguator $MW_HOME/extensions/Disambiguator \
	&& cd $MW_HOME/extensions/Disambiguator \
	&& git checkout -q 56a4738b35d331fe3d3f985b9e3d1c084ab75ed9 \
	# DismissableSiteNotice
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/DismissableSiteNotice $MW_HOME/extensions/DismissableSiteNotice \
	&& cd $MW_HOME/extensions/DismissableSiteNotice \
	&& git checkout -q caca5bf6baaf5b85487a5b822e42c6ee74aa0e9d \
	# DisplayTitle
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/DisplayTitle $MW_HOME/extensions/DisplayTitle \
	&& cd $MW_HOME/extensions/DisplayTitle \
	&& git checkout -q 920768a8efb9f316aed1f134fc07aa153d612eb7 \
	# DynamicPageList3
	# TODO no 1.43 branch yet
	&& git clone --single-branch -b REL1_39 https://github.com/Universal-Omega/DynamicPageList3.git $MW_HOME/extensions/DynamicPageList3 \
	&& cd $MW_HOME/extensions/DynamicPageList3 \
	&& git checkout -q e4faf608b0f5a77c4a4c3576a2a28216c7d2bbbf

# E
RUN set -x; \
	cd $MW_HOME/extensions \
	# Editcount
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Editcount $MW_HOME/extensions/Editcount \
	&& cd $MW_HOME/extensions/Editcount \
	&& git checkout -q a81f6e9e404da0e82801fc12d91567d1cc143181 \
	# Elastica
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Elastica $MW_HOME/extensions/Elastica \
	&& cd $MW_HOME/extensions/Elastica \
	&& git checkout -q 3f2c3cad516c875091c3536d8d17b0297e8d2d87 \
	# EmailAuthorization
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/EmailAuthorization $MW_HOME/extensions/EmailAuthorization \
	&& cd $MW_HOME/extensions/EmailAuthorization \
	&& git checkout -q d14a4bb04e2004bb13023dd8a044fc530d558bb8 \
	# EmbedVideo (v. 3.4.2)
	# (Canasta uses hydrawiki, but we switched to StarCitizenWiki's fork which
	# which is maintained, WE-286)
	&& git clone --single-branch -b master https://github.com/StarCitizenWiki/mediawiki-extensions-EmbedVideo.git $MW_HOME/extensions/EmbedVideo \
	&& cd $MW_HOME/extensions/EmbedVideo \
	&& git checkout -q 3d8124738d3f1696b42b6eba1d11e9aeae660551 \
	# EventLogging
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/EventLogging $MW_HOME/extensions/EventLogging \
	&& cd $MW_HOME/extensions/EventLogging \
	&& git checkout -q 411fc0d6c8538b0064e0d75b5302534c7f28ac50 \
	# EventStreamConfig
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/EventStreamConfig $MW_HOME/extensions/EventStreamConfig \
	&& cd $MW_HOME/extensions/EventStreamConfig \
	&& git checkout -q 38de67f43c8a1fb26115226fe17caf428b7ce381 \
	# ExternalData (v. 3.3)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/ExternalData $MW_HOME/extensions/ExternalData \
	&& cd $MW_HOME/extensions/ExternalData \
	&& git checkout -q 564932ba8606390f339291a626b67340af536c68

# F
RUN set -x; \
	cd $MW_HOME/extensions \
	# FlexDiagrams (v. 0.6)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/FlexDiagrams $MW_HOME/extensions/FlexDiagrams \
	&& cd $MW_HOME/extensions/FlexDiagrams \
	&& git checkout -q 7e108c024e892b5dbecdada5dba7d62a93450d23

# G
RUN set -x; \
	cd $MW_HOME/extensions \
	# GlobalNotice
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/GlobalNotice $MW_HOME/extensions/GlobalNotice \
	&& cd $MW_HOME/extensions/GlobalNotice \
	&& git checkout -q 0cc66c56ebcfdebc0d407d82ae584a5426523d9f \
	# GoogleAnalyticsMetrics
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/GoogleAnalyticsMetrics $MW_HOME/extensions/GoogleAnalyticsMetrics \
	&& cd $MW_HOME/extensions/GoogleAnalyticsMetrics \
	&& git checkout -q 441511d7c848f8b59a08dc160fb1062f67778032 \
	# GoogleDocCreator
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/GoogleDocCreator $MW_HOME/extensions/GoogleDocCreator \
	&& cd $MW_HOME/extensions/GoogleDocCreator \
	&& git checkout -q 9db568cb4113ab99919fcb2e107e3428212f6ee1

# H
RUN set -x; \
	cd $MW_HOME/extensions \
	# HeaderFooter
	&& git clone -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/HeaderFooter $MW_HOME/extensions/HeaderFooter \
	&& cd $MW_HOME/extensions/HeaderFooter \
	&& git checkout -q b5fa1769548ab6452b86c6ea0fa28197ecf11164 \
	# HeaderTabs (v2.3)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/HeaderTabs $MW_HOME/extensions/HeaderTabs \
	&& cd $MW_HOME/extensions/HeaderTabs \
	&& git checkout -q 2fa424dd8adfb31a27613715ef523b918675ea42 \
	# HTMLTags
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/HTMLTags $MW_HOME/extensions/HTMLTags \
	&& cd $MW_HOME/extensions/HTMLTags \
	&& git checkout -q 3dc5caa3d586756f39abfef49053136267eb68ef

# L
RUN set -x; \
	cd $MW_HOME/extensions \
	# LabeledSectionTransclusion
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LabeledSectionTransclusion $MW_HOME/extensions/LabeledSectionTransclusion \
	&& cd $MW_HOME/extensions/LabeledSectionTransclusion \
	&& git checkout -q e7e5c6caf8faed52c8bdec9ee363511666405b20 \
	# LDAPAuthentication2
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LDAPAuthentication2 $MW_HOME/extensions/LDAPAuthentication2 \
	&& cd $MW_HOME/extensions/LDAPAuthentication2 \
	&& git checkout -q 808036a082e429c54799b0bbce89cba74a74157f \
	# LDAPAuthorization
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LDAPAuthorization $MW_HOME/extensions/LDAPAuthorization \
	&& cd $MW_HOME/extensions/LDAPAuthorization \
	&& git checkout -q 05a9d007c24429cfee90337077c9d3276edc73ad \
	# LDAPProvider
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LDAPProvider $MW_HOME/extensions/LDAPProvider \
	&& cd $MW_HOME/extensions/LDAPProvider \
	&& git checkout -q c8a4cad128f7aa898c8660648a7da1aef571765d \
	# Lingo (v. 3.2.4)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/Lingo $MW_HOME/extensions/Lingo \
	&& cd $MW_HOME/extensions/Lingo \
	&& git checkout -q f87ea047c6665c4c8d7435d23a3b454d127447a0 \
	# LinkSuggest
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LinkSuggest $MW_HOME/extensions/LinkSuggest \
	&& cd $MW_HOME/extensions/LinkSuggest \
	&& git checkout -q 145247abb87a61b4c19523ce62de37161780bd14 \
	# LinkTarget
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LinkTarget $MW_HOME/extensions/LinkTarget \
	&& cd $MW_HOME/extensions/LinkTarget \
	&& git checkout -q 83007f7c813204e769aecdfe15abf61cccb0c43b \
	# LockAuthor
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LockAuthor $MW_HOME/extensions/LockAuthor \
	&& cd $MW_HOME/extensions/LockAuthor \
	&& git checkout -q 29fc3cad3e6b9c47c04161a03d758ff355ca5723 \
	# Lockdown
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Lockdown $MW_HOME/extensions/Lockdown \
	&& cd $MW_HOME/extensions/Lockdown \
	&& git checkout -q 977cfa553b8f40f731b9b86f7dcc18cf181bd854 \
	# LookupUser
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LookupUser $MW_HOME/extensions/LookupUser \
	&& cd $MW_HOME/extensions/LookupUser \
	&& git checkout -q d0198361db26d3c6c69ce4cff52c85edae79bbe8 \
	# Loops
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Loops $MW_HOME/extensions/Loops \
	&& cd $MW_HOME/extensions/Loops \
	&& git checkout -q dee5dd131110a73ebcb3c09cad9eec0e130f9315 \
	# LuaCache
	&& git clone --single-branch -b master https://github.com/HydraWiki/LuaCache.git $MW_HOME/extensions/LuaCache \
	&& cd $MW_HOME/extensions/LuaCache \
	&& git checkout -q c654dacff3ae177d8ffc3dfd8c4f5e1e1ca7cb2f

# M
RUN set -x; \
	cd $MW_HOME/extensions \
	# MagicNoCache
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MagicNoCache $MW_HOME/extensions/MagicNoCache \
	&& cd $MW_HOME/extensions/MagicNoCache \
	&& git checkout -q 7315339c97c0eb7d528a8f6b14d055812a85fdb2 \
	# MassMessage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MassMessage $MW_HOME/extensions/MassMessage \
	&& cd $MW_HOME/extensions/MassMessage \
	&& git checkout -q 27ad797faa94d0d43294609eb00b836d7ab2a08e \
	# MassMessageEmail
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MassMessageEmail $MW_HOME/extensions/MassMessageEmail \
	&& cd $MW_HOME/extensions/MassMessageEmail \
	&& git checkout -q b2d7a0441ce18e7d63532f4e46ac99a99c27718e \
	# MediaUploader
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MediaUploader $MW_HOME/extensions/MediaUploader \
	&& cd $MW_HOME/extensions/MediaUploader \
	&& git checkout -q 77d2936cb635478c667d216fec3dcf8e0880e0c7 \
	# MintyDocs (1.2.1)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/MintyDocs $MW_HOME/extensions/MintyDocs \
	&& cd $MW_HOME/extensions/MintyDocs \
	&& git checkout -q 760e10ddf4b1dd70caae76286e6afd6342f8f67b \
	# MobileFrontend
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MobileFrontend $MW_HOME/extensions/MobileFrontend \
	&& cd $MW_HOME/extensions/MobileFrontend \
	&& git checkout -q a44f2808aa9e051f6a56215ce1320018db723808 \
	# MsUpload
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MsUpload $MW_HOME/extensions/MsUpload \
	&& cd $MW_HOME/extensions/MsUpload \
	&& git checkout -q 039b6aece443d6d030e187c112ab2520a65915b2 \
	# MyVariables
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MyVariables $MW_HOME/extensions/MyVariables \
	&& cd $MW_HOME/extensions/MyVariables \
	&& git checkout -q 28e21be0ff6fdc1060f5e83a130faa8406d09b0f

# N
RUN set -x; \
	cd $MW_HOME/extensions \
	# NCBITaxonomyLookup
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/NCBITaxonomyLookup $MW_HOME/extensions/NCBITaxonomyLookup \
	&& cd $MW_HOME/extensions/NCBITaxonomyLookup \
	&& git checkout -q 58727c6d1c62c3403a50e5e945b1a374701c3a93 \
	# NewUserMessage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/NewUserMessage $MW_HOME/extensions/NewUserMessage \
	&& cd $MW_HOME/extensions/NewUserMessage \
	&& git checkout -q 28641bc5780fa8023106b33f8647fc7bd954eb19 \
	# NumerAlpha
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/NumerAlpha $MW_HOME/extensions/NumerAlpha \
	&& cd $MW_HOME/extensions/NumerAlpha \
	&& git checkout -q 27660326ccaf44bbc2942e40a24e4433faaec1a7

# O
RUN set -x; \
	cd $MW_HOME/extensions \
	# OpenGraphMeta
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/OpenGraphMeta $MW_HOME/extensions/OpenGraphMeta \
	&& cd $MW_HOME/extensions/OpenGraphMeta \
	&& git checkout -q cb990fcea3b7827f02bcc328e367a7b2387a32a3 \
	# OpenIDConnect
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/OpenIDConnect $MW_HOME/extensions/OpenIDConnect \
	&& cd $MW_HOME/extensions/OpenIDConnect \
	&& git checkout -q 1d741bde52bc702a68e328bce07a629731fb245a
# P
RUN set -x; \
	cd $MW_HOME/extensions \
	# PageExchange
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/PageExchange $MW_HOME/extensions/PageExchange \
	&& cd $MW_HOME/extensions/PageExchange \
	&& git checkout -q afda8c1ebe6e870841df47f9abeba5ac590594d7 \
	# PageForms (v. 5.9)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/PageForms $MW_HOME/extensions/PageForms \
	&& cd $MW_HOME/extensions/PageForms \
	&& git checkout -q 4ac28291df76dd5544d232d2988f69e61c86af3e \
	# PluggableAuth
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/PluggableAuth $MW_HOME/extensions/PluggableAuth \
	&& cd $MW_HOME/extensions/PluggableAuth \
	&& git checkout -q 4ef6f74c067f9ff81b78fd64b9780a82ccce97f3 \
	# Popups
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Popups $MW_HOME/extensions/Popups \
	&& cd $MW_HOME/extensions/Popups \
	&& git checkout -q 3567c401b261076c68cb4872ec32a8eac47ff681 \
	# PagePort (code moved to gerrit after REL1_43 cut)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/PagePort $MW_HOME/extensions/PagePort \
	&& cd $MW_HOME/extensions/PagePort \
	&& git checkout -q 0679a33d62559367fce2486c4ccae02f27c26d9f

# R
RUN set -x; \
	cd $MW_HOME/extensions \
	# RegularTooltips
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/RegularTooltips $MW_HOME/extensions/RegularTooltips \
	&& cd $MW_HOME/extensions/RegularTooltips \
	&& git checkout -q e52d009f1a01575de2abebf802c6e97b24587d9a \
	# RevisionSlider
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/RevisionSlider $MW_HOME/extensions/RevisionSlider \
	&& cd $MW_HOME/extensions/RevisionSlider \
	&& git checkout -q b10b2150133e77099a37b089003170c0111eb681 \
	# RottenLinks
	&& git clone --single-branch -b master https://github.com/miraheze/RottenLinks.git $MW_HOME/extensions/RottenLinks \
	&& cd $MW_HOME/extensions/RottenLinks \
	&& git checkout -q cb1d7376e7f900606b8f998e01280adf645d97c6

# S
RUN set -x; \
	cd $MW_HOME/extensions \
	# SandboxLink
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SandboxLink $MW_HOME/extensions/SandboxLink \
	&& cd $MW_HOME/extensions/SandboxLink \
	&& git checkout -q 3eae08b2f34e84399e154cc78973c69d4f5c7811 \
	# SaveSpinner
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SaveSpinner $MW_HOME/extensions/SaveSpinner \
	&& cd $MW_HOME/extensions/SaveSpinner \
	&& git checkout -q 438ea79d4ba11cfe8a8c3599fba5c473b9760b91 \
	# SemanticDependencyUpdater (WikiTeq fork)
	&& git clone --single-branch -b old-master https://github.com/WikiTeq/SemanticDependencyUpdater.git $MW_HOME/extensions/SemanticDependencyUpdater \
	&& cd $MW_HOME/extensions/SemanticDependencyUpdater \
	&& git checkout -q 8f927a9b0f1eb49359d30a76099fa1252905f64d \
	# SimpleChanges
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SimpleChanges $MW_HOME/extensions/SimpleChanges \
	&& cd $MW_HOME/extensions/SimpleChanges \
	&& git checkout -q 024aca4c80d2a6b697f3d85e99de8e198b126999 \
	# SimpleMathJax
	&& git clone --single-branch https://github.com/jmnote/SimpleMathJax.git $MW_HOME/extensions/SimpleMathJax \
	&& cd $MW_HOME/extensions/SimpleMathJax \
	&& git checkout -q fab35e6ac66e1f5abd3c91a57719f8180dd346ef \
	# SkinPerPage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SkinPerPage $MW_HOME/extensions/SkinPerPage \
	&& cd $MW_HOME/extensions/SkinPerPage \
	&& git checkout -q cd94d4684782457f81517d6f2692f3af300d9242 \
	# SmiteSpam
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SmiteSpam $MW_HOME/extensions/SmiteSpam \
	&& cd $MW_HOME/extensions/SmiteSpam \
	&& git checkout -q 529ad28e2953506c7216c90abb7bd17f320fb0b5

# T
RUN set -x; \
	cd $MW_HOME/extensions \
	# TemplateStyles
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TemplateStyles $MW_HOME/extensions/TemplateStyles \
	&& cd $MW_HOME/extensions/TemplateStyles \
	&& git checkout -q 31a4bd259a921e19b4857befa700e7fc0998b6d2 \
	# TemplateWizard
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TemplateWizard $MW_HOME/extensions/TemplateWizard \
	&& cd $MW_HOME/extensions/TemplateWizard \
	&& git checkout -q 4c3057f1bf55f686f044dce40b9e70e14ea8d8ec \
	# TimedMediaHandler
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TimedMediaHandler $MW_HOME/extensions/TimedMediaHandler \
	&& cd $MW_HOME/extensions/TimedMediaHandler \
	&& git checkout -q 3cafd5daa4580fb013b7918a4b1cc9e60dd53527 \
	# TinyMCE
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TinyMCE $MW_HOME/extensions/TinyMCE \
	&& cd $MW_HOME/extensions/TinyMCE \
	&& git checkout -q 70467c1b6bcfa7e2f5d415040b6a997741402b4a \
	# TitleIcon
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TitleIcon $MW_HOME/extensions/TitleIcon \
	&& cd $MW_HOME/extensions/TitleIcon \
	&& git checkout -q 892afc0abab4c76e2db13afab11dd82a8e09e8c8

# U
RUN set -x; \
	cd $MW_HOME/extensions \
	# UniversalLanguageSelector
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UniversalLanguageSelector $MW_HOME/extensions/UniversalLanguageSelector \
	&& cd $MW_HOME/extensions/UniversalLanguageSelector \
	&& git checkout -q d74ff7c4b98d72dda6bfccc597d496ef93953bfb \
	# UploadWizard
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UploadWizard $MW_HOME/extensions/UploadWizard \
	&& cd $MW_HOME/extensions/UploadWizard \
	&& git checkout -q 16b2d111e4f5a1f30249d78965c536a592305caf \
	# UrlGetParameters
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UrlGetParameters $MW_HOME/extensions/UrlGetParameters \
	&& cd $MW_HOME/extensions/UrlGetParameters \
	&& git checkout -q 013427509ca51a710879c8811b6f4ef04d7b2e12 \
	# UserFunctions
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UserFunctions $MW_HOME/extensions/UserFunctions \
	&& cd $MW_HOME/extensions/UserFunctions \
	&& git checkout -q fe610c0a243644789afd7837b7d19a896e216822 \
	# UserMerge
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UserMerge $MW_HOME/extensions/UserMerge \
	&& cd $MW_HOME/extensions/UserMerge \
	&& git checkout -q 658fd7ac017cee7cd1ccd68a7431ffad31cf056c \
	# UserPageViewTracker (v. 0.9 development)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/UserPageViewTracker $MW_HOME/extensions/UserPageViewTracker \
	&& cd $MW_HOME/extensions/UserPageViewTracker \
	&& git checkout -q f375afc09cf381d662c75d405aa373cf6cb658cd

# V
RUN set -x; \
	cd $MW_HOME/extensions \
	# Variables
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Variables $MW_HOME/extensions/Variables \
	&& cd $MW_HOME/extensions/Variables \
	&& git checkout -q 81115fae09d0a219078d2a2511de83474fd2eb8f \
	# VEForAll (v. 0.6)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/VEForAll $MW_HOME/extensions/VEForAll \
	&& cd $MW_HOME/extensions/VEForAll \
	&& git checkout -q 33b5fa746af51e9c6c770950a197b1c17f5ee253 \
	# VoteNY
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/VoteNY $MW_HOME/extensions/VoteNY \
	&& cd $MW_HOME/extensions/VoteNY \
	&& git checkout -q d1d57da0ba7418c9e7f98b659a5fa2832d790c2d

# W
RUN set -x; \
	cd $MW_HOME/extensions \
	# WatchAnalytics (v. 4.3)
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/WatchAnalytics $MW_HOME/extensions/WatchAnalytics \
	&& cd $MW_HOME/extensions/WatchAnalytics \
	&& git checkout -q da4ab0f2455ef9ad2d1593143f638988f9aa1dec \
	# WhoIsWatching
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/WhoIsWatching $MW_HOME/extensions/WhoIsWatching \
	&& cd $MW_HOME/extensions/WhoIsWatching \
	&& git checkout -q ad0d721ab588c77678a33db304a77bd684724a1a \
	# Widgets
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Widgets $MW_HOME/extensions/Widgets \
	&& cd $MW_HOME/extensions/Widgets \
	&& git checkout -q 50da5c66923ec5169f5606cc1d76f38f0b759d71 \
	# WikiForum
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/WikiForum $MW_HOME/extensions/WikiForum \
	&& cd $MW_HOME/extensions/WikiForum \
	&& git checkout -q 34526466f179d6998e60ea98dbd3f78a90213520 \
	# WikiSEO
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/WikiSEO $MW_HOME/extensions/WikiSEO \
	&& cd $MW_HOME/extensions/WikiSEO \
	&& git checkout -q 5d27adb6ec53e7b1076a485e93f0b0c272d08937 \
	# WSOAuth
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/WSOAuth $MW_HOME/extensions/WSOAuth \
	&& cd $MW_HOME/extensions/WSOAuth \
	&& git checkout -q 9f25fade2bcd3fae44c3236072f5ea2eb068b75c

#### WikiTeq extensions ####

# A
RUN set -x; \
	cd $MW_HOME/extensions \
  	# AddMessages
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/AddMessages $MW_HOME/extensions/AddMessages \
	&& cd $MW_HOME/extensions/AddMessages \
	&& git checkout -q a0af32f229d93016f3c3e80bcf2065e09f498064 \
	# Auth_remoteuser
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Auth_remoteuser $MW_HOME/extensions/Auth_remoteuser \
	&& cd $MW_HOME/extensions/Auth_remoteuser \
	&& git checkout -q c985d520c7aea38092ee7208be31f07a7251210d

# B
RUN set -x; \
	cd $MW_HOME/extensions \
	# Buggy
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Buggy.git $MW_HOME/extensions/Buggy \
	&& cd $MW_HOME/extensions/Buggy \
	&& git checkout -q 49dc8fd9ae01195127e0106b94fb01beb5022eb7

# C
RUN set -x; \
	cd $MW_HOME/extensions \
  	# ChangeAuthor
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ChangeAuthor $MW_HOME/extensions/ChangeAuthor \
	&& cd $MW_HOME/extensions/ChangeAuthor \
	&& git checkout -q 89105aebc39d85c15149391832376d6ea85702c1 \
	# Citoid
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Citoid $MW_HOME/extensions/Citoid \
	&& cd $MW_HOME/extensions/Citoid \
	&& git checkout -q ee1f920556ff245fd4366d8ceed15afb6aa1b0f8

# E
RUN set -x; \
	cd $MW_HOME/extensions \
   	# EditAccount
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/EditAccount $MW_HOME/extensions/EditAccount \
	&& cd $MW_HOME/extensions/EditAccount \
	&& git checkout -q e59561c56836a98bc5f5f3068bc81fd67a5d1c41 \
	# Flow
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Flow $MW_HOME/extensions/Flow \
	&& cd $MW_HOME/extensions/Flow \
	&& git checkout -q fc462613fcdcefd03d03981d0660610cba21c6f6

# G
RUN set -x; \
	cd $MW_HOME/extensions \
  	# GoogleDocTag
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/GoogleDocTag $MW_HOME/extensions/GoogleDocTag \
	&& cd $MW_HOME/extensions/GoogleDocTag \
	&& git checkout -q 50dfe68e36742b9c6ab24b734ab4401cf1d65178 \
	# GTag
	&& git clone https://github.com/SkizNet/mediawiki-GTag.git $MW_HOME/extensions/GTag \
	&& cd $MW_HOME/extensions/GTag \
	&& git checkout -q 90d87ea56777b2be3ab5f718b0b6644623a24d04

# H
RUN set -x; \
	cd $MW_HOME/extensions \
   	# HeadScript
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/HeadScript $MW_HOME/extensions/HeadScript \
	&& cd $MW_HOME/extensions/HeadScript \
	&& git checkout -q cc0fb94acd25a20292b0a4d5bbe74bac307b55fe

# I
RUN set -x; \
	cd $MW_HOME/extensions \
   	# IframePage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/IframePage $MW_HOME/extensions/IframePage \
	&& cd $MW_HOME/extensions/IframePage \
	&& git checkout -q 31f27b2388c2032e121a062561924419ce2fe0e9

# L
RUN set -x; \
	cd $MW_HOME/extensions \
  	# Lazyload
	&& git clone https://github.com/mudkipme/mediawiki-lazyload.git $MW_HOME/extensions/Lazyload \
	&& cd $MW_HOME/extensions/Lazyload \
	&& git checkout -b $MW_VERSION 30a01cc149822353c9404ec178ec01848bae65c5 \
	# LiquidThreads
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LiquidThreads $MW_HOME/extensions/LiquidThreads \
	&& cd $MW_HOME/extensions/LiquidThreads \
	&& git checkout -q f0d9a0de69623655ca57c40bcd10cb933d9ec99f

# M
RUN set -x; \
	cd $MW_HOME/extensions \
   	# MassPasswordReset
	# No 1.43 branch
	&& cd $MW_HOME/extensions \
	&& git clone https://github.com/nischayn22/MassPasswordReset.git \
	&& cd MassPasswordReset \
	&& git checkout -b REL1_39 04b7e765db994d41f5ca3a910e18f77105218d94 \
	# MobileDetect
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MobileDetect $MW_HOME/extensions/MobileDetect \
	&& cd $MW_HOME/extensions/MobileDetect \
	&& git checkout -q 1c783c4abc9849e1409f386583404762463f263f \
	# Mpdf
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Mpdf.git $MW_HOME/extensions/Mpdf \
	&& cd $MW_HOME/extensions/Mpdf \
	&& git checkout -q dcd9c9b4587d2caefe6a952ca49be7b72eff1da0

# P
RUN set -x; \
	cd $MW_HOME/extensions \
   	# PageSchemas
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/PageSchemas $MW_HOME/extensions/PageSchemas \
	&& cd $MW_HOME/extensions/PageSchemas \
	&& git checkout -q 25a55c1aa9c6600e9fd9b03f5d50ccad2a9e83fe \
	# PDFEmbed
	&& git clone --single-branch -b main https://github.com/WolfgangFahl/PDFEmbed.git $MW_HOME/extensions/PDFEmbed \
	&& cd $MW_HOME/extensions/PDFEmbed \
	&& git checkout -q f38758156639b34317ffc6a9e8b5b2624aebae8b \
	# PubmedParser (v. 5.2.0)
	&& git clone --single-branch -b main https://github.com/bovender/PubmedParser.git $MW_HOME/extensions/PubmedParser \
	&& cd $MW_HOME/extensions/PubmedParser \
	&& git checkout -q 509c9a26b5c07fbc476448bd34b38cd8f5ec01b5

# S
RUN set -x; \
	cd $MW_HOME/extensions \
  	# Scopus
	# No 1.43 branch
	&& git clone https://github.com/nischayn22/Scopus.git $MW_HOME/extensions/Scopus \
	&& cd $MW_HOME/extensions/Scopus \
	&& git checkout -b REL1_39 4fe8048459d9189626d82d9d93a0d5f906c43746 \
	# SelectCategory
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SelectCategory $MW_HOME/extensions/SelectCategory \
	&& cd $MW_HOME/extensions/SelectCategory \
	&& git checkout -q 1f351647af2e235e11139aa8f1b70c19a3556c61 \
	# SemanticQueryInterface
	&& git clone https://github.com/vedmaka/SemanticQueryInterface.git $MW_HOME/extensions/SemanticQueryInterface \
	&& cd $MW_HOME/extensions/SemanticQueryInterface \
	&& git checkout -q 0016305a95ecbb6ed4709bfa3fc6d9995d51336f \
	&& mv SemanticQueryInterface/* . \
	&& rmdir SemanticQueryInterface \
	&& ln -s SQI.php SemanticQueryInterface.php \
	&& rm -fr .git \
	# Sentry (WikiTeq fork that uses sentry/sentry 3.x)
	&& git clone --single-branch -b master https://github.com/WikiTeq/mediawiki-extensions-Sentry.git $MW_HOME/extensions/Sentry \
	&& cd $MW_HOME/extensions/Sentry \
	&& git checkout -q 9d9162d83f921b66f6c14ed354d20607ecafa030 \
	# ShowMe
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ShowMe $MW_HOME/extensions/ShowMe \
	&& cd $MW_HOME/extensions/ShowMe \
	&& git checkout -q 44e3569219e804829e1ff770bb9bd02b7dd7ec2b \
	# SimpleTooltip
	# No 1.43 branch
	&& git clone --single-branch -b master https://github.com/Universal-Omega/SimpleTooltip.git $MW_HOME/extensions/SimpleTooltip \
	&& cd $MW_HOME/extensions/SimpleTooltip \
	&& git checkout -b REL1_39 3146514ecda810d6ce9feb79ac8e0e0015f242eb \
	# SimpleTippy
	&& git clone --single-branch -b master https://github.com/vedmaka/mediawiki-extension-SimpleTippy.git $MW_HOME/extensions/SimpleTippy \
	&& cd $MW_HOME/extensions/SimpleTippy \
	&& git checkout -q 6b4ddff802db21a4c3443d7ce9dcab5ac39d625a \
	# Skinny
	&& git clone --single-branch -b master https://github.com/tinymighty/skinny.git $MW_HOME/extensions/Skinny \
	&& cd $MW_HOME/extensions/Skinny \
	&& git checkout -q fd17e6102ce12b97c70a4448e8732d3be129ff4d \
	# SkinPerNamespace
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SkinPerNamespace $MW_HOME/extensions/SkinPerNamespace \
	&& cd $MW_HOME/extensions/SkinPerNamespace \
	&& git checkout -q 33590b2659bf87274bb954f0d01377f5d679d94c \
	# Survey
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Survey $MW_HOME/extensions/Survey \
	&& cd $MW_HOME/extensions/Survey \
	&& git checkout -q b0eb0fa7838827d2ce22be2fbd96ed9a6b182b7e

# T
RUN set -x; \
	cd $MW_HOME/extensions \
   	# Tabber
	&& git clone --single-branch -b master https://gitlab.com/hydrawiki/extensions/Tabber.git $MW_HOME/extensions/Tabber \
	&& cd $MW_HOME/extensions/Tabber \
	&& git checkout -q 6c67baf4d18518fa78e07add4c032d62dd384b06 \
	# TabberNeue (v. 2.7.1)
	&& git clone --single-branch -b main https://github.com/StarCitizenTools/mediawiki-extensions-TabberNeue.git $MW_HOME/extensions/TabberNeue \
	&& cd $MW_HOME/extensions/TabberNeue \
	&& git checkout -q 799f86514b6b72bb6be1d615232a5c7cf7f6cfa3 \
	# Tabs
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Tabs $MW_HOME/extensions/Tabs \
	&& cd $MW_HOME/extensions/Tabs \
	&& git checkout -q 505eac44a119ec3d804b8fd16d4c6b1f6abf7258 \
	# TwitterTag
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TwitterTag $MW_HOME/extensions/TwitterTag \
	&& cd $MW_HOME/extensions/TwitterTag \
	&& git checkout -q 0ce9a66d1818eb7b77b91fb051957f99fc17351f

# U
RUN set -x; \
	cd $MW_HOME/extensions \
   	# UploadWizardExtraButtons
	&& git clone --single-branch -b master https://github.com/vedmaka/mediawiki-extension-UploadWizardExtraButtons.git $MW_HOME/extensions/UploadWizardExtraButtons \
	&& cd $MW_HOME/extensions/UploadWizardExtraButtons \
	&& git checkout -q accba1b9b6f50e67d709bd727c9f4ad6de78c0c0

# Y
RUN set -x; \
	cd $MW_HOME/extensions \
   	# YouTube
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/YouTube $MW_HOME/extensions/YouTube \
	&& cd $MW_HOME/extensions/YouTube \
	&& git checkout -q 01673ce5f560fabe09b0feb1e65b57cbf58aae39

# G
RUN set -x; \
	cd $MW_HOME/extensions \
   	# GoogleLogin
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/GoogleLogin $MW_HOME/extensions/GoogleLogin \
	&& cd $MW_HOME/extensions/GoogleLogin \
	&& git checkout -q 0c653d036198d5fd52f8588776b95415ccc0eef4

# V
RUN set -x; \
	cd $MW_HOME/extensions \
   	# VariablesLua (v. 1.6.0)
	&& git clone --single-branch -b master https://github.com/Liquipedia/VariablesLua.git $MW_HOME/extensions/VariablesLua \
	&& cd $MW_HOME/extensions/VariablesLua \
	&& git checkout -q 64a5776f055b33c38602e8a94f7237a6b8cb4c79

# W
RUN set -x; \
	cd $MW_HOME/extensions \
	# WSSlots
	&& git clone --single-branch -b REL1_43 https://github.com/WikiTeq/WSSlots.git $MW_HOME/extensions/WSSlots \
	&& cd $MW_HOME/extensions/WSSlots \
	&& git checkout -q a46d1309ab11034aa7e3a762e392346c1b0ecd67

# J
RUN set -x; \
	cd $MW_HOME/extensions \
	# JWTAuth
	&& git clone --single-branch -b main https://github.com/jeffw16/JWTAuth.git $MW_HOME/extensions/JWTAuth \
	&& cd $MW_HOME/extensions/JWTAuth \
	&& git checkout -q c7c0730160a84d6b60e3e1b6b108d790972f0f15 # Upgrade carefully, we had a problem with version 2.0, see MITE-50

# WikiTeq removes/fixes the extensions with issues in Canasta docker image, remove it if fixed in Canasta
RUN set -x; \
	# does not work? see WIK-702?focusedCommentId=41955
	rm -fr $MW_HOME/extensions/TimedMediaHandler \
	# missed in Canasta
	&& cd $MW_HOME/extensions/EmailAuthorization \
	&& git submodule update --init --recursive

################# Patches #################

# WikiTeq AL-12
COPY _sources/patches/FlexDiagrams.0.4.fix.diff /tmp/FlexDiagrams.0.4.fix.diff
RUN set -x; \
	cd $MW_HOME/extensions/FlexDiagrams \
	&& git apply /tmp/FlexDiagrams.0.4.fix.diff

# PageForms WLDR-319, WLDR-318
COPY _sources/patches/pageforms-5.9-displaytitle.patch /tmp/pageforms-5.9-displaytitle.patch
RUN set -x; \
	cd $MW_HOME/extensions/PageForms \
	&& git apply /tmp/pageforms-5.9-displaytitle.patch

# GoogleLogin gerrit patches 1070987 and 1074530 applied to REL1_43
COPY _sources/patches/GoogleLogin-fixes.patch /tmp/GoogleLogin-fixes.patch
RUN set -x; \
	cd $MW_HOME/extensions/GoogleLogin \
	&& git apply /tmp/GoogleLogin-fixes.patch

# GoogleAnalyticsMetrics pins google/apiclient to 2.12.6, relax it
COPY _sources/patches/GoogleAnalyticsMetrics-relax-pin.patch /tmp/GoogleAnalyticsMetrics-relax-pin.patch
RUN set -x; \
	cd $MW_HOME/extensions/GoogleAnalyticsMetrics \
	&& git apply /tmp/GoogleAnalyticsMetrics-relax-pin.patch

# Cleanup all .git leftovers
RUN set -x; \
	cd $MW_HOME/extensions \
	&& find . \( -name ".git" -o -name ".gitignore" -o -name ".gitmodules" -o -name ".gitattributes" \) -exec rm -rf -- {} +

FROM base AS composer

# Copy core, skins and extensions
COPY --from=core $MW_HOME $MW_HOME
COPY --from=skins $MW_HOME/skins $MW_HOME/skins
COPY --from=extensions $MW_HOME/extensions $MW_HOME/extensions

# Composer dependencies
COPY _sources/configs/composer.wikiteq.json $MW_HOME/composer.local.json
# Run with secret mounted to /run/secrets/COMPOSER_TOKEN
# This is needed to bypass rate limits
RUN --mount=type=secret,id=COMPOSER_TOKEN cd $MW_HOME \
	&& cp composer.json composer.json.bak \
	&& cat composer.json.bak | jq '. + {"minimum-stability": "dev"}' > composer.json \
	&& rm composer.json.bak \
	&& cp composer.json composer.json.bak \
	&& cat composer.json.bak | jq '. + {"prefer-stable": true}' > composer.json \
	&& rm composer.json.bak \
	&& composer clear-cache \
	# configure auth
	&& if [ -f "/run/secrets/COMPOSER_TOKEN" ]; then composer config -g github-oauth.github.com $(cat /run/secrets/COMPOSER_TOKEN); fi \
	&& composer update --no-dev --with-dependencies \
	&& composer clear-cache \
	# deauth
	&& composer config -g --unset github-oauth.github.com

# Move files around
RUN set -x; \
	# Move files to $MW_ORIGIN_FILES directory
	mv $MW_HOME/images $MW_ORIGIN_FILES/ \
	&& mv $MW_HOME/cache $MW_ORIGIN_FILES/ \
	# Create symlinks from $MW_VOLUME to the wiki root for images and cache directories
	&& ln -s $MW_VOLUME/images $MW_HOME/images \
	&& ln -s $MW_VOLUME/cache $MW_HOME/cache

FROM base AS final

COPY --from=composer $MW_HOME $MW_HOME
COPY --from=composer $MW_ORIGIN_FILES $MW_ORIGIN_FILES

# Default values
ENV MW_AUTOUPDATE=true \
	MW_MAINTENANCE_UPDATE=0 \
	MW_ENABLE_EMAIL=0 \
	MW_ENABLE_USER_EMAIL=0 \
	MW_ENABLE_UPLOADS=0 \
	MW_USE_IMAGE_MAGIC=0 \
	MW_USE_INSTANT_COMMONS=0 \
	MW_EMERGENCY_CONTACT=apache@invalid \
	MW_PASSWORD_SENDER=apache@invalid \
	MW_MAIN_CACHE_TYPE=CACHE_NONE \
	MW_DB_TYPE=mysql \
	MW_DB_SERVER=db \
	MW_DB_NAME=mediawiki \
	MW_DB_USER=root \
	MW_DB_INSTALLDB_USER=root \
	MW_REDIS_SERVERS=redis:6379 \
	MW_CIRRUS_SEARCH_SERVERS=elasticsearch \
	MW_MAINTENANCE_CIRRUSSEARCH_UPDATECONFIG=2 \
	MW_MAINTENANCE_CIRRUSSEARCH_FORCEINDEX=2 \
	MW_ENABLE_JOB_RUNNER=true \
	MW_JOB_RUNNER_PAUSE=2 \
	MW_JOB_RUNNER_MEMORY_LIMIT=512M \
	MW_ENABLE_TRANSCODER=true \
	MW_JOB_TRANSCODER_PAUSE=60 \
	MW_MAP_DOMAIN_TO_DOCKER_GATEWAY=0 \
	MW_ENABLE_SITEMAP_GENERATOR=false \
	MW_SITEMAP_PAUSE_DAYS=1 \
	MW_SITEMAP_SUBDIR="" \
	MW_SITEMAP_IDENTIFIER="mediawiki" \
	MW_CONFIG_DIR=/mediawiki/config \
	PHP_UPLOAD_MAX_FILESIZE=10M \
	PHP_POST_MAX_SIZE=10M \
	PHP_MEMORY_LIMIT=128M \
	PHP_MAX_INPUT_VARS=1000 \
	PHP_MAX_EXECUTION_TIME=60 \
	PHP_MAX_INPUT_TIME=60 \
	LOG_FILES_COMPRESS_DELAY=3600 \
	LOG_FILES_REMOVE_OLDER_THAN_DAYS=10 \
	MEDIAWIKI_MAINTENANCE_AUTO_ENABLED=false \
	MW_SENTRY_DSN="" \
	MW_USE_CACHE_DIRECTORY=1 \
	APACHE_REMOTE_IP_HEADER=X-Forwarded-For \
	MW_AUTO_IMPORT=1

COPY _sources/configs/msmtprc /etc/
COPY _sources/configs/mediawiki.conf /etc/apache2/sites-enabled/
COPY _sources/configs/status.conf /etc/apache2/mods-available/
COPY _sources/configs/scan.conf /etc/clamd.d/scan.conf
COPY _sources/configs/php_*.ini /etc/php/8.1/cli/conf.d/
COPY _sources/configs/php_*.ini /etc/php/8.1/apache2/conf.d/
COPY _sources/scripts/*.sh /
COPY _sources/scripts/*.php $MW_HOME/maintenance/
COPY _sources/configs/robots.php $WWW_ROOT/
COPY _sources/configs/robots.txt $WWW_ROOT/
COPY _sources/configs/.htaccess $WWW_ROOT/
COPY _sources/images/favicon.ico $WWW_ROOT/
COPY _sources/canasta/DockerSettings.php $MW_HOME/
COPY _sources/canasta/getMediawikiSettings.php /
COPY _sources/configs/mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf

RUN set -x; \
	chmod -v +x /*.sh \
	# Sitemap directory
	&& mkdir -p $MW_ORIGIN_FILES/sitemap \
	&& ln -s $MW_VOLUME/sitemap $MW_HOME/sitemap \
	# Comment out ErrorLog and CustomLog parameters, we use rotatelogs in mediawiki.conf for the log files
	&& sed -i 's/^\(\s*ErrorLog .*\)/# \1/g' /etc/apache2/apache2.conf \
	&& sed -i 's/^\(\s*CustomLog .*\)/# \1/g' /etc/apache2/apache2.conf \
	# Make web installer work with Canasta
	&& cp "$MW_HOME/includes/Output/NoLocalSettings.php" "$MW_HOME/includes/CanastaNoLocalSettings.php" \
	&& sed -i 's/MW_CONFIG_FILE/CANASTA_CONFIG_FILE/g' "$MW_HOME/includes/CanastaNoLocalSettings.php" \
	# Modify config
	&& sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
	&& a2enmod expires remoteip \
	&& a2disconf other-vhosts-access-log \
	# For Widgets extension
	&& mkdir -p $MW_ORIGIN_FILES/extensions/Widgets \
	&& mv $MW_HOME/extensions/Widgets/compiled_templates $MW_ORIGIN_FILES/extensions/Widgets/ \
	&& ln -s $MW_VOLUME/extensions/Widgets/compiled_templates $MW_HOME/extensions/Widgets/compiled_templates

COPY _sources/images/Powered-by-Canasta.png /var/www/mediawiki/w/resources/assets/

EXPOSE 80
WORKDIR $MW_HOME

HEALTHCHECK --interval=1m --timeout=10s \
	CMD wget -q --method=HEAD localhost/w/api.php

CMD ["/run-apache.sh"]
