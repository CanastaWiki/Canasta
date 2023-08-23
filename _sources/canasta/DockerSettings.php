<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

/**
 * Returns boolean value from environment variable
 * Must return the same result as isTrue function in run-apache.sh file
 * @param $value
 * @return bool
 */
function isEnvTrue( $name ): bool {
	$value = getenv( $name );
	switch ( $value ) {
		case "True":
		case "TRUE":
		case "true":
		case "1":
			return true;
	}
	return false;
}

const DOCKER_SKINS = [
	'CologneBlue',
	'MinervaNeue',
	'Modern',
	'MonoBook', # bundled
	'Refreshed',
	'Timeless', # bundled
	'Vector', # bundled
	'chameleon',
	'pivot',
];

const DOCKER_EXTENSIONS = [
	'SemanticMediaWiki', // keep it at the top to be enabled first, because some Semantic extension don't work in other case.
	'AJAXPoll',
	'AbuseFilter',
	'AdminLinks',
	'AdvancedSearch',
	'AntiSpoof',
	'ApprovedRevs',
	'Arrays',
	'BetaFeatures',
	'Bootstrap',
	'BootstrapComponents',
	'BreadCrumbs2',
	'Buggy',
	'Cargo',
	'CategoryTree', # bundled
	'ChangeAuthor',
	'CharInsert',
	'CheckUser',
	'CirrusSearch',
	'Cite', # bundled
	'CiteThisPage', # bundled
	'Citoid',
	'CodeEditor', # bundled
	'CodeMirror',
	'Collection',
	'CommentStreams',
	'CommonsMetadata',
	'ConfirmAccount',
	'ConfirmEdit', # bundled
	'ConfirmEdit/QuestyCaptcha', # bundled
	'ConfirmEdit/ReCaptchaNoCaptcha', # bundled
	'ContactPage',
	'ContributionScores',
	'CookieWarning',
	'DataTransfer',
	'DebugMode',
	'DeleteBatch',
	'Description2',
	'Disambiguator',
	'DiscussionTools',
	'DismissableSiteNotice',
	'DisplayTitle',
	'Echo',
	'EditAccount',
	'Editcount',
	'Elastica',
	'EmailAuthorization',
	'EmbedVideo',
	'EncryptedUploads',
	'EventLogging',
	'EventStreamConfig',
	'ExternalData',
	'FlexDiagrams',
	'Flow',
	'GTag',
	'Gadgets', # bundled
	'GlobalNotice',
	'GoogleAnalyticsMetrics',
	'GoogleDocCreator',
	'GoogleDocTag',
	'Graph',
	'HTMLTags',
	'HeadScript',
	'HeaderFooter',
	'HeaderTabs',
	'IframePage',
	'ImageMap', # bundled
	'InputBox', # bundled
	'Interwiki', # bundled
	'JWTAuth',
	'LDAPAuthentication2',
	'LDAPAuthorization',
	'LDAPProvider',
	'LabeledSectionTransclusion',
	'Lazyload',
	'Lingo',
	'LinkSuggest',
	'LinkTarget',
	'Linter',
	'LiquidThreads',
	'LockAuthor',
	'Lockdown',
	'LookupUser',
	'Loops',
	'MagicNoCache',
	'Maps',
	'MassMessage',
	'MassMessageEmail',
	'MassPasswordReset',
	'Math',
	'MediaUploader',
	'Mermaid',
	'MintyDocs',
	'MobileDetect',
	'MobileFrontend',
	'Mpdf',
	'MsUpload',
	'MultimediaViewer', # bundled
	'MyVariables',
	'NCBITaxonomyLookup',
	'NewUserMessage',
	'Nuke', # bundled
	'NumerAlpha',
	'OATHAuth', # bundled
	'OpenGraphMeta',
	'OpenIDConnect',
	'PDFEmbed',
	'PageExchange',
//	'PageForms',   must be enabled manually after enableSemantics()
	'PageImages', # bundled
	'PageSchemas',
	'ParserFunctions', # bundled
	'PdfHandler', # bundled
	'PluggableAuth',
	'Poem', # bundled
	'Popups',
	'PubmedParser',
	'RegularTooltips',
	'RemoteWiki',
	'Renameuser', # bundled
	'ReplaceText', # bundled
	'RevisionSlider',
	'RottenLinks',
	'SandboxLink',
	'SaveSpinner',
	'Scopus',
	'Scribunto', # bundled
	'SecureLinkFixer', # bundled
	'SelectCategory',
	'SemanticCompoundQueries',
	'SemanticDependencyUpdater', //  must be enabled after SemanticMediaWiki
	'SemanticDrilldown',
	'SemanticExtraSpecialProperties',
//	'SemanticMediaWiki', moved the top to be enabled first, because some Semantic extension don't work in other case.
	'SemanticQueryInterface',
	'SemanticResultFormats',
	'SemanticScribunto',
	'Sentry',
	'ShowMe',
	'SimpleBatchUpload',
	'SimpleChanges',
	'SimpleMathJax',
	'SimpleTooltip',
	'SkinPerNamespace',
	'SkinPerPage',
	'Skinny',
	'SmiteSpam',
	'SoundManager2Button',
	'SpamBlacklist', # bundled
	'SubPageList',
	'Survey',
	'SyntaxHighlight_GeSHi', # bundled
	'Tabber',
	'TabberNeue',
	'Tabs',
	'TemplateData', # bundled
	'TemplateStyles',
	'TemplateWizard',
	'TextExtracts', # bundled
	'Thanks',
	'TinyMCE',
	'TitleBlacklist', # bundled
	'TitleIcon',
	'TwitterTag',
	'UniversalLanguageSelector',
	'UploadWizard',
	'UploadWizardExtraButtons',
	'UrlGetParameters',
	'UserFunctions',
	'UserMerge',
	'UserPageViewTracker',
	'VEForAll',
	'Validator',
	'Variables',
	'VariablesLua',
	'VisualEditor', # bundled
	'VoteNY',
	'WatchAnalytics',
	'WSOAuth',
	'WhoIsWatching',
	'WhosOnline',
	'Widgets',
	'WikiEditor', # bundled
	'WikiForum',
	'WikiSEO',
	'YouTube',
];

$DOCKER_MW_VOLUME = getenv( 'MW_VOLUME' );

########################### Core Settings ##########################

# The name of the site. This is the name of the site as displayed throughout the site.
$wgSitename  = getenv( 'MW_SITE_NAME' );

$wgMetaNamespace = "Project";

## The URL base path to the directory containing the wiki;
## defaults for all runtime URL paths are based off of this.
## For more information on customizing the URLs
## (like /w/index.php/Page_title to /wiki/Page_title) please see:
## https://www.mediawiki.org/wiki/Manual:Short_URL
$wgScriptPath = "/w";
$wgScriptExtension = ".php";

## The protocol and server name to use in fully-qualified URLs
if ( getenv( 'MW_SITE_SERVER' ) ) {
	$wgServer = getenv( 'MW_SITE_SERVER' );
}

## The URL path to static resources (images, scripts, etc.)
$wgResourceBasePath = $wgScriptPath;

## UPO means: this is also a user preference option

$wgEnableEmail = isEnvTrue( 'MW_ENABLE_EMAIL' );
$wgEnableUserEmail = isEnvTrue( 'MW_ENABLE_USER_EMAIL' );

$wgEmergencyContact = getenv( 'MW_EMERGENCY_CONTACT' );
$wgPasswordSender = getenv( 'MW_PASSWORD_SENDER' );

$wgEnotifUserTalk = false; # UPO
$wgEnotifWatchlist = false; # UPO
$wgEmailAuthentication = true;

## Database settings
$wgSQLiteDataDir = "$DOCKER_MW_VOLUME/sqlite";
$wgDBtype = getenv( 'MW_DB_TYPE' );
$wgDBserver = getenv( 'MW_DB_SERVER' );
$wgDBname = getenv( 'MW_DB_NAME' );
$wgDBuser = getenv( 'MW_DB_USER' );
$wgDBpassword = getenv( 'MW_DB_PASS' );

# MySQL specific settings
$wgDBprefix = "";

# MySQL table options to use during installation or update
$wgDBTableOptions = "ENGINE=InnoDB, DEFAULT CHARSET=binary";

# Periodically send a pingback to https://www.mediawiki.org/ with basic data
# about this MediaWiki instance. The Wikimedia Foundation shares this data
# with MediaWiki developers to help guide future development efforts.
$wgPingback = false;

## If you use ImageMagick (or any other shell command) on a
## Linux server, this will need to be set to the name of an
## available UTF-8 locale
$wgShellLocale = "en_US.utf8";

## Set $wgCacheDirectory to a writable directory on the web server
## to make your wiki go slightly faster. The directory should not
## be publicly accessible from the web.
$wgCacheDirectory = isEnvTrue( 'MW_USE_CACHE_DIRECTORY' ) ? "$DOCKER_MW_VOLUME/l10n_cache" : false;

# Do not overwrite $wgSecretKey with empty string if MW_SECRET_KEY is not defined
$wgSecretKey = getenv( 'MW_SECRET_KEY' ) ?: $wgSecretKey;

# Changing this will log out all existing sessions.
$wgAuthenticationTokenVersion = "1";

## For attaching licensing metadata to pages, and displaying an
## appropriate copyright notice / icon. GNU Free Documentation
## License and Creative Commons licenses are supported so far.
$wgRightsPage = ""; # Set to the title of a wiki page that describes your license/copyright
$wgRightsUrl = "";
$wgRightsText = "";
$wgRightsIcon = "";

# Path to the GNU diff3 utility. Used for conflict resolution.
$wgDiff3 = "/usr/bin/diff3";

# see https://www.mediawiki.org/wiki/Manual:$wgCdnServersNoPurge
# Add docker networks as CDNs
$wgCdnServersNoPurge = [ '172.16.0.0/12', '192.168.0.0/16', '10.0.0.0/8' ];

if ( isEnvTrue( 'MW_SHOW_EXCEPTION_DETAILS' ) ) {
	$wgShowExceptionDetails = true;
}

# Site language code, should be one of the list in ./languages/Names.php
$wgLanguageCode = getenv( 'MW_SITE_LANG' ) ?: 'en';

# Allow images and other files to be uploaded through the wiki.
$wgEnableUploads  = isEnvTrue( 'MW_ENABLE_UPLOADS' );
$wgUseImageMagick = isEnvTrue( 'MW_USE_IMAGE_MAGIC' );

####################### Skin Settings #######################
# Default skin: you can change the default skin. Use the internal symbolic
# names, ie 'standard', 'nostalgia', 'cologneblue', 'monobook', 'vector':
$wgDefaultSkin = getenv( 'MW_DEFAULT_SKIN' );
$dockerLoadSkins = null;
$dockerLoadSkins = getenv( 'MW_LOAD_SKINS' );
if ( $dockerLoadSkins ) {
	$dockerLoadSkins = explode( ',', $dockerLoadSkins );
	$dockerLoadSkins = array_intersect( DOCKER_SKINS, $dockerLoadSkins );
	if ( $dockerLoadSkins ) {
		wfLoadSkins( $dockerLoadSkins );
	}
}
if ( !$dockerLoadSkins ) {
	wfLoadSkin( 'Vector' );
	$wgDefaultSkin = 'Vector';
} else{
	if ( !$wgDefaultSkin ) {
		$wgDefaultSkin = reset( $dockerLoadSkins );
	}
	$dockerLoadSkins = array_combine( $dockerLoadSkins, $dockerLoadSkins );
}

if ( isset( $dockerLoadSkins['chameleon'] ) ) {
	wfLoadExtension( 'Bootstrap' );
}

####################### Extension Settings #######################
// The variable will be an array [ 'extensionName' => 'extensionName, ... ]
// made by see array_combine( $dockerLoadExtensions, $dockerLoadExtensions ) below
$dockerLoadExtensions = getenv( 'MW_LOAD_EXTENSIONS' );
if ( $dockerLoadExtensions ) {
	$dockerLoadExtensions = explode( ',', $dockerLoadExtensions );
	$dockerLoadExtensions = array_intersect( DOCKER_EXTENSIONS, $dockerLoadExtensions );
	if ( $dockerLoadExtensions ) {
		$dockerLoadExtensions = array_combine( $dockerLoadExtensions, $dockerLoadExtensions );
		// Enable SemanticMediaWiki first, because some Semantic extension don't work in other case
		if ( isset( $dockerLoadExtensions['SemanticMediaWiki'] ) ) {
			wfLoadExtension( 'SemanticMediaWiki' );
		}
		foreach ( $dockerLoadExtensions as $extension ) {
			if ( $extension === 'SemanticMediaWiki' ) {
				// Already loaded above ^
				continue;
			}
			if ( file_exists( "$wgExtensionDirectory/$extension/extension.json" ) ) {
				wfLoadExtension( $extension );
			} else {
				require_once "$wgExtensionDirectory/$extension/$extension.php";
			}
		}
	}
}

# SyntaxHighlight_GeSHi
$wgPygmentizePath = '/usr/bin/pygmentize';

# SemanticMediaWiki
$smwgConfigFileDir = "$DOCKER_MW_VOLUME/extensions/SemanticMediaWiki/config";

// Scribunto https://www.mediawiki.org/wiki/Extension:Scribunto
$wgScribuntoDefaultEngine = 'luasandbox';
$wgScribuntoEngineConf['luasandbox']['cpuLimit'] = '120';
$wgScribuntoUseGeSHi = boolval( $dockerLoadExtensions['SyntaxHighlight_GeSHi'] ?? false );
$wgScribuntoUseCodeEditor = boolval( $dockerLoadExtensions['CodeEditor'] ?? false );

# Interwiki
$wgGroupPermissions['sysop']['interwiki'] = true;

# InstantCommons allows wiki to use images from http://commons.wikimedia.org
$wgUseInstantCommons  = isEnvTrue( 'MW_USE_INSTANT_COMMONS' );

# Name used for the project namespace. The name of the meta namespace (also known as the project namespace), used for pages regarding the wiki itself.
#$wgMetaNamespace = 'Project';
#$wgMetaNamespaceTalk = 'Project_talk';

# The relative URL path to the logo.  Make sure you change this from the default,
# or else you'll overwrite your logo when you upgrade!
$wgLogo = "$wgScriptPath/logo.png";

##### Short URLs
## https://www.mediawiki.org/wiki/Manual:Short_URL
$wgArticlePath = '/wiki/$1';
## Also see mediawiki.conf

##### Jobs
# Number of jobs to perform per request. see https://www.mediawiki.org/wiki/Manual:$wgJobRunRate
$wgJobRunRate = 0;

# SVG Converters
$wgSVGConverter = 'rsvg';

##### Improve performance
# https://www.mediawiki.org/wiki/Manual:$wgMainCacheType
switch ( getenv( 'MW_MAIN_CACHE_TYPE' ) ) {
	case 'CACHE_ACCEL':
		# APC has several problems in latest versions of WediaWiki and extensions, for example:
		# https://www.mediawiki.org/wiki/Extension:Flow#.22Exception_Caught:_CAS_is_not_implemented_in_Xyz.22
		$wgMainCacheType = CACHE_ACCEL;
		$wgSessionCacheType = CACHE_DB; #This may cause problems when CACHE_ACCEL is used
		break;
	case 'CACHE_DB':
		$wgMainCacheType = CACHE_DB;
		break;
	case 'CACHE_ANYTHING':
		$wgMainCacheType = CACHE_ANYTHING;
		break;
	case 'CACHE_MEMCACHED':
		# Use Memcached, see https://www.mediawiki.org/wiki/Memcached
		$wgMainCacheType = CACHE_MEMCACHED;
		$wgParserCacheType = CACHE_MEMCACHED; # optional
		$wgMessageCacheType = CACHE_MEMCACHED; # optional
		$wgMemCachedServers = explode( ',', getenv( 'MW_MEMCACHED_SERVERS' ) );
		$wgSessionsInObjectCache = true; # optional
		$wgSessionCacheType = CACHE_MEMCACHED; # optional
		break;
	case 'CACHE_REDIS':
		$wgObjectCaches['redis'] = [
			'class' => 'RedisBagOStuff',
			'servers' => ['redis:6379']
		];
		$wgMainCacheType = 'redis';
		$wgSessionCacheType = CACHE_DB;
		break;
	default:
		$wgMainCacheType = CACHE_NONE;
}

# Use Varnish accelerator
$tmpProxy = getenv( 'MW_PROXY_SERVERS' );
if ( $tmpProxy ) {
	# https://www.mediawiki.org/wiki/Manual:Varnish_caching
	$wgUseCdn = true;
	$wgCdnServers = explode( ',', $tmpProxy );
	$wgUsePrivateIPs = true;
	# Use HTTP protocol for internal connections like PURGE request to Varnish
	if ( strncasecmp( $wgServer, 'https://', 8 ) === 0 ) {
		$wgInternalServer = 'http://' . substr( $wgServer, 8 ); // Replaces HTTPS with HTTP
	}
	// Re-warm up varnish cache after a purge.
	// Do this on LinksUpdate and not HTMLCacheUpdate because HTMLCacheUpdate
	// does 100 pages at a time very quickly which can overwhelm things.
	// WLDR-314.
	$wgHooks['LinksUpdateComplete'][] = function ( $linksUpdate ) {
		global $wgCdnServers;
		$url = $linksUpdate->getTitle()->getInternalURL();
		// Adapted from CdnCacheUpdate::naivePurge.
		foreach( $wgCdnServers as $server ) {
			$urlInfo = wfParseUrl( $url );
			$urlHost = strlen( $urlInfo['port'] ?? '' )
				? \Wikimedia\IPUtils::combineHostAndPort( $urlInfo['host'], (int)$urlInfo['port'] )
				: $urlInfo['host'];
			$baseReq = [
				'method' => 'GET',
				'url' => $url,
				'headers' => [
					'Host' => $urlHost,
					'Connection' => 'Keep-Alive',
					'Proxy-Connection' => 'Keep-Alive',
					'User-Agent' => 'MediaWiki/' . MW_VERSION . ' LinksUpdate',
				],
				'proxy' => $server
			];
			MediaWiki\MediaWikiServices::getInstance()->getHttpRequestFactory()
				->createMultiClient()->runMulti( [ $baseReq ] );
		}
	};
}

# Debug mode
$MW_DEBUG_MODE = getenv( 'MW_DEBUG_MODE' );
if ( $MW_DEBUG_MODE === 'true' ) {
	$wgDebugMode = true;
} elseif ( is_numeric( $MW_DEBUG_MODE ) ) {
	$wgDebugMode = intval( $MW_DEBUG_MODE );
} else {
	$wgDebugMode = false;
}
if ( $wgDebugMode ) {
	if ( isset( $wgDebugModeForIP ) && $_SERVER['REMOTE_ADDR'] == $wgDebugModeForIP ) {
		wfLoadExtension( 'DebugMode' );
	}
}

# AdvancedSearch
# Deep category searching requires SPARQL (like wikidata), should be disabled by default for non Wikimedia wikis
$wgAdvancedSearchDeepcatEnabled = false;

######################### Custom Settings ##########################
$canastaLocalSettingsFilePath = getenv( 'MW_CONFIG_DIR' ) . '/LocalSettings.php';
$emulateLocalSettingsDoesNotExists = false;
if ( is_readable( "$IP/_settings/LocalSettings.php" ) ) {
	require_once "$IP/_settings/LocalSettings.php";
} elseif ( is_readable( "$IP/CustomSettings.php" ) ) {
	require_once "$IP/CustomSettings.php";
} elseif ( is_readable( $canastaLocalSettingsFilePath ) ) {
	require_once $canastaLocalSettingsFilePath;
} elseif ( getenv( 'MW_DB_TYPE' ) !== 'sqlite' && !getenv( 'MW_DB_SERVER' ) ) {
	// There are no LocalSettings.php files
	// and the database server is not defined (and it is not a sqlite database)
	$emulateLocalSettingsDoesNotExists = true;
}

if ( defined( 'MW_CONFIG_CALLBACK' ) ) {
	// Called from WebInstaller or similar entry point

	if ( $emulateLocalSettingsDoesNotExists	) {
		// Remove all variables, WebInstaller should decide that "$IP/LocalSettings.php" does not exist.
		$vars = array_keys( get_defined_vars() );
		foreach ( $vars as $v => $k ) {
			unset( $$k );
		}
		unset( $vars, $v, $k );
		return;
	}
}

if ( $emulateLocalSettingsDoesNotExists ) {
	// Emulate that "$IP/LocalSettings.php" does not exist

	// Set CANASTA_CONFIG_FILE for NoLocalSettings template work correctly in includes/CanastaNoLocalSettings.php
	define( "CANASTA_CONFIG_FILE", $canastaLocalSettingsFilePath );

	// Do the same what function wfWebStartNoLocalSettings() does
	require_once "$IP/includes/CanastaNoLocalSettings.php";
	die();
}

# Include all php files in config/settings directory
foreach ( glob( getenv( 'MW_CONFIG_DIR' ) . '/settings/*.php' ) as $filename ) {
	if ( is_readable( $filename ) ) {
		require_once $filename;
	} else {
		MWDebug::warning( 'Cannot read file: $filename' );
	}
}

# Flow https://www.mediawiki.org/wiki/Extension:Flow
if ( isset( $dockerLoadExtensions['Flow'] ) ) {
	$flowNamespaces = getenv( 'MW_FLOW_NAMESPACES' );
	if ( $flowNamespaces ) {
		$wgFlowContentFormat = 'html';
		foreach ( explode( ',', $flowNamespaces ) as $ns ) {
			$wgNamespaceContentModels[ constant( $ns ) ] = 'flow-board';
		}
	}
}

########################### Search Type ############################
switch( getenv( 'MW_SEARCH_TYPE' ) ) {
	case 'CirrusSearch':
		# https://www.mediawiki.org/wiki/Extension:CirrusSearch
		wfLoadExtension( 'Elastica' );
		wfLoadExtension( 'CirrusSearch' );
		$wgCirrusSearchServers =  explode( ',', getenv( 'MW_CIRRUS_SEARCH_SERVERS' ) );
		if ( isset( $flowNamespaces ) ) {
			$wgFlowSearchServers = $wgCirrusSearchServers;
		}
		$wgSearchType = 'CirrusSearch';
		break;
}

########################### Sitemap ############################
if ( isEnvTrue('MW_ENABLE_SITEMAP_GENERATOR') ) {
	$wgHooks['BeforePageDisplay'][] = function ( $out, $skin ) {
		global $wgScriptPath;
		$out->addLink( [
			'rel' => 'sitemap',
			'type' => 'application/xml',
			'title' => 'Sitemap',
			'href' => $wgScriptPath . '/sitemap/sitemap-index-mediawiki.xml'
		] );
	};
}

# Sentry
$wgSentryDsn = getenv('MW_SENTRY_DSN');
if ( $wgSentryDsn ) {
	wfLoadExtension( 'Sentry' );
}

# Fixes CVE-2021-44858, CVE-2021-45038, CVE-2021-44857, https://www.mediawiki.org/wiki/2021-12_security_release/FAQ
$wgActions['mcrundo'] = false;
$wgActions['mcrrestore'] = false;
$wgWhitelistRead = [];
$wgWhitelistReadRegexp = [];

if ( isset( $_REQUEST['forceprofile'] ) ) {
	$wgProfiler['class'] = 'ProfilerXhprof';
	$wgProfiler['output'] = [ 'ProfilerOutputText' ];
	$wgProfiler['visible'] = false;
	$wgUseCdn = false; // make sure profile is not cached
}
