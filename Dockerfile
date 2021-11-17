FROM debian:10 as base

LABEL maintainers=""
LABEL org.opencontainers.image.source=https://github.com/WikiWorks/Canasta

ENV MW_VERSION=REL1_35 \
	MW_CORE_VERSION=1.35.4 \
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
    git=1:2.20.1-2+deb10u3 \
    apache2=2.4.38-3+deb10u5 \
    software-properties-common=0.96.20.2-2 \
	gpg=2.2.12-1+deb10u1 \
	apt-transport-https=1.8.2.3 \
	ca-certificates=20200601~deb10u2 \
	wget=1.20.1-1.1 \
	imagemagick=8:6.9.10.23+dfsg-2.1+deb10u1  \
	python-pygments=2.3.1+dfsg-1+deb10u2 \
	msmtp=1.8.3-1 \
	msmtp-mta=1.8.3-1 \
	patch=2.7.6-3+deb10u1 \
	vim=2:8.1.0875-5 \
	mc=3:4.8.22-1 \
	ffmpeg=7:4.1.6-1~deb10u1 \
	curl=7.64.0-4+deb10u2 \
	unzip=6.0-23+deb10u2 \
	gnupg=2.2.12-1+deb10u1 \
	default-mysql-client=1.0.5 \
	rsync=3.1.3-6 \
    && wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg \
    && echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list \
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
RUN set -x; \
	cd $MW_HOME/skins \
	# Chameleon
	&& git clone https://github.com/ProfessionalWiki/chameleon.git $MW_HOME/skins/chameleon \
	&& cd $MW_HOME/skins/chameleon \
	&& git checkout -q -b $MW_VERSION c817e3a89193ecb8e2ec37800d4534b4747e6903 \
	# CologneBlue
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/CologneBlue $MW_HOME/skins/CologneBlue \
	&& cd $MW_HOME/skins/CologneBlue \
	&& git checkout -q 515a545dfee9f534f74a42057b7a4509076716b4 \
	# MinervaNeue
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/MinervaNeue $MW_HOME/skins/MinervaNeue \
	&& cd $MW_HOME/skins/MinervaNeue \
	&& git checkout -q 6c99418af845a7761c246ee5a50fbb82715f4003 \
	# Modern
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/Modern $MW_HOME/skins/Modern \
	&& cd $MW_HOME/skins/Modern \
	&& git checkout -q d0a04c91132105f712df4de44a99d3643e7afbba \
	# Pivot
	&& git clone -b v2.3.0 https://github.com/Hutchy68/pivot.git $MW_HOME/skins/pivot \
	&& cd $MW_HOME/skins/pivot \
	&& git checkout -q -b $MW_VERSION 0d3d6b03a83afd7e1cb170aa41bdf23c0ce3e93b \
	# Refreshed
	&& git clone -b $MW_VERSION --single-branch https://gerrit.wikimedia.org/r/mediawiki/skins/Refreshed $MW_HOME/skins/Refreshed \
	&& cd $MW_HOME/skins/Refreshed \
	&& git checkout -q 3fad8765c3ec8082bb899239f502199f651818cb

# Extensions
RUN set -x; \
	cd $MW_HOME/extensions \
	# AdminLinks
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/AdminLinks $MW_HOME/extensions/AdminLinks \
	&& cd $MW_HOME/extensions/AdminLinks \
	&& git checkout -q 28009e814c91d67f4287bcc180d626308adb2b52 \
	# AdvancedSearch
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/AdvancedSearch $MW_HOME/extensions/AdvancedSearch \
	&& cd $MW_HOME/extensions/AdvancedSearch \
	&& git checkout -q d1895707f3750a6d4a486b425ac9a727707f27f9 \
	# AJAXPoll
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/AJAXPoll $MW_HOME/extensions/AJAXPoll \
	&& cd $MW_HOME/extensions/AJAXPoll \
	&& git checkout -q 846bbd16799efb7b279433856a5e85914961314b \
	# AntiSpoof
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/AntiSpoof $MW_HOME/extensions/AntiSpoof \
	&& cd $MW_HOME/extensions/AntiSpoof \
	&& git checkout -q 1c82ce797d2eefa7f82fb88f82d550c2c73ff3b6 \
	# ApprovedRevs
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/ApprovedRevs $MW_HOME/extensions/ApprovedRevs \
	&& cd $MW_HOME/extensions/ApprovedRevs \
	&& git checkout -q fb54b5f5cf4d9495877c622fd0f197ece6a15545 \
	# Arrays
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Arrays $MW_HOME/extensions/Arrays \
	&& cd $MW_HOME/extensions/Arrays \
	&& git checkout -q e09d74379c191f3e83560d7bb35d39fb4162f0fc \
	# BetaFeatures
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/BetaFeatures $MW_HOME/extensions/BetaFeatures \
	&& cd $MW_HOME/extensions/BetaFeatures \
	&& git checkout -q 27486070bff17b4886543fe8d888585a722c6a76 \
	# BreadCrumbs2
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/BreadCrumbs2.git  $MW_HOME/extensions/BreadCrumbs2 \
	&& cd $MW_HOME/extensions/BreadCrumbs2 \
	&& git fetch "https://gerrit.wikimedia.org/r/mediawiki/extensions/BreadCrumbs2" refs/changes/03/701603/1 \
	&& git checkout FETCH_HEAD \
	# Cargo
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/Cargo $MW_HOME/extensions/Cargo \
	&& cd $MW_HOME/extensions/Cargo \
	&& git checkout -q 479026a912fc2529d1f367fc4a85f79f5da24f93 \
	# ChangeAuthor
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ChangeAuthor $MW_HOME/extensions/ChangeAuthor \
	&& cd $MW_HOME/extensions/ChangeAuthor \
	&& git checkout -q 2afac6dcc34264de8f952ab89c4c0332ddb67051 \
	# CharInsert
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CharInsert $MW_HOME/extensions/CharInsert \
	&& cd $MW_HOME/extensions/CharInsert \
	&& git checkout -q 98fa7c3c8b114a565c2e63e52319ea5382ed695a \
	# CheckUser
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CheckUser $MW_HOME/extensions/CheckUser \
	&& cd $MW_HOME/extensions/CheckUser \
	&& git checkout -q 025d552c4ca4968cca8a8717b25129d62147c9a7 \
	# CirrusSearch
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CirrusSearch $MW_HOME/extensions/CirrusSearch \
	&& cd $MW_HOME/extensions/CirrusSearch \
	&& git checkout -q 203237ef2828c46094c5f6ba26baaeff2ab3596b \
	# CodeMirror
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CodeMirror $MW_HOME/extensions/CodeMirror \
	&& cd $MW_HOME/extensions/CodeMirror \
	&& git checkout -q 84846ec71fb3be844771025ddd9c039da3cc1616 \
	# Collection
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Collection $MW_HOME/extensions/Collection \
	&& cd $MW_HOME/extensions/Collection \
	&& git checkout -q c22330cb462cbcb7e01da48b7ab1e0caa4e3841f \
	# CommentStreams
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CommentStreams $MW_HOME/extensions/CommentStreams \
	&& cd $MW_HOME/extensions/CommentStreams \
	&& git checkout -q 91161ea4cf31df54229b5881a7f96bcbd6fa48ff \
	# CommonsMetadata
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/CommonsMetadata $MW_HOME/extensions/CommonsMetadata \
	&& cd $MW_HOME/extensions/CommonsMetadata \
	&& git checkout -q badf499682be04d2b2b1139ae9063fb7b436daa3 \
	# ConfirmAccount
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ConfirmAccount $MW_HOME/extensions/ConfirmAccount \
	&& cd $MW_HOME/extensions/ConfirmAccount \
	&& git checkout -q cde8cece830eaeebf66d0d96dc09a206683435c7 \
	# ContactPage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ContactPage $MW_HOME/extensions/ContactPage \
	&& cd $MW_HOME/extensions/ContactPage \
	&& git checkout -q 0466489a8c2ad8f5c045b145cb8b65bb8b164c48 \
	# ContributionScores
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ContributionScores $MW_HOME/extensions/ContributionScores \
	&& cd $MW_HOME/extensions/ContributionScores \
	&& git checkout -q de75d9f6904e9b41f7148417cc9fd491164da722 \
	# DataTransfer
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/DataTransfer $MW_HOME/extensions/DataTransfer \
	&& cd $MW_HOME/extensions/DataTransfer \
	&& git checkout -q 138d06f75f3cbe4097f85b203d760da277c419b8 \
	# Description2
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Description2 $MW_HOME/extensions/Description2 \
	&& cd $MW_HOME/extensions/Description2 \
	&& git checkout -q c471ce36b822e74104a38e302bd59b993c679d72 \
	# Disambiguator
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Disambiguator $MW_HOME/extensions/Disambiguator \
	&& cd $MW_HOME/extensions/Disambiguator \
	&& git checkout -q 06cae54808417caa72c6fe6702af23da5f4c45c5 \
	# DismissableSiteNotice
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/DismissableSiteNotice $MW_HOME/extensions/DismissableSiteNotice \
	&& cd $MW_HOME/extensions/DismissableSiteNotice \
	&& git checkout -q ad3a7802f78498e748833886613e28b4f7cb91b8 \
	# DisplayTitle
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/DisplayTitle $MW_HOME/extensions/DisplayTitle \
	&& cd $MW_HOME/extensions/DisplayTitle \
	&& git checkout -q 4f3f66c524465b26b3ee66029a4500966ba29ab2 \
	# Echo
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Echo $MW_HOME/extensions/Echo \
	&& cd $MW_HOME/extensions/Echo \
	&& git checkout -q a3dedc0d64380d74d2e153aad9a8d54cee1b85bd \
	# Elastica
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Elastica $MW_HOME/extensions/Elastica \
	&& cd $MW_HOME/extensions/Elastica \
	&& git checkout -q 8af6b458adf628a98af4ba8e407f9c676bf4a4fb \
	# EmbedVideo
	&& git clone --single-branch -b master https://gitlab.com/hydrawiki/extensions/EmbedVideo.git $MW_HOME/extensions/EmbedVideo \
	&& cd $MW_HOME/extensions/EmbedVideo \
	&& git checkout -q 85c5219593cc86367ffb17bfb650f73ca3eb9b11 \
	# EncryptedUploads
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/EncryptedUploads $MW_HOME/extensions/EncryptedUploads \
	&& cd $MW_HOME/extensions/EncryptedUploads \
	&& git checkout -q 51e3482462f1852e289d5863849b164e1b1a7ea9 \
	# EventLogging
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/EventLogging $MW_HOME/extensions/EventLogging \
	&& cd $MW_HOME/extensions/EventLogging \
	&& git checkout -q 71f88485e0bea9c668dec20e018d3da2d444585e \
	# EventStreamConfig
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/EventStreamConfig $MW_HOME/extensions/EventStreamConfig \
	&& cd $MW_HOME/extensions/EventStreamConfig \
	&& git checkout -q bce5bc385b2919cf294a074b64bc330ac48f78db \
	# ExternalData
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/ExternalData $MW_HOME/extensions/ExternalData \
	&& cd $MW_HOME/extensions/ExternalData \
	&& git checkout -q 6cb6d70c1ff3104c4337847a54a6980798d63299 \
	# Favorites
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Favorites $MW_HOME/extensions/Favorites \
	&& cd $MW_HOME/extensions/Favorites \
	&& git checkout -q 782afc856a35c37b1a508ce37f7402954cc32efb \
	# FixedHeaderTable
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/FixedHeaderTable $MW_HOME/extensions/FixedHeaderTable \
	&& cd $MW_HOME/extensions/FixedHeaderTable \
	&& git checkout -q 5096d0f2cfc2409612484774541cd485494ee7ea \
	# Flow
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Flow $MW_HOME/extensions/Flow \
	&& cd $MW_HOME/extensions/Flow \
	&& git checkout -q d37f94241d8cb94ac96c7946f83c1038844cf7e6 \
	# GlobalNotice
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/GlobalNotice $MW_HOME/extensions/GlobalNotice \
	&& cd $MW_HOME/extensions/GlobalNotice \
	&& git checkout -q f86637d27e6be7c60ec12bb8859f4b76cceb1be2 \
	# GoogleAnalyticsMetrics
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/GoogleAnalyticsMetrics $MW_HOME/extensions/GoogleAnalyticsMetrics \
	&& cd $MW_HOME/extensions/GoogleAnalyticsMetrics \
	&& git checkout -q c292c17b2e1f44f11a82323b48ec2911c384a085 \
	# GoogleDocCreator
	&& git clone --single-branch -b master https://github.com/nischayn22/GoogleDocCreator.git $MW_HOME/extensions/GoogleDocCreator \
	&& cd $MW_HOME/extensions/GoogleDocCreator \
	&& git checkout -q 63aecabb4292ad9d4e8336a93aec25f977ee633e \
	# GoogleDocTag
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/GoogleDocTag $MW_HOME/extensions/GoogleDocTag \
	&& cd $MW_HOME/extensions/GoogleDocTag \
	&& git checkout -q f9fdb27250112fd02d9ff8eeb2a54ecd8c49b08d \
	# HeaderFooter
	&& git clone https://github.com/enterprisemediawiki/HeaderFooter.git $MW_HOME/extensions/HeaderFooter \
	&& cd $MW_HOME/extensions/HeaderFooter \
	&& git checkout -q eee7d2c1a3373c7d6b326fd460e5d4859dd22c40 \
	# HeaderTabs
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/HeaderTabs $MW_HOME/extensions/HeaderTabs \
	&& cd $MW_HOME/extensions/HeaderTabs \
	&& git checkout -q 5f18c955d04d2c7810d51ae2a641d62b969aba31 \
	# HeadScript
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/HeadScript $MW_HOME/extensions/HeadScript \
	&& cd $MW_HOME/extensions/HeadScript \
	&& git checkout -q f8245e350d6e3452a20d871240ebb193f69f384d \
	# HTMLTags
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/HTMLTags $MW_HOME/extensions/HTMLTags \
	&& cd $MW_HOME/extensions/HTMLTags \
	&& git checkout -q 3476196e1e46b3cb56035d2151d98797c088bc90 \
	# IframePage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/IframePage $MW_HOME/extensions/IframePage \
	&& cd $MW_HOME/extensions/IframePage \
	&& git checkout -q abbff3dd72194ae7ec07415ff6816170198d1f01 \
	# LabeledSectionTransclusion
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LabeledSectionTransclusion $MW_HOME/extensions/LabeledSectionTransclusion \
	&& cd $MW_HOME/extensions/LabeledSectionTransclusion \
	&& git checkout -q 8b0ba6952488763201a0defef0499c743ef933f7 \
	# Lazyload
	&& git clone --single-branch -b master https://github.com/WikiTeq/mediawiki-lazyload.git $MW_HOME/extensions/Lazyload \
	&& cd $MW_HOME/extensions/Lazyload \
	&& git checkout -q 92172c30ee5ac764627e397b19eddd536155394e \
	# Lingo
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/Lingo $MW_HOME/extensions/Lingo \
	&& cd $MW_HOME/extensions/Lingo \
	&& git checkout -q d59cdaf9afbb98a0a8b507afdb102a2755dd85a1 \
	# LinkSuggest
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LinkSuggest $MW_HOME/extensions/LinkSuggest \
	&& cd $MW_HOME/extensions/LinkSuggest \
	&& git checkout -q 44f905ee4e7ac8349a822bfd9d22f79a1e24e4a4 \
	# LinkTarget
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/LinkTarget $MW_HOME/extensions/LinkTarget \
	&& cd $MW_HOME/extensions/LinkTarget \
	&& git checkout -q ab1aba0a4a138f80c4cd9c86cc53259ca0fe4545 \
	# LockAuthor
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/LockAuthor $MW_HOME/extensions/LockAuthor \
	&& cd $MW_HOME/extensions/LockAuthor \
	&& git checkout -q ee5ab1ed2bc34ab1b08c799fb1e14e0d5de65953 \
	# Lockdown
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Lockdown $MW_HOME/extensions/Lockdown \
	&& cd $MW_HOME/extensions/Lockdown \
	&& git checkout -q 4d595408c96190a1c44cfed96f244988fc88054a \
	# LookupUser
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/LookupUser $MW_HOME/extensions/LookupUser \
	&& cd $MW_HOME/extensions/LookupUser \
	&& git checkout -q 57d8f2df716758f87e2286c52f0bdea78a8a85cf \
	# Loops
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Loops $MW_HOME/extensions/Loops \
	&& cd $MW_HOME/extensions/Loops \
	&& git checkout -q f0f1191f56e6b31b063f59ee2710a6f62890a336 \
	# MassMessage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MassMessage $MW_HOME/extensions/MassMessage \
	&& cd $MW_HOME/extensions/MassMessage \
	&& git checkout -q 4c6be095fcb1eb2d741881773a6b8ef0487871af \
	# MassMessageEmail
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MassMessageEmail $MW_HOME/extensions/MassMessageEmail \
	&& cd $MW_HOME/extensions/MassMessageEmail \
	&& git checkout -q 2424d03ac7b53844d49379cba3cceb5d9f4b578e \
	# MassPasswordReset
	&& git clone --single-branch -b master https://github.com/nischayn22/MassPasswordReset.git $MW_HOME/extensions/MassPasswordReset \
	&& cd $MW_HOME/extensions/MassPasswordReset \
	&& git checkout -q affaeee6620f9a70b9dc80c53879a35c9aed92c6 \
	# Math
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Math $MW_HOME/extensions/Math \
	&& cd $MW_HOME/extensions/Math \
	&& git checkout -q ce438004cb7366860d3bff1f60839ef3c304aa1e \
	# MobileDetect
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MobileDetect $MW_HOME/extensions/MobileDetect \
	&& cd $MW_HOME/extensions/MobileDetect \
	&& git checkout -q 017464a0f56fa34fd03118d6502f15c9952f9d9a \
	# MobileFrontend
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MobileFrontend $MW_HOME/extensions/MobileFrontend \
	&& cd $MW_HOME/extensions/MobileFrontend \
	&& git checkout -q db7c7843189a9009dde59503e3e3d4cbcab8eaef \
	# MsUpload
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MsUpload $MW_HOME/extensions/MsUpload \
	&& cd $MW_HOME/extensions/MsUpload \
	&& git checkout -q 583f3a9fdc541ef492f042be3313f4edd47205de \
	# MyVariables
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/MyVariables $MW_HOME/extensions/MyVariables \
	&& cd $MW_HOME/extensions/MyVariables \
	&& git checkout -q cde2562ffde8a1b648be10b78b86386a9c7d3151 \
	# NCBITaxonomyLookup
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/NCBITaxonomyLookup $MW_HOME/extensions/NCBITaxonomyLookup \
	&& cd $MW_HOME/extensions/NCBITaxonomyLookup \
	&& git checkout -q 512a390a62fbe6f3a7480641f6582126678e5a7c \
	# NumerAlpha
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/NumerAlpha $MW_HOME/extensions/NumerAlpha \
	&& cd $MW_HOME/extensions/NumerAlpha \
	&& git checkout -q ab24279b72af1c199651d4630aa198d39344785f \
	# OpenGraphMeta
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/OpenGraphMeta $MW_HOME/extensions/OpenGraphMeta \
	&& cd $MW_HOME/extensions/OpenGraphMeta \
	&& git checkout -q 5bbb2754497515a08562ad6cf62ed51ab9e588bd \
	# OpenIDConnect
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/OpenIDConnect $MW_HOME/extensions/OpenIDConnect \
	&& cd $MW_HOME/extensions/OpenIDConnect \
	&& git checkout -q b44189a2fb29ee45330c64bcf57d6537f63b18df \
	# PageExchange
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/PageExchange $MW_HOME/extensions/PageExchange \
	&& cd $MW_HOME/extensions/PageExchange \
	&& git checkout -q 59d6d64fce6cbe40de6ebe07a0f3d65635aea30e \
	# PageForms
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/PageForms $MW_HOME/extensions/PageForms \
	&& cd $MW_HOME/extensions/PageForms \
	&& git checkout -q 01a2363f7520668c1cde7d4568cb8b00da0b394b \
	# PluggableAuth
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/PluggableAuth $MW_HOME/extensions/PluggableAuth \
	&& cd $MW_HOME/extensions/PluggableAuth \
	&& git checkout -q d036ae0bf509ce160c4f6a1965c795d4fdae82b4 \
	# Popups
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Popups $MW_HOME/extensions/Popups \
	&& cd $MW_HOME/extensions/Popups \
	&& git checkout -q dccd60752353eac1063a79f81a8059b3b06b9353 \
	# PubmedParser
	&& git clone --single-branch -b main https://github.com/bovender/PubmedParser.git $MW_HOME/extensions/PubmedParser \
	&& cd $MW_HOME/extensions/PubmedParser \
	&& git checkout -q 9cd01d828b23853e3e790dc7bf49cdd230847272 \
	# RevisionSlider
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/RevisionSlider $MW_HOME/extensions/RevisionSlider \
	&& cd $MW_HOME/extensions/RevisionSlider \
	&& git checkout -q d1a6af207e26e220d93d16381a58055259575d3b \
	# RottenLinks
	&& git clone --single-branch -b master https://github.com/miraheze/RottenLinks.git $MW_HOME/extensions/RottenLinks \
	&& cd $MW_HOME/extensions/RottenLinks \
	&& git checkout -q 4e7e675bb26fc39b85dd62c9ad37e29d8f705a41 \
	# SandboxLink
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SandboxLink $MW_HOME/extensions/SandboxLink \
	&& cd $MW_HOME/extensions/SandboxLink \
	&& git checkout -q 2d7123c29b5e61f2c7d6e81168dc6d261ff93cbd \
	# SaveSpinner
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SaveSpinner $MW_HOME/extensions/SaveSpinner \
	&& cd $MW_HOME/extensions/SaveSpinner \
	&& git checkout -q 2f19bdd7c6cc48729faa4b8e9afc8953dbeaeae1 \
	# Scopus
	&& git clone --single-branch -b master https://github.com/nischayn22/Scopus.git $MW_HOME/extensions/Scopus \
	&& cd $MW_HOME/extensions/Scopus \
	&& git checkout -q 4fe8048459d9189626d82d9d93a0d5f906c43746 \
	# SelectCategory
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SelectCategory $MW_HOME/extensions/SelectCategory \
	&& cd $MW_HOME/extensions/SelectCategory \
	&& git checkout -q 4c28f553dcec7534e0d403fb3e1b45bbfafb21ad \
	# SemanticDrilldown
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SemanticDrilldown $MW_HOME/extensions/SemanticDrilldown \
	&& cd $MW_HOME/extensions/SemanticDrilldown \
	&& git checkout -q 8e03672100457ebfcd65f4b94fd60af80c2eaf4a \
	# SemanticExternalQueryLookup (WikiTeq's fork)
	&& git clone --single-branch -b master https://github.com/WikiTeq/SemanticExternalQueryLookup.git $MW_HOME/extensions/SemanticExternalQueryLookup \
	&& cd $MW_HOME/extensions/SemanticExternalQueryLookup \
	&& git checkout -q dd7810061f2f1a9eef7be5ee09da999cbf9ecd8a \
	# SemanticQueryInterface
	&& git clone --single-branch -b master https://github.com/vedmaka/SemanticQueryInterface.git $MW_HOME/extensions/SemanticQueryInterface \
	&& cd $MW_HOME/extensions/SemanticQueryInterface \
	&& git checkout -q 0016305a95ecbb6ed4709bfa3fc6d9995d51336f \
	&& mv $MW_HOME/extensions/SemanticQueryInterface/SemanticQueryInterface/* $MW_HOME/extensions/SemanticQueryInterface/ \
	&& rmdir $MW_HOME/extensions/SemanticQueryInterface/SemanticQueryInterface \
	&& ln -s $MW_HOME/extensions/SemanticQueryInterface/SQI.php $MW_HOME/extensions/SemanticQueryInterface/SemanticQueryInterface.php \
	&& rm -fr $MW_HOME/extensions/SemanticQueryInterface/.git \
	# SimpleChanges
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SimpleChanges $MW_HOME/extensions/SimpleChanges \
	&& cd $MW_HOME/extensions/SimpleChanges \
	&& git checkout -q c0991c9245dc8907e59f8e4c6fb89852f0c52dde \
	# SimpleMathJax
	&& git clone --single-branch https://github.com/jmnote/SimpleMathJax.git $MW_HOME/extensions/SimpleMathJax \
	&& cd $MW_HOME/extensions/SimpleMathJax \
	&& git checkout -q ddcac9ac1616aed794576f2914ee426879194f0f \
	# SimpleTooltip
	&& git clone --single-branch -b master https://github.com/Fannon/SimpleTooltip.git $MW_HOME/extensions/SimpleTooltip \
	&& cd $MW_HOME/extensions/SimpleTooltip \
	&& git checkout -q 2476bff8f4555f86795c26ca5fdb7db99bfe58d1 \
	# ShowMe
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/ShowMe $MW_HOME/extensions/ShowMe \
	&& cd $MW_HOME/extensions/ShowMe \
	&& git checkout -q 368f7a9cdd151a9fb198c83ca9a48efacf6b2b1f \
	# SkinPerPage
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SkinPerPage $MW_HOME/extensions/SkinPerPage \
	&& cd $MW_HOME/extensions/SkinPerPage \
	&& git checkout -q b929bc6e56b51a8356c04b3761c262b6a9a423e3 \
	# SocialProfile
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SocialProfile $MW_HOME/extensions/SocialProfile \
	&& cd $MW_HOME/extensions/SocialProfile \
	&& git checkout -q d34f32174c23818dbf057a5482dc6ed4781a3a25 \
	# SRFEventCalendarMod
	&& git clone --single-branch -b master https://github.com/vedmaka/mediawiki-extension-SRFEventCalendarMod.git $MW_HOME/extensions/SRFEventCalendarMod \
	&& cd $MW_HOME/extensions/SRFEventCalendarMod \
	&& git checkout -q e0dfa797af0709c90f9c9295d217bbb6d564a7a8 \
	# Sync
	&& git clone --single-branch -b master https://github.com/nischayn22/Sync.git $MW_HOME/extensions/Sync \
	&& cd $MW_HOME/extensions/Sync \
	&& git checkout -q f56b956521f383221737261ad68aef2367466b76 \
	# Tabber
	&& git clone --single-branch -b master https://gitlab.com/hydrawiki/extensions/Tabber.git $MW_HOME/extensions/Tabber \
	&& cd $MW_HOME/extensions/Tabber \
	&& git checkout -q 6c67baf4d18518fa78e07add4c032d62dd384b06 \
	# Tabs
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Tabs $MW_HOME/extensions/Tabs \
	&& cd $MW_HOME/extensions/Tabs \
	&& git checkout -q 1d669869c746183f9972ab7201e7e4981a248311 \
	# TalkRight
	&& git clone https://github.com/enterprisemediawiki/TalkRight.git $MW_HOME/extensions/TalkRight \
	&& cd $MW_HOME/extensions/TalkRight \
	&& git checkout -q cc966969e11bd0d72e118d326ebff216d623e06b \
	# TemplateStyles
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TemplateStyles $MW_HOME/extensions/TemplateStyles \
	&& cd $MW_HOME/extensions/TemplateStyles \
	&& git checkout -q a859a0c0b742af1709d5b836737ff93ffa5a43c9 \
	# Thanks
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Thanks $MW_HOME/extensions/Thanks \
	&& cd $MW_HOME/extensions/Thanks \
	&& git checkout -q e28a16d38b5a4c0d32f2388aa4fcc93ec48e7b02 \
	# TimedMediaHandler
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TimedMediaHandler $MW_HOME/extensions/TimedMediaHandler \
	&& cd $MW_HOME/extensions/TimedMediaHandler \
	&& git checkout -q 6d922042852cd9c6b02a406ccfcc0dae8533624b \
	# TinyMCE
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TinyMCE $MW_HOME/extensions/TinyMCE \
	&& cd $MW_HOME/extensions/TinyMCE \
	&& git checkout -q 587bbb0b98044ae4904cf67f104d0cf27bd6972d \
	# TwitterTag
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/TwitterTag $MW_HOME/extensions/TwitterTag \
	&& cd $MW_HOME/extensions/TwitterTag \
	&& git checkout -q 6758d15d8e4f0553bbcbc7af026ba245f1ff9282 \
	# UniversalLanguageSelector
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UniversalLanguageSelector $MW_HOME/extensions/UniversalLanguageSelector \
	&& cd $MW_HOME/extensions/UniversalLanguageSelector \
	&& git checkout -q e7ab607dd91b55f15a733bcba793619cf48d3604 \
	# UploadWizard
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UploadWizard $MW_HOME/extensions/UploadWizard \
	&& cd $MW_HOME/extensions/UploadWizard \
	&& git checkout -q c54e588bac935db78fad297602f61d47ed2162d5 \
	# UploadWizardExtraButtons
	&& git clone --single-branch -b master https://github.com/vedmaka/mediawiki-extension-UploadWizardExtraButtons.git $MW_HOME/extensions/UploadWizardExtraButtons \
	&& cd $MW_HOME/extensions/UploadWizardExtraButtons \
	&& git checkout -q accba1b9b6f50e67d709bd727c9f4ad6de78c0c0 \
	# UrlGetParameters
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UrlGetParameters $MW_HOME/extensions/UrlGetParameters \
	&& cd $MW_HOME/extensions/UrlGetParameters \
	&& git checkout -q 163df22a566c34e0717ed8a7154f40dfb71cef4f \
	# UserMerge
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/UserMerge $MW_HOME/extensions/UserMerge \
	&& cd $MW_HOME/extensions/UserMerge \
	&& git checkout -q 1c161b2c12c3882b4230561d1834e7c5170d9200 \
	# Variables
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Variables $MW_HOME/extensions/Variables \
	&& cd $MW_HOME/extensions/Variables \
	&& git checkout -q e20f4c7469bdc724ccc71767ed86deec3d1c3325 \
	# VEForAll TODO (version 0.3, master), switch back to REL_x for 1.36
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/VEForAll $MW_HOME/extensions/VEForAll \
	&& cd $MW_HOME/extensions/VEForAll \
	&& git checkout -q 8f83eb6e607b89f6e1a44966e8637cadd7942bd7 \
	# VoteNY
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/VoteNY $MW_HOME/extensions/VoteNY \
	&& cd $MW_HOME/extensions/VoteNY \
	&& git checkout -q b73dd009cf151a9f442361f6eb1e355817ca1e18 \
	# WhoIsWatching
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/WhoIsWatching $MW_HOME/extensions/WhoIsWatching \
	&& cd $MW_HOME/extensions/WhoIsWatching \
	&& git checkout -q 510e95a76fe140890ea83abf75be64ce97f7fd30 \
	# Widgets
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/Widgets $MW_HOME/extensions/Widgets \
	&& cd $MW_HOME/extensions/Widgets \
	&& git checkout -q e9ebcb7a60e04a4b6054538032d1d2e1badf9934 \
	# WikiForum
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/WikiForum $MW_HOME/extensions/WikiForum \
	&& cd $MW_HOME/extensions/WikiForum \
	&& git checkout -q 9cffc82dfd761fbb7a91aa778fb6633215c47501 \
	# WikiSEO
	&& git clone --single-branch -b master https://gerrit.wikimedia.org/r/mediawiki/extensions/WikiSEO $MW_HOME/extensions/WikiSEO \
	&& cd $MW_HOME/extensions/WikiSEO \
	&& git checkout -q 2c0a40267e9e1abd087cf3fd378cc508b8562f9f \
	# Wiretap
	&& git clone https://github.com/enterprisemediawiki/Wiretap.git $MW_HOME/extensions/Wiretap \
	&& cd $MW_HOME/extensions/Wiretap \
	&& git checkout -q a97b708c3093ea66e7cf625859b1b38178526bab \
	# YouTube
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/YouTube $MW_HOME/extensions/YouTube \
	&& cd $MW_HOME/extensions/YouTube \
	&& git checkout -q bd736585dca8412d5eb9dde8f68a54b3c69df9cf

# ReplaceText (switch to more recent commit due to bug on submodule HEAD)
RUN set -x; \
	cd $MW_HOME/extensions/ReplaceText \
	&& git checkout -q 109d24b690b9096863513bdea642f88c062a3b0b

# GTag1
COPY _sources/extensions/GTag1.2.0.tar.gz /tmp/
RUN set -x; \
    tar -xvf /tmp/GTag*.tar.gz -C $MW_HOME/extensions \
    && rm /tmp/GTag*.tar.gz

# GoogleAnalyticsMetrics: Resolve composer conflicts, so placed before the composer install statement!
COPY _sources/patches/core-fix-composer-for-GoogleAnalyticsMetrics.diff /tmp/core-fix-composer-for-GoogleAnalyticsMetrics.diff
RUN set -x; \
	cd $MW_HOME \
	&& git apply /tmp/core-fix-composer-for-GoogleAnalyticsMetrics.diff

# Composer dependencies
COPY _sources/configs/composer.local.json $MW_HOME/composer.local.json
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

# PageForms
COPY _sources/patches/PageForms.01a2363f7520668c1cde7d4568cb8b00da0b394b.VeForAll.patch /tmp/PageForms.01a2363f7520668c1cde7d4568cb8b00da0b394b.VeForAll.patch
RUN set -x; \
	cd $MW_HOME/extensions/PageForms \
    && git apply /tmp/PageForms.01a2363f7520668c1cde7d4568cb8b00da0b394b.VeForAll.patch

# SemanticResultFormats, see https://github.com/WikiTeq/SemanticResultFormats/compare/master...WikiTeq:fix1_35
COPY _sources/patches/semantic-result-formats.patch /tmp/semantic-result-formats.patch
RUN set -x; \
	cd $MW_HOME/extensions/SemanticResultFormats \
	&& patch < /tmp/semantic-result-formats.patch

# Fixes PHP parsoid errors when user replies on a flow message, see https://phabricator.wikimedia.org/T260648#6645078
COPY _sources/patches/flow-conversion-utils.patch /tmp/flow-conversion-utils.patch
RUN set -x; \
	cd $MW_HOME/extensions/Flow \
	&& git checkout d37f94241d8cb94ac96c7946f83c1038844cf7e6 \
	&& git apply /tmp/flow-conversion-utils.patch

# SWM maintenance page returns 503 (Service Unavailable) status code, PR: https://github.com/SemanticMediaWiki/SemanticMediaWiki/pull/4967
COPY _sources/patches/smw-maintenance-503.patch /tmp/smw-maintenance-503.patch
RUN set -x; \
	cd $MW_HOME/extensions/SemanticMediaWiki \
	&& patch -u -b src/SetupCheck.php -i /tmp/smw-maintenance-503.patch

# TODO send to upstream, see https://wikiteq.atlassian.net/browse/MW-64 and https://wikiteq.atlassian.net/browse/MW-81
COPY _sources/patches/skin-refreshed.patch /tmp/skin-refreshed.patch
RUN set -x; \
	cd $MW_HOME/skins/Refreshed \
	&& patch -u -b includes/RefreshedTemplate.php -i /tmp/skin-refreshed.patch

# Allow to modify headelement in the Vector skin, see https://wikiteq.atlassian.net/browse/FAM-7
COPY _sources/patches/skin-vector-addVectorGeneratedSkinDataHook.patch /tmp/skin-vector-addVectorGeneratedSkinDataHook.patch
RUN set -x; \
	cd $MW_HOME/skins/Vector \
	&& git apply /tmp/skin-vector-addVectorGeneratedSkinDataHook.patch

# TODO: remove for 1.36+, see https://phabricator.wikimedia.org/T281043
COPY _sources/patches/social-profile-REL1_35.44b4f89.diff /tmp/social-profile-REL1_35.44b4f89.diff
RUN set -x; \
    cd $MW_HOME/extensions/SocialProfile \
    && git apply /tmp/social-profile-REL1_35.44b4f89.diff

# WikiTeq's patch allowing to manage fields visibility site-wide
COPY _sources/patches/SocialProfile-disable-fields.patch /tmp/SocialProfile-disable-fields.patch
RUN set -x; \
    cd $MW_HOME/extensions/SocialProfile \
    && git apply /tmp/SocialProfile-disable-fields.patch

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
    && for i in $(ls -d */); do echo "#cfLoadSkin('${i%%/}');"; done > $MW_ORIGIN_FILES/installedSkins.txt

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
    && ln -s $MW_VOLUME/cache $MW_HOME/cache \
    # Create placeholder symlink for the LocalSettings file
    && ln -s $MW_VOLUME/config/LocalSettings.php $MW_HOME/LocalSettings.php

FROM base as final

COPY --from=source $MW_HOME $MW_HOME
COPY --from=source $MW_ORIGIN_FILES $MW_ORIGIN_FILES

# Default values
ENV MW_ENABLE_JOB_RUNNER=true \
	MW_JOB_RUNNER_PAUSE=2 \
	MW_ENABLE_TRANSCODER=true \
	MW_JOB_TRANSCODER_PAUSE=60 \
	MW_ENABLE_SITEMAP_GENERATOR=true \
	MW_SITEMAP_PAUSE_DAYS=1 \
	MW_SITEMAP_SUBDIR="" \
	MW_SITEMAP_IDENTIFIER="mediawiki" \
	PHP_UPLOAD_MAX_FILESIZE=10M \
	PHP_POST_MAX_SIZE=10M \
	PHP_MAX_INPUT_VARS=1000 \
	LOG_FILES_COMPRESS_DELAY=3600 \
	LOG_FILES_REMOVE_OLDER_THAN_DAYS=10

COPY _sources/configs/.msmtprc /etc/
COPY _sources/configs/mediawiki.conf /etc/apache2/sites-enabled/
COPY _sources/configs/php_error_reporting.ini _sources/configs/php_upload_max_filesize.ini /etc/php/7.4/cli/conf.d/
COPY _sources/configs/php_error_reporting.ini _sources/configs/php_upload_max_filesize.ini /etc/php/7.4/apache2/conf.d/
COPY _sources/configs/php_max_input_vars.ini _sources/configs/php_max_input_vars.ini /etc/php/7.4/apache2/conf.d/
COPY _sources/scripts/*.sh /
COPY _sources/configs/robots.txt $WWW_ROOT/
COPY _sources/configs/.htaccess $WWW_ROOT/
COPY _sources/canasta/CanastaUtils.php $MW_HOME/
COPY _sources/canasta/getMediawikiSettings.php /
COPY _sources/configs/mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf

RUN set -x; \
	chmod -v +x /*.sh \
	# Sitemap directory
	&& ln -s $MW_VOLUME/sitemap $MW_HOME/sitemap \
	# Comment out ErrorLog and CustomLog parameters, we use rotatelogs in mediawiki.conf for the log files
	&& sed -i 's/^\(\s*ErrorLog .*\)/# \1/g' /etc/apache2/apache2.conf \
	&& sed -i 's/^\(\s*CustomLog .*\)/# \1/g' /etc/apache2/apache2.conf \
    # Modify config
    && sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

EXPOSE 80
WORKDIR $MW_HOME

HEALTHCHECK --interval=1m --timeout=10s \
	CMD wget -q --method=HEAD localhost/w/api.php

CMD ["/run-apache.sh"]
