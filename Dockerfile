FROM debian:11.7 as base

LABEL maintainers=""
LABEL org.opencontainers.image.source=https://github.com/CanastaWiki/Canasta

ENV MW_VERSION=REL1_39 \
	MW_CORE_VERSION=1.39.6 \
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
	inotify-tools \
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
	php7.4-intl \
	php7.4-opcache \
	php7.4-apcu \
	php7.4-redis \
	php7.4-curl \
	php7.4-zip \
	php7.4-fpm \
	libapache2-mod-fcgid \
	libfcgi-bin \
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
	&& a2enconf php7.4-fpm \
	&& a2enmod mpm_event \
	&& a2enmod proxy_fcgi \
    # Create directories
    && mkdir -p $MW_HOME \
    && mkdir -p $MW_ORIGIN_FILES \
    && mkdir -p $MW_VOLUME

# Composer
RUN set -x; \
	curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer self-update 2.1.3

FROM base as source

# MediaWiki core
RUN set -x; \
	git clone --depth 1 -b $MW_CORE_VERSION https://github.com/wikimedia/mediawiki $MW_HOME \
	&& cd $MW_HOME \
	&& git submodule update --init --recursive

# Skins
# The Minerva Neue, MonoBook, Timeless, Vector and Vector 2022 skins are bundled into MediaWiki and do not need to be
# separately installed.
RUN set -x; \
	cd $MW_HOME/skins \
 	# Chameleon (v. 4.2.1)
  	&& git clone https://github.com/ProfessionalWiki/chameleon $MW_HOME/skins/chameleon \
	&& cd $MW_HOME/skins/chameleon \
	&& git checkout -q f34a56528ada14ac07e1b03beda41f775ef27606 \
	# CologneBlue
	&& git clone -b $MW_VERSION --single-branch https://github.com/wikimedia/mediawiki-skins-CologneBlue $MW_HOME/skins/CologneBlue \
	&& cd $MW_HOME/skins/CologneBlue \
	&& git checkout -q 4d588eb78d7e64e574f631c5897579537305437d \
	# Modern
	&& git clone -b $MW_VERSION --single-branch https://github.com/wikimedia/mediawiki-skins-Modern $MW_HOME/skins/Modern \
	&& cd $MW_HOME/skins/Modern \
	&& git checkout -q fb6c2831b5f150e9b82d98d661710695a2d0f8f2 \
	# Pivot
	&& git clone -b v2.3.0 https://github.com/wikimedia/mediawiki-skins-Pivot $MW_HOME/skins/pivot \
	&& cd $MW_HOME/skins/pivot \
	&& git checkout -q d79af7514347eb5272936243d4013118354c85c1 \
	# Refreshed
	&& git clone -b $MW_VERSION --single-branch https://github.com/wikimedia/mediawiki-skins-Refreshed $MW_HOME/skins/Refreshed \
	&& cd $MW_HOME/skins/Refreshed \
	&& git checkout -q 86f33620f25335eb62289aa18d342ff3b980d8b8

# Extensions
# The following extensions are bundled into MediaWiki and do not need to be separately installed:
# AbuseFilter, CategoryTree, Cite, CiteThisPage, CodeEditor, ConfirmEdit, Gadgets, ImageMap, InputBox, Interwiki,
# Math, MultimediaViewer, Nuke, OATHAuth, PageImages, ParserFunctions, PdfHandler, Poem, Renameuser, Replace Text,
# Scribunto, SecureLinkFixer, SpamBlacklist, SyntaxHighlight, TemplateData, TextExtracts, TitleBlacklist,
# VisualEditor, WikiEditor.
# The following extensions are downloaded via Composer and also do not need to be downloaded here:
# Bootstrap, DataValues (and related extensions like DataValuesCommon), ParserHooks.
RUN set -x; \
	cd $MW_HOME/extensions \
	# AdminLinks (v. 0.6.1)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-AdminLinks $MW_HOME/extensions/AdminLinks \
	&& cd $MW_HOME/extensions/AdminLinks \
	&& git checkout -q 3e2671c21fd4b8644552069ee60220035b6e96f5 \
	# AdvancedSearch
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-AdvancedSearch $MW_HOME/extensions/AdvancedSearch \
	&& cd $MW_HOME/extensions/AdvancedSearch \
	&& git checkout -q 1a44eafc93a17938333b74a37cb4deff2192e50a \
	# AJAXPoll
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-AJAXPoll $MW_HOME/extensions/AJAXPoll \
	&& cd $MW_HOME/extensions/AJAXPoll \
	&& git checkout -q 8429d8d4cba5be6df04e3fec17b0daabbf10cfa7 \
	# AntiSpoof
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-AntiSpoof $MW_HOME/extensions/AntiSpoof \
	&& cd $MW_HOME/extensions/AntiSpoof \
	&& git checkout -q 01cf89a678d5bab6610d24e07d3534356a5880cb \
	# ApprovedRevs (v. 1.8.2)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-ApprovedRevs $MW_HOME/extensions/ApprovedRevs \
	&& cd $MW_HOME/extensions/ApprovedRevs \
	&& git checkout -q 53b67bf7e1e8ac3d20c2fd41ad2ab1c708c045a6 \
	# Arrays
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Arrays $MW_HOME/extensions/Arrays \
	&& cd $MW_HOME/extensions/Arrays \
	&& git checkout -q 338f661bf0ab377f70e029079f2c5c5b370219df \
	# BetaFeatures
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-BetaFeatures $MW_HOME/extensions/BetaFeatures \
	&& cd $MW_HOME/extensions/BetaFeatures \
	&& git checkout -q 09cca44341f9695446c4e9fc9e8fec3fdcb197b0 \
	# BootstrapComponents (v. 5.1.0)
	&& git clone --single-branch -b master https://github.com/oetterer/BootstrapComponents $MW_HOME/extensions/BootstrapComponents \
	&& cd $MW_HOME/extensions/BootstrapComponents \
	&& git checkout -q 665c3dee1d9e3f4bcb18dd1920fe27b70e334574 \
	# BreadCrumbs2
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-BreadCrumbs2 $MW_HOME/extensions/BreadCrumbs2 \
	&& cd $MW_HOME/extensions/BreadCrumbs2 \
	&& git checkout -q d53357a6839e94800a617de4fc451b6c64d0a1c8 \
	# Buggy
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Buggy.git $MW_HOME/extensions/Buggy \
	&& cd $MW_HOME/extensions/Buggy \
	&& git checkout -q 768d2ec62de692ab62fc0c9f1820e22058d09d4b \
	# Cargo (v. 3.4.2)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-Cargo $MW_HOME/extensions/Cargo \
	&& cd $MW_HOME/extensions/Cargo \
	&& git checkout -q 7e8ea881cdb41e79687d059670fc68872a6a892c \
	# CharInsert
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-CharInsert $MW_HOME/extensions/CharInsert \
	&& cd $MW_HOME/extensions/CharInsert \
	&& git checkout -q 54c0f0ca9119a3ce791fb5d53edd4ec32035a5c5 \
	# CheckUser
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-CheckUser $MW_HOME/extensions/CheckUser \
	&& cd $MW_HOME/extensions/CheckUser \
	&& git checkout -q 9e2b6d3e928855247700146273d8131e025de918 \
	# CirrusSearch
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-CirrusSearch $MW_HOME/extensions/CirrusSearch \
	&& cd $MW_HOME/extensions/CirrusSearch \
	&& git checkout -q 8296300873aaffe815800cf05c84fa04c8cbd2c0 \
	# CodeMirror
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-CodeMirror $MW_HOME/extensions/CodeMirror \
	&& cd $MW_HOME/extensions/CodeMirror \
	&& git checkout -q 27efed79972ca181a194d17f4a94f4192fd5a493 \
	# Collection
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Collection $MW_HOME/extensions/Collection \
	&& cd $MW_HOME/extensions/Collection \
	&& git checkout -q e00e70c6fcec963c8876e410e52c83c75ed60827 \
	# CommentStreams
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-CommentStreams $MW_HOME/extensions/CommentStreams \
	&& cd $MW_HOME/extensions/CommentStreams \
	&& git checkout -q 274bb10bc2d39fd137650dbc0dfc607c766d1aaa \
	# CommonsMetadata
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-CommonsMetadata $MW_HOME/extensions/CommonsMetadata \
	&& cd $MW_HOME/extensions/CommonsMetadata \
	&& git checkout -q 8ee30de3b1cabbe55c484839127493fd5fa5d076 \
	# ConfirmAccount
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-ConfirmAccount $MW_HOME/extensions/ConfirmAccount \
	&& cd $MW_HOME/extensions/ConfirmAccount \
	&& git checkout -q c06d5dfb43811a2dee99099476c57af2b6d762c4 \
	# ContactPage
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-ContactPage $MW_HOME/extensions/ContactPage \
	&& cd $MW_HOME/extensions/ContactPage \
	&& git checkout -q f509796056ae1fc597b6e3c3c268fac35bf66636 \
	# ContributionScores
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-ContributionScores $MW_HOME/extensions/ContributionScores \
	&& cd $MW_HOME/extensions/ContributionScores \
	&& git checkout -q e307850555ef313f623dde6e2f1d5d2a43663730 \
	# CookieWarning
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-CookieWarning $MW_HOME/extensions/CookieWarning \
	&& cd $MW_HOME/extensions/CookieWarning \
	&& git checkout -q bc991e93133bd69fe45e07b3d4554225decc7dae \
	# DataTransfer
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-DataTransfer $MW_HOME/extensions/DataTransfer \
	&& cd $MW_HOME/extensions/DataTransfer \
	&& git checkout -q 2f9f949f71f0bb7d1bd8b6b97c795b9428bb1c71 \
	# DeleteBatch
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-DeleteBatch $MW_HOME/extensions/DeleteBatch \
	&& cd $MW_HOME/extensions/DeleteBatch \
	&& git checkout -q 82078d60fc59a718f429ddebe5e99de8a8734413 \
	# Description2
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Description2 $MW_HOME/extensions/Description2 \
	&& cd $MW_HOME/extensions/Description2 \
	&& git checkout -q d2a5322a44f940de873050573e35fba4eb3063f8 \
	# Disambiguator
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Disambiguator $MW_HOME/extensions/Disambiguator \
	&& cd $MW_HOME/extensions/Disambiguator \
	&& git checkout -q b7e7fad5f9f3dccfb902a3cbfd3bf2b16df91871 \
	# DismissableSiteNotice
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-DismissableSiteNotice $MW_HOME/extensions/DismissableSiteNotice \
	&& cd $MW_HOME/extensions/DismissableSiteNotice \
	&& git checkout -q 88129f80f077ec9e4932148056c8cfc1ed0361c7 \
	# DisplayTitle
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-DisplayTitle $MW_HOME/extensions/DisplayTitle \
	&& cd $MW_HOME/extensions/DisplayTitle \
	&& git checkout -q a14c406cc273c73a12957b55a27c095ad98d1795 \
	# Echo
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Echo $MW_HOME/extensions/Echo \
	&& cd $MW_HOME/extensions/Echo \
	&& git checkout -q fdbc2cafdc412dc60d4345511defe9ee393efecf \
	# EditAccount
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-EditAccount.git $MW_HOME/extensions/EditAccount \
	&& cd $MW_HOME/extensions/EditAccount \
	&& git checkout -q abf772dc6ce8f3a31f2d82a1408796c138151ab0 \
	# Editcount
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Editcount $MW_HOME/extensions/Editcount \
	&& cd $MW_HOME/extensions/Editcount \
	&& git checkout -q 41544ffceb1356f91575dc6772a48b172751d7cc \
	# Elastica
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Elastica $MW_HOME/extensions/Elastica \
	&& cd $MW_HOME/extensions/Elastica \
	&& git checkout -q e4ead38b71ed4f3df8dc689fe448b749771b4ed4 \
	# EmailAuthorization
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-EmailAuthorization $MW_HOME/extensions/EmailAuthorization \
	&& cd $MW_HOME/extensions/EmailAuthorization \
	&& git checkout -q 2016da1b354f741d89b5dc207d4a84e11ffe9bce \
	# EmbedVideo
	&& git clone --single-branch -b master https://github.com/StarCitizenWiki/mediawiki-extensions-EmbedVideo.git $MW_HOME/extensions/EmbedVideo \
	&& cd $MW_HOME/extensions/EmbedVideo \
	&& git checkout -q 5c03c031070981730a0e01aa3cbc3e5cbd1b88c1 \
	# EventLogging
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-EventLogging $MW_HOME/extensions/EventLogging \
	&& cd $MW_HOME/extensions/EventLogging \
	&& git checkout -q 2740dbcd139be279ca2a4db039739b4f796b4178 \
	# EventStreamConfig
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-EventStreamConfig $MW_HOME/extensions/EventStreamConfig \
	&& cd $MW_HOME/extensions/EventStreamConfig \
	&& git checkout -q 1aae8cb6c312e49f0126091a59a453cb224657f9 \
	# ExternalData (v. 3.2)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-ExternalData $MW_HOME/extensions/ExternalData \
	&& cd $MW_HOME/extensions/ExternalData \
	&& git checkout -q 5d30e60a65ca53a3fb5b39826deb2e6917892e22 \
	# FlexDiagrams (v. 0.5)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-FlexDiagrams $MW_HOME/extensions/FlexDiagrams \
	&& cd $MW_HOME/extensions/FlexDiagrams \
	&& git checkout -q eefc9e29aedfc6d8ffaf4f4e50043b390ebd7adc \
	# Flow
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Flow.git $MW_HOME/extensions/Flow \
	&& cd $MW_HOME/extensions/Flow \
	&& git checkout -q f2998fd1a0676d26c33d97a8272c76fc68b387b6 \
	# GlobalNotice
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-GlobalNotice $MW_HOME/extensions/GlobalNotice \
	&& cd $MW_HOME/extensions/GlobalNotice \
	&& git checkout -q 15a40bff4641f00a5a8dda3d36795b1c659c19a7 \
	# GoogleAnalyticsMetrics
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-GoogleAnalyticsMetrics $MW_HOME/extensions/GoogleAnalyticsMetrics \
	&& cd $MW_HOME/extensions/GoogleAnalyticsMetrics \
	&& git checkout -q 82a08cc63ec58698f144be7c2fb1a6f861cb57bd \
	# GoogleDocCreator
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-GoogleDocCreator $MW_HOME/extensions/GoogleDocCreator \
	&& cd $MW_HOME/extensions/GoogleDocCreator \
	&& git checkout -q 9e53ecfa4149688a2352a7898c2a2005632e1b7d \
	# Graph
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Graph $MW_HOME/extensions/Graph \
	&& cd $MW_HOME/extensions/Graph \
	&& git checkout -q 9c229eafdf406c95a4a666a6b7f2a9d0d3d682e4 \
	# GTag
	&& git clone https://github.com/SkizNet/mediawiki-GTag $MW_HOME/extensions/GTag \
	&& cd $MW_HOME/extensions/GTag \
	&& git checkout -q d45f54085d003166aa032363408b8dbef7dd3628 \
	# HeaderFooter
	&& git clone -b MW_REL1_39_Compat https://github.com/wikimedia/mediawiki-extensions-HeaderFooter.git $MW_HOME/extensions/HeaderFooter \
	&& cd $MW_HOME/extensions/HeaderFooter \
	&& git checkout -q 8b7e15ca013af371c7f37b0d955ed2039a5e2fbf \
	# HeaderTabs (v2.2)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-HeaderTabs $MW_HOME/extensions/HeaderTabs \
	&& cd $MW_HOME/extensions/HeaderTabs \
	&& git checkout -q 42aaabf1deeb0a228fc99e578ff7ec925e560dd7 \
	# HTMLTags
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-HTMLTags $MW_HOME/extensions/HTMLTags \
	&& cd $MW_HOME/extensions/HTMLTags \
	&& git checkout -q b8cb3131c5e76f5c037c8474fe14e51f2e877f03 \
	# LabeledSectionTransclusion
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-LabeledSectionTransclusion $MW_HOME/extensions/LabeledSectionTransclusion \
	&& cd $MW_HOME/extensions/LabeledSectionTransclusion \
	&& git checkout -q 187abfeaafbad35eed4254f7a7ee0638980e932a \
	# LDAPAuthentication2
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-LDAPAuthentication2 $MW_HOME/extensions/LDAPAuthentication2 \
	&& cd $MW_HOME/extensions/LDAPAuthentication2 \
	&& git checkout -q 6bc584893d3157d5180e0e3ed93c3dbbc5b93056 \
	# LDAPAuthorization
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-LDAPAuthorization $MW_HOME/extensions/LDAPAuthorization \
	&& cd $MW_HOME/extensions/LDAPAuthorization \
	&& git checkout -q e6815d29c22f4b4eb85f868372a729ad49d7d3c8 \
	# LDAPProvider
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-LDAPProvider $MW_HOME/extensions/LDAPProvider \
	&& cd $MW_HOME/extensions/LDAPProvider \
	&& git checkout -q 80f8cc8156b0cd250d0dfacd9378ed0db7c2091d \
	# Lingo
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Lingo $MW_HOME/extensions/Lingo \
	&& cd $MW_HOME/extensions/Lingo \
	&& git checkout -q a291fa25822097a4a2aefff242a876edadb535a4 \
	# LinkSuggest
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-LinkSuggest $MW_HOME/extensions/LinkSuggest \
	&& cd $MW_HOME/extensions/LinkSuggest \
	&& git checkout -q 6005d191e35d1d6bed5a4e7bd1bedc5fa0030bf1 \
	# LinkTarget
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-LinkTarget $MW_HOME/extensions/LinkTarget \
	&& cd $MW_HOME/extensions/LinkTarget \
	&& git checkout -q e5d592dcc72a00e06604ee3f65dfb8f99977c156 \
	# Linter
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Linter $MW_HOME/extensions/Linter \
	&& cd $MW_HOME/extensions/Linter \
	&& git checkout -q 8bc1727955da7468f096aa5c5b5790923db43d20 \
	# LockAuthor
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-LockAuthor $MW_HOME/extensions/LockAuthor \
	&& cd $MW_HOME/extensions/LockAuthor \
	&& git checkout -q 4ebc4f221a0987b64740014a9380e9c3522f271d \
	# Lockdown
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Lockdown $MW_HOME/extensions/Lockdown \
	&& cd $MW_HOME/extensions/Lockdown \
	&& git checkout -q ffcb6e8892ad35bb731fad1dc24712a245ab86d0 \
	# LookupUser
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-LookupUser $MW_HOME/extensions/LookupUser \
	&& cd $MW_HOME/extensions/LookupUser \
	&& git checkout -q 5fa17d449b6bedb3e8cee5b239af6cadae31da70 \
	# Loops
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Loops $MW_HOME/extensions/Loops \
	&& cd $MW_HOME/extensions/Loops \
	&& git checkout -q 0eb05a81b9b53f5381eefb4f8b6959b6dcdec1d8 \
	# MagicNoCache
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-MagicNoCache $MW_HOME/extensions/MagicNoCache \
	&& cd $MW_HOME/extensions/MagicNoCache \
	&& git checkout -q 93534c12dac0e821c46c94b21053d274a6e557de \
 	# Maps
	&& git clone --single-branch -b master https://github.com/ProfessionalWiki/Maps $MW_HOME/extensions/Maps \
	&& cd $MW_HOME/extensions/Maps \
	&& git checkout -q 5c87d702b30bb132d89ec03d24b7c19a9805db87 \
	# MassMessage
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-MassMessage $MW_HOME/extensions/MassMessage \
	&& cd $MW_HOME/extensions/MassMessage \
	&& git checkout -q d6a86291bb975c3dc7778f370006f1145cc834bd \
	# MassMessageEmail
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-MassMessageEmail $MW_HOME/extensions/MassMessageEmail \
	&& cd $MW_HOME/extensions/MassMessageEmail \
	&& git checkout -q bd1f3413dbe8242b4294892a7f9803ea22364eae \
	# MediaUploader
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-MediaUploader $MW_HOME/extensions/MediaUploader \
	&& cd $MW_HOME/extensions/MediaUploader \
	&& git checkout -q 1edd91c506c1c0319e7b9a3e71d639130760b1fd \
	# Mermaid (v. 3.1.0)
	&& git clone --single-branch -b master https://github.com/SemanticMediaWiki/Mermaid $MW_HOME/extensions/Mermaid \
	&& cd $MW_HOME/extensions/Mermaid \
	&& git checkout -q fd792683fef3c84a7cdd56f8f474c4da0dd630f2 \
	# MintyDocs (1.0)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-MintyDocs $MW_HOME/extensions/MintyDocs \
	&& cd $MW_HOME/extensions/MintyDocs \
	&& git checkout -q 4496e33ce71d2c364b16599619c961a1a330bf14 \
	# MobileFrontend
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-MobileFrontend $MW_HOME/extensions/MobileFrontend \
	&& cd $MW_HOME/extensions/MobileFrontend \
	&& git checkout -q f0bed5588f76b827038fb9af73fb9677e5804077 \
	# MsUpload
	&& git clone https://github.com/wikimedia/mediawiki-extensions-MsUpload $MW_HOME/extensions/MsUpload \
	&& cd $MW_HOME/extensions/MsUpload \
	&& git checkout -q 8c2403b09186f5f25f0c28369e6aff3c285047df \
	# MyVariables
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-MyVariables $MW_HOME/extensions/MyVariables \
	&& cd $MW_HOME/extensions/MyVariables \
	&& git checkout -q 8b45be10c9b0a484824c55d8cc48399290384260 \
	# NewUserMessage
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-NewUserMessage $MW_HOME/extensions/NewUserMessage \
	&& cd $MW_HOME/extensions/NewUserMessage \
	&& git checkout -q 206f32880fa7bf70b191d33ed80b8626bca39efe \
	# NumerAlpha
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-NumerAlpha $MW_HOME/extensions/NumerAlpha \
	&& cd $MW_HOME/extensions/NumerAlpha \
	&& git checkout -q 93c0869735581006a3f510096738e262d49f4107 \
	# OpenGraphMeta
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-OpenGraphMeta $MW_HOME/extensions/OpenGraphMeta \
	&& cd $MW_HOME/extensions/OpenGraphMeta \
	&& git checkout -q d319702cd4ceda1967c233ef8e021b67b3fc355f \
	# OpenIDConnect
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-OpenIDConnect $MW_HOME/extensions/OpenIDConnect \
	&& cd $MW_HOME/extensions/OpenIDConnect \
	&& git checkout -q 0824f3cf3800f63e930abf0f03baf1a7c755a270 \
	# PageExchange
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-PageExchange $MW_HOME/extensions/PageExchange \
	&& cd $MW_HOME/extensions/PageExchange \
	&& git checkout -q 28482410564e38d2b97ab7321e99c4281c6e5877 \
	# PageForms (v. 5.6.1)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-PageForms $MW_HOME/extensions/PageForms \
	&& cd $MW_HOME/extensions/PageForms \
	&& git checkout -q f90d67ecc2c111e82db454c71592c83384ff9704 \
	# PluggableAuth
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-PluggableAuth $MW_HOME/extensions/PluggableAuth \
	&& cd $MW_HOME/extensions/PluggableAuth \
	&& git checkout -q 4be1e402e1862d165a4feb003c492ddc9525057e \
	# Popups
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Popups $MW_HOME/extensions/Popups \
	&& cd $MW_HOME/extensions/Popups \
	&& git checkout -q ff4d2156e1f7f4c11f7396cb0cd70d387abd8187 \
	# RegularTooltips
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-RegularTooltips $MW_HOME/extensions/RegularTooltips \
	&& cd $MW_HOME/extensions/RegularTooltips \
	&& git checkout -q 1af807bb6d5cfbd1e471e38bf70d6a392fb7eda2 \
	# RevisionSlider
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-RevisionSlider $MW_HOME/extensions/RevisionSlider \
	&& cd $MW_HOME/extensions/RevisionSlider \
	&& git checkout -q 3cae51a322a5ca0f359e83efcb5fac38e73e346e \
	# RottenLinks
	&& git clone --single-branch -b master https://github.com/miraheze/RottenLinks.git $MW_HOME/extensions/RottenLinks \
	&& cd $MW_HOME/extensions/RottenLinks \
	&& git checkout -q a96e99d0a61a42d59587a67db0720ce245a7ee46 \
	# SandboxLink
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-SandboxLink $MW_HOME/extensions/SandboxLink \
	&& cd $MW_HOME/extensions/SandboxLink \
	&& git checkout -q 9ab23288a010c3894c59cd5ba3096d93d57c15c5 \
	# SaveSpinner
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-SaveSpinner $MW_HOME/extensions/SaveSpinner \
	&& cd $MW_HOME/extensions/SaveSpinner \
	&& git checkout -q 1e819e2fff7fad6999bafe71d866c3af50836c42 \
	# SemanticBreadcrumbLinks
	&& git clone --single-branch -b master https://github.com/SemanticMediaWiki/SemanticBreadcrumbLinks $MW_HOME/extensions/SemanticBreadcrumbLinks \
	&& cd $MW_HOME/extensions/SemanticBreadcrumbLinks \
	&& git checkout -q 87a69003743f1de52338f4717cfcf5218ca5a743 \
	# SemanticCompoundQueries (v. 2.2.0)
	&& git clone --single-branch -b master https://github.com/SemanticMediaWiki/SemanticCompoundQueries $MW_HOME/extensions/SemanticCompoundQueries \
	&& cd $MW_HOME/extensions/SemanticCompoundQueries \
	&& git checkout -q eeb514393fdf2e80ae7084839d8803ee32ae3da4 \
	# SemanticDependencyUpdater (v. 2.0.2)
	&& git clone --single-branch -b master https://github.com/gesinn-it/SemanticDependencyUpdater $MW_HOME/extensions/SemanticDependencyUpdater \
	&& cd $MW_HOME/extensions/SemanticDependencyUpdater \
	&& git checkout -q e8a483dd54de6a069854789ae6c702aab98a89ab \
	# SemanticDrilldown
	&& git clone --single-branch -b $MW_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/SemanticDrilldown $MW_HOME/extensions/SemanticDrilldown \
	&& cd $MW_HOME/extensions/SemanticDrilldown \
	&& git checkout -q e960979ec5a3b1e662b3742cee7e7ef4056f9a46 \
	# SemanticExtraSpecialProperties (v. 3.0.4)
	&& git clone --single-branch -b master https://github.com/SemanticMediaWiki/SemanticExtraSpecialProperties $MW_HOME/extensions/SemanticExtraSpecialProperties \
	&& cd $MW_HOME/extensions/SemanticExtraSpecialProperties \
	&& git checkout -q e449633082a4bf7dcae119b6a6d0bfeec8e3cfe8 \
	# SemanticFormsSelect
	&& git clone https://github.com/SemanticMediaWiki/SemanticFormsSelect.git $MW_HOME/extensions/SemanticFormsSelect \
	&& cd $MW_HOME/extensions/SemanticFormsSelect \
	&& git checkout -q 4b56baa752401b4ff9fe555fd57fc5c3309601d4 \
	# SemanticMediaWiki (v. 4.1.2)
	&& git clone https://github.com/SemanticMediaWiki/SemanticMediaWiki $MW_HOME/extensions/SemanticMediaWiki \
	&& cd $MW_HOME/extensions/SemanticMediaWiki \
	&& git checkout -q 5c94879171d5f741b896828c25a9f2bb07a03dff \
	# SemanticResultFormats (v. 4.0.2)
	&& git clone https://github.com/SemanticMediaWiki/SemanticResultFormats $MW_HOME/extensions/SemanticResultFormats \
	&& cd $MW_HOME/extensions/SemanticResultFormats \
	&& git checkout -q d5196722a56f9b65475be68d1e97063d7b975cb9 \
	# SemanticScribunto (v. 2.2.0)
	&& git clone --single-branch -b master https://github.com/SemanticMediaWiki/SemanticScribunto $MW_HOME/extensions/SemanticScribunto \
	&& cd $MW_HOME/extensions/SemanticScribunto \
	&& git checkout -q 1c616a4c4da443b3433000d6870bb92c184236fa \
	# SemanticTasks
	&& git clone https://github.com/WikiTeq/SemanticTasks.git $MW_HOME/extensions/SemanticTasks \
	&& cd $MW_HOME/extensions/SemanticTasks \
	&& git checkout -q 70ddd8cf6090139ce5ee6fdf1e7f3a9f2c68d5d3 \
	# SemanticWatchlist (v. 1.3.0)
	&& git clone https://github.com/SemanticMediaWiki/SemanticWatchlist.git $MW_HOME/extensions/SemanticWatchlist \
	&& cd $MW_HOME/extensions/SemanticWatchlist \
	&& git checkout -q ecea17097874d16cd240ce35bd20692a67c5064b \
	# Sentry (WikiTeq fork that uses sentry/sentry 3.x)
	&& git clone --single-branch -b master https://github.com/WikiTeq/mediawiki-extensions-Sentry.git $MW_HOME/extensions/Sentry \
	&& cd $MW_HOME/extensions/Sentry \
	&& git checkout -q 9d9162d83f921b66f6c14ed354d20607ecafa030 \
	# SimpleBatchUpload (v. 2.0.0)
	&& git clone https://github.com/ProfessionalWiki/SimpleBatchUpload $MW_HOME/extensions/SimpleBatchUpload \
	&& cd $MW_HOME/extensions/SimpleBatchUpload \
	&& git checkout -q 3b9e248b49d7fbeb81d7da32078db7040809e724 \
	# SimpleChanges
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-SimpleChanges $MW_HOME/extensions/SimpleChanges \
	&& cd $MW_HOME/extensions/SimpleChanges \
	&& git checkout -q 5352de89dfaf043f646a44582b26f07822f02be7 \
	# SimpleMathJax
	&& git clone --single-branch https://github.com/jmnote/SimpleMathJax.git $MW_HOME/extensions/SimpleMathJax \
	&& cd $MW_HOME/extensions/SimpleMathJax \
	&& git checkout -q 3757e9b1cf235b2e2c62e7d208d52206e185b28e \
	# SkinPerPage
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-SkinPerPage $MW_HOME/extensions/SkinPerPage \
	&& cd $MW_HOME/extensions/SkinPerPage \
	&& git checkout -q 2793602b37c33aa4c769834feac0b88f385ccef9 \
	# SmiteSpam
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-SmiteSpam $MW_HOME/extensions/SmiteSpam \
	&& cd $MW_HOME/extensions/SmiteSpam \
	&& git checkout -q 268f212b7e366711d8e7b54c7faf5b750fa014ad \
	# SocialProfile
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-SocialProfile $MW_HOME/extensions/SocialProfile \
	&& cd $MW_HOME/extensions/SocialProfile \
	&& git checkout -q 74fcf9bead948ec0419eea10800c9331bcc1273e \
	# SubPageList (v. 3.0.0)
	&& git clone https://github.com/ProfessionalWiki/SubPageList $MW_HOME/extensions/SubPageList \
	&& cd $MW_HOME/extensions/SubPageList \
	&& git checkout -q c016dcdb7866f20319731e6497b48fd43756505e \
	# TemplateStyles
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-TemplateStyles $MW_HOME/extensions/TemplateStyles \
	&& cd $MW_HOME/extensions/TemplateStyles \
	&& git checkout -q 2a93b56e370ab8b8e020ed29c507104b56f1d11a \
	# TemplateWizard
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-TemplateWizard $MW_HOME/extensions/TemplateWizard \
	&& cd $MW_HOME/extensions/TemplateWizard \
	&& git checkout -q d486e3475f84118fd9b5c77d60254daa2f56f654 \
	# Thanks
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Thanks $MW_HOME/extensions/Thanks \
	&& cd $MW_HOME/extensions/Thanks \
	&& git checkout -q 03b6a52f263604c819e69b78c157f6ef5adb053e \
	# TimedMediaHandler
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-TimedMediaHandler $MW_HOME/extensions/TimedMediaHandler \
	&& cd $MW_HOME/extensions/TimedMediaHandler \
	&& git checkout -q 2e64302c68e58693650e91b7869fa5aecf1aaf23 \
	# TinyMCE
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-TinyMCE $MW_HOME/extensions/TinyMCE \
	&& cd $MW_HOME/extensions/TinyMCE \
	&& git checkout -q 06436ec3a53c6cd53c458e4e8ab3ec8d1a23029b \
	# TitleIcon
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-TitleIcon $MW_HOME/extensions/TitleIcon \
	&& cd $MW_HOME/extensions/TitleIcon \
	&& git checkout -q 7c6c83f4859642542393612ad961a258378e0cac \
	# UniversalLanguageSelector
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-UniversalLanguageSelector $MW_HOME/extensions/UniversalLanguageSelector \
	&& cd $MW_HOME/extensions/UniversalLanguageSelector \
	&& git checkout -q 8216e434c38ddeba74e5ad758bfbbcc83861fa60 \
	# UploadWizard
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-UploadWizard $MW_HOME/extensions/UploadWizard \
	&& cd $MW_HOME/extensions/UploadWizard \
	&& git checkout -q 847413694b519c76da7196023651c8d584137d2f \
	# UrlGetParameters
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-UrlGetParameters $MW_HOME/extensions/UrlGetParameters \
	&& cd $MW_HOME/extensions/UrlGetParameters \
	&& git checkout -q d36f92810c762b301035ff1b4f42792ed9a1018b \
	# UserFunctions
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-UserFunctions $MW_HOME/extensions/UserFunctions \
	&& cd $MW_HOME/extensions/UserFunctions \
	&& git checkout -q b532b1047080c3738327ee2f3b541e563e06ca19 \
	# UserMerge
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-UserMerge $MW_HOME/extensions/UserMerge \
	&& cd $MW_HOME/extensions/UserMerge \
	&& git checkout -q 183bb7a8f78cbe365bec0fbd4b3ecdd4fae1a359 \
	# UserPageViewTracker (v. 0.7)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-UserPageViewTracker $MW_HOME/extensions/UserPageViewTracker \
	&& cd $MW_HOME/extensions/UserPageViewTracker \
	&& git checkout -q f4b7c20c372165541164d449c12df1e74e98ed0b \
	# Variables
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Variables $MW_HOME/extensions/Variables \
	&& cd $MW_HOME/extensions/Variables \
	&& git checkout -q b4a9063f16a928567e3b6788cda9246c2e94797f \
	# VEForAll (v. 0.5)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-VEForAll $MW_HOME/extensions/VEForAll \
	&& cd $MW_HOME/extensions/VEForAll \
	&& git checkout -q cffa12abb85200e90b1cbc636325b1ec1a89a6af \
	# VoteNY
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-VoteNY $MW_HOME/extensions/VoteNY \
	&& cd $MW_HOME/extensions/VoteNY \
	&& git checkout -q 11c103f4b9167a8d8d5e850d8a781c6f49b249c1 \
	# WatchAnalytics (v. 4.1.2)
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-WatchAnalytics $MW_HOME/extensions/WatchAnalytics \
	&& cd $MW_HOME/extensions/WatchAnalytics \
	&& git checkout -q 72b70a667a26bbde0a3cf93fc79747aae08fca32 \
	# WhoIsWatching
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-WhoIsWatching $MW_HOME/extensions/WhoIsWatching \
	&& cd $MW_HOME/extensions/WhoIsWatching \
	&& git checkout -q 836a31018e26ab7c993088c4cca31a89efec2ee5 \
	# WhosOnline
	&& git clone --single-branch -b master https://github.com/wikimedia/mediawiki-extensions-WhosOnline $MW_HOME/extensions/WhosOnline \
	&& cd $MW_HOME/extensions/WhosOnline \
	&& git checkout -q d3d63faa08b89c429a7803b283e9bb685a51b9a0 \
	# Widgets
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-Widgets $MW_HOME/extensions/Widgets \
	&& cd $MW_HOME/extensions/Widgets \
	&& git checkout -q 197d429f971b2aebbce29b7a91a194e1f8181e64 \
	# WikiForum
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-WikiForum $MW_HOME/extensions/WikiForum \
	&& cd $MW_HOME/extensions/WikiForum \
	&& git checkout -q a2685b60af86890f199a5f3b6581918369e6a571 \
	# WikiSEO
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-WikiSEO $MW_HOME/extensions/WikiSEO \
	&& cd $MW_HOME/extensions/WikiSEO \
	&& git checkout -q 610cffa3345333b53d4dda7b55b2012fbfcee9de \
	# WSOAuth
	&& git clone --single-branch -b $MW_VERSION https://github.com/wikimedia/mediawiki-extensions-WSOAuth $MW_HOME/extensions/WSOAuth \
	&& cd $MW_HOME/extensions/WSOAuth \
	&& git checkout -q 3c54c4899dd63989bc3214273bf1c5807c7ac5db

# Patch composer
RUN set -x; \
    sed -i 's="monolog/monolog": "2.2.0",="monolog/monolog": "^2.2",=g' $MW_HOME/composer.json

# Patch some SMW-based extensions' composer.json files to avoid Composer-based downloading of SMW.

# SemanticBreadcrumbLinks
COPY _sources/patches/semantic-breadcrumb-links-composer-reqs.patch /tmp/semantic-breadcrumb-links-composer-reqs.patch
RUN set -x; \
	cd $MW_HOME/extensions/SemanticBreadcrumbLinks \
	&& git apply /tmp/semantic-breadcrumb-links-composer-reqs.patch

# SemanticResultFormats
COPY _sources/patches/semantic-result-formats-composer-reqs.patch /tmp/semantic-result-formats-composer-reqs.patch
RUN set -x; \
	cd $MW_HOME/extensions/SemanticResultFormats \
	&& git apply /tmp/semantic-result-formats-composer-reqs.patch

# SemanticWatchlist
COPY _sources/patches/SemanticWatchList.417851c22c25f3e33fb654f4138c760c53051b9a.patch /tmp/SemanticWatchList.417851c22c25f3e33fb654f4138c760c53051b9a.patch
RUN set -x; \
    cd $MW_HOME/extensions/SemanticWatchlist \
    && git apply /tmp/SemanticWatchList.417851c22c25f3e33fb654f4138c760c53051b9a.patch

# Composer dependencies
COPY _sources/configs/composer.canasta.json $MW_HOME/composer.local.json
RUN set -x; \
	cd $MW_HOME \
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

# Other patches

# Add autoloading to several extensions' extension.json file, which normally require
# Composer autoloading
COPY _sources/patches/semantic-compound-queries-autoload.patch /tmp/semantic-compound-queries-autoload.patch
RUN set -x; \
	cd $MW_HOME/extensions/SemanticCompoundQueries \
	&& git apply /tmp/semantic-compound-queries-autoload.patch

COPY _sources/patches/semantic-scribunto-autoload.patch /tmp/semantic-scribunto-autoload.patch
RUN set -x; \
	cd $MW_HOME/extensions/SemanticScribunto \
	&& git apply /tmp/semantic-scribunto-autoload.patch

# Cleanup all .git leftovers
RUN set -x; \
    cd $MW_HOME \
    && find . \( -name ".git" -o -name ".gitignore" -o -name ".gitmodules" -o -name ".gitattributes" \) -exec rm -rf -- {} +

# Generate sample files for installing extensions and skins in LocalSettings.php
RUN set -x; \
	cd $MW_HOME/extensions \
    && for i in $(ls -d */); do echo "#wfLoadExtension('${i%%/}');"; done > $MW_ORIGIN_FILES/installedExtensions.txt \
    # Dirty hack for Semantic MediaWiki
    && sed -i "s/#wfLoadExtension('SemanticMediaWiki');/#enableSemantics('localhost');/g" $MW_ORIGIN_FILES/installedExtensions.txt \
    && cd $MW_HOME/skins \
    && for i in $(ls -d */); do echo "#wfLoadSkin('${i%%/}');"; done > $MW_ORIGIN_FILES/installedSkins.txt \
    # Load Vector skin by default in the sample file
    && sed -i "s/#wfLoadSkin('Vector');/wfLoadSkin('Vector');/" $MW_ORIGIN_FILES/installedSkins.txt

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
	MW_MAP_DOMAIN_TO_DOCKER_GATEWAY=true \
	MW_ENABLE_SITEMAP_GENERATOR=false \
	MW_SITEMAP_PAUSE_DAYS=1 \
	MW_SITEMAP_SUBDIR="" \
	MW_SITEMAP_IDENTIFIER="mediawiki" \
	PHP_UPLOAD_MAX_FILESIZE=10M \
	PHP_POST_MAX_SIZE=10M \
	PHP_MAX_INPUT_VARS=1000 \
	PHP_MAX_EXECUTION_TIME=60 \
	PHP_MAX_INPUT_TIME=60 \
	PM_MAX_CHILDREN=25 \
	PM_START_SERVERS=10 \
	PM_MIN_SPARE_SERVERS=5 \
	PM_MAX_SPARE_SERVERS=15 \
	PM_MAX_REQUESTS=2500 \
	LOG_FILES_COMPRESS_DELAY=3600 \
	LOG_FILES_REMOVE_OLDER_THAN_DAYS=10

COPY _sources/configs/msmtprc /etc/
COPY _sources/configs/mediawiki.conf /etc/apache2/sites-enabled/
COPY _sources/configs/status.conf /etc/apache2/mods-available/
COPY _sources/configs/php_error_reporting.ini _sources/configs/php_upload_max_filesize.ini /etc/php/7.4/cli/conf.d/
COPY _sources/configs/php_error_reporting.ini _sources/configs/php_upload_max_filesize.ini /etc/php/7.4/fpm/conf.d/
COPY _sources/configs/php_max_input_vars.ini _sources/configs/php_max_input_vars.ini /etc/php/7.4/fpm/conf.d/
COPY _sources/configs/php_timeouts.ini /etc/php/7.4/fpm/conf.d/
COPY _sources/configs/php-fpm-www.conf /etc/php/7.4/fpm/pool.d/www.conf
COPY _sources/scripts/*.sh /
COPY _sources/scripts/maintenance-scripts/*.sh /maintenance-scripts/
COPY _sources/scripts/*.php $MW_HOME/maintenance/
COPY _sources/configs/robots.txt $WWW_ROOT/
COPY _sources/configs/.htaccess $WWW_ROOT/
COPY _sources/images/favicon.ico $WWW_ROOT/
COPY _sources/canasta/LocalSettings.php _sources/canasta/CanastaUtils.php _sources/canasta/CanastaDefaultSettings.php $MW_HOME/
COPY _sources/canasta/getMediawikiSettings.php /
COPY _sources/configs/mpm_event.conf /etc/apache2/mods-available/mpm_event.conf

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
	&& a2enmod expires \
	&& a2disconf other-vhosts-access-log \
	# Enable environment variables for FPM workers
	&& sed -i '/clear_env/s/^;//' /etc/php/7.4/fpm/pool.d/www.conf

COPY _sources/images/Powered-by-Canasta.png /var/www/mediawiki/w/resources/assets/

EXPOSE 80
WORKDIR $MW_HOME

HEALTHCHECK --interval=1m --timeout=10s \
	CMD wget -q --method=HEAD localhost/w/api.php

CMD ["/run-apache.sh"]
