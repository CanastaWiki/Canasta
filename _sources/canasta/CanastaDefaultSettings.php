<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

$canastaLocalSettingsFilePath = getenv( 'MW_VOLUME' ) . '/config/LocalSettings.php';
$canastaCommonSettingsFilePath = getenv( 'MW_VOLUME' ) . '/config/CommonSettings.php';

// Check if installation is configured:
// - New installations: MW_SECRET_KEY is set in environment
// - Existing installations: config/LocalSettings.php or config/CommonSettings.php exists
$hasSecretKeyEnv = getenv( 'MW_SECRET_KEY' ) !== false && getenv( 'MW_SECRET_KEY' ) !== '';
$hasLocalSettings = file_exists( $canastaLocalSettingsFilePath );
$hasCommonSettings = file_exists( $canastaCommonSettingsFilePath );
$isConfigured = $hasSecretKeyEnv || $hasLocalSettings || $hasCommonSettings;

if ( defined( 'MW_CONFIG_CALLBACK' ) ) {
	// Called from WebInstaller or similar entry point

	if ( !$isConfigured ) {
		// Remove all variables, WebInstaller should decide that "$IP/LocalSettings.php" does not exist.
		$vars = array_keys( get_defined_vars() );
		foreach ( $vars as $v => $k ) {
			unset( $$k );
		}
		unset( $vars, $v, $k );
		return;
	}
}
// WebStart entry point

// Check that installation is configured
if ( !$isConfigured ) {
	// Emulate that "$IP/LocalSettings.php" does not exist

	// Set CANASTA_CONFIG_FILE for NoLocalSettings template work correctly in includes/CanastaNoLocalSettings.php
	define( "CANASTA_CONFIG_FILE", $canastaLocalSettingsFilePath );

	// Do the same what function wfWebStartNoLocalSettings() does
	require_once "$IP/includes/CanastaNoLocalSettings.php";
	die();
}

// Canasta default settings below

$wgServer = getenv( 'MW_SITE_SERVER' ) ?: 'http://localhost';

## The URL base path to the directory containing the wiki;
## defaults for all runtime URL paths are based off of this.
## For more information on customizing the URLs
## (like /w/index.php/Page_title to /wiki/Page_title) please see:
## https://www.mediawiki.org/wiki/Manual:Short_URL
$wgScriptPath = "/w";
$wgScriptExtension = ".php";
$wgArticlePath = '/wiki/$1';
$wgStylePath = $wgScriptPath . '/skins';

## The URL path to static resources (images, scripts, etc.)
$wgResourceBasePath = $wgScriptPath;

# SyntaxHighlight_GeSHi
$wgPygmentizePath = '/usr/bin/pygmentize';

# SVG Converters
$wgSVGConverter = 'rsvg';

# Binary paths
$wgDiff3 = "/usr/bin/diff3";
$wgImageMagickConvertCommand = "/usr/bin/convert";
$wgUseImageMagick = true;

# File uploads enabled by default (Canasta is configured for uploads)
$wgEnableUploads = true;

# Disable pingback
$wgPingback = false;

# Use local files instead of Wikimedia Commons
$wgUseInstantCommons = false;

# Database connection (from environment, can be overridden by config/LocalSettings.php)
# $wgDBport is intentionally not set — MediaWiki's MySQL driver ignores
# it (only the PostgreSQL driver honors $wgDBport). Non-standard ports
# are communicated via host:port on $wgDBserver.
$wgDBtype = "mysql";
$wgDBserver = getenv( 'MYSQL_HOST' ) ?: 'db';
$_dbPort = getenv( 'MYSQL_PORT' ) ?: '3306';
if ( $_dbPort !== '3306' ) {
	$wgDBserver .= ':' . $_dbPort;
}
$wgDBuser = getenv( 'MYSQL_USER' ) ?: 'root';
$wgDBpassword = getenv( 'MYSQL_PASSWORD' ) ?: 'mediawiki';

# Secret key (from environment, can be overridden by config/LocalSettings.php)
$secretKey = getenv( 'MW_SECRET_KEY' );
if ( $secretKey ) {
	$wgSecretKey = $secretKey;
}
$wgAuthenticationTokenVersion = "1";

# MySQL defaults
$wgDBprefix = "";
$wgDBssl = filter_var( getenv( 'MYSQL_SSL' ), FILTER_VALIDATE_BOOLEAN );
$wgDBTableOptions = "ENGINE=InnoDB, DEFAULT CHARSET=binary";

# Semantic MediaWiki: store smw.json on the persistent volume
$smwgConfigFileDir = getenv( 'MW_VOLUME' ) . '/config/persistent';

# Main cache: APCu, or Redis when the instance runs one. APCu is private to
# each PHP process, so maintenance scripts cannot purge the web server's copy;
# a Redis the web server and scripts share can be purged.
if ( isEnvTrue( 'CANASTA_ENABLE_REDIS' ) ) {
	$wgObjectCaches['redis'] = [
		'class' => \Wikimedia\ObjectCache\RedisBagOStuff::class,
		'servers' => [ 'redis:6379' ],
	];
	$wgMainCacheType = 'redis';
} else {
	$wgMainCacheType = CACHE_ACCEL;
}
$wgMemCachedServers = [];

# Sessions in the database survive web container restarts, and are shared
# between web replicas. They get their own table because update.php empties
# objectcache, which would log every user out. The table is created at
# container start (run-maintenance-scripts.sh) and by update.php.
$wgObjectCaches['canasta-sessions'] = [
	'class' => SqlBagOStuff::class,
	'loggroup' => 'SQLBagOStuff',
	'tableName' => 'canasta_sessions',
];
$wgSessionCacheType = 'canasta-sessions';
$wgHooks['LoadExtensionSchemaUpdates'][] = static function ( $updater ) {
	if ( $updater->getDB()->getType() === 'mysql' ) {
		$updater->addExtensionTable( 'canasta_sessions', __DIR__ . '/canasta_sessions.sql' );
	}
};

# Varnish cache configuration (enabled by default for backward compatibility;
# set CANASTA_ENABLE_VARNISH=false to disable)
$canastaEnableVarnish = strtolower( (string)getenv( 'CANASTA_ENABLE_VARNISH' ) );
if ( $canastaEnableVarnish !== 'false' && $canastaEnableVarnish !== '0' ) {
	# Exclude all private IP ranges from CDN purge restrictions
	# see https://www.mediawiki.org/wiki/Manual:$wgCdnServersNoPurge
	$wgUseCdn = true;
	$wgCdnServersNoPurge = [];
	$wgCdnServersNoPurge[] = '10.0.0.0/8';     // 10.0.0.0 – 10.255.255.255
	$wgCdnServersNoPurge[] = '172.16.0.0/12';  // 172.16.0.0 – 172.31.255.255
	$wgCdnServersNoPurge[] = '192.168.0.0/16'; // 192.168.0.0 – 192.168.255.255

	# Configure Varnish cache purging
	$wgCdnServers = [ 'varnish:80' ];
	$wgInternalServer = preg_replace( '/^https:/', 'http:', $wgServer );
}

/**
 * Returns boolean value from environment variable
 * Must return the same result as the isTrue function in functions.sh
 * @param $name
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

/**
 * Load extensions and skins from YAML files in the given settings directory.
 * Uses MediaWiki's SettingsBuilder to process each file, which handles extension
 * and skin registration via the same mechanism as MediaWiki's own YAML settings
 * files (see Manual:YAML_settings_file_format).
 *
 * Files are loaded in lexicographic order. The Canasta CLI manages a file called
 * settings.yaml; users may add their own YAML files alongside it.
 *
 * This runs during the SettingsBuilder "loading" stage (within LocalSettings.php
 * processing), so loadFile() is available. Extensions and skins are queued and
 * registered later when Setup.php transitions to the registration stage.
 *
 * @param string $configDir Directory containing YAML settings files
 */
function canastaLoadConfigYaml( $configDir ) {
	global $wgSettings;
	if ( $wgSettings === null ) {
		// Reached outside a normal request bootstrap (e.g. PHPUnit's
		// extension-discovery runner sources LocalSettings.php without
		// initialising Setup.php, so $wgSettings is never created).
		return;
	}
	$yamlFiles = glob( $configDir . '/*.yaml' );
	if ( $yamlFiles === false || !is_array( $yamlFiles ) ) {
		return;
	}
	sort( $yamlFiles );
	foreach ( $yamlFiles as $yamlFile ) {
		$wgSettings->loadFile( $yamlFile );
	}
}

$DOCKER_MW_VOLUME = getenv( 'MW_VOLUME' );

## Set $wgCacheDirectory to a writable directory on the web server
## to make your wiki go slightly faster. The directory should not
## be publicly accessible from the web.
$wgCacheDirectory = isEnvTrue( 'MW_USE_CACHE_DIRECTORY' ) ? "$DOCKER_MW_VOLUME/l10n_cache" : false;

# Default logging: capture exceptions, errors, fatal errors, and every shell
# command MediaWiki runs (exec). These are production-safe and low-volume.
# Users can override or extend these in their settings files.
# For full debug logging (verbose, not for production), set $wgDebugLogFile.
$wgDebugLogGroups = [
	'exception' => getenv( 'MW_LOG' ) . '/exception.log',
	'error' => getenv( 'MW_LOG' ) . '/error.log',
	'fatal' => getenv( 'MW_LOG' ) . '/fatal.log',
	'exec' => getenv( 'MW_LOG' ) . '/exec.log',
];

# Include user defined CommonSettings.php file
if ( file_exists( $canastaCommonSettingsFilePath ) ) {
	require_once "$canastaCommonSettingsFilePath";
}

# Include user defined LocalSettings.php file
if ( file_exists( $canastaLocalSettingsFilePath ) ) {
	require_once "$canastaLocalSettingsFilePath";
}

# Load global settings files
# Check new path first (settings/global/), fall back to legacy path (settings/)
$globalSettingsDir = getenv( 'MW_VOLUME' ) . '/config/settings/global';
if ( !is_dir( $globalSettingsDir ) ) {
	$globalSettingsDir = getenv( 'MW_VOLUME' ) . '/config/settings';
}

// Load extensions/skins from YAML files (e.g. settings.yaml) before
// user PHP files so that user settings can configure loaded extensions.
canastaLoadConfigYaml( $globalSettingsDir );

$filenames = glob( $globalSettingsDir . '/*.php' );

if ( $filenames !== false && is_array( $filenames ) ) {
	sort( $filenames );

	foreach ( $filenames as $filename ) {
		require_once "$filename";
	}
}

# Include the FarmConfig
if ( file_exists( getenv( 'MW_VOLUME' ) . '/config/wikis.yaml' ) ) {
	require_once "$IP/FarmConfigLoader.php";
}

# Show distribution version on Special:Version
$canastaVersionFile = '/tmp/canasta-version';
if ( file_exists( $canastaVersionFile ) ) {
	$lines = file( $canastaVersionFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES );
	if ( count( $lines ) >= 2 ) {
		$distributionLabel = $lines[0];
		$distributionVersion = $lines[1];
		$wgHooks['SoftwareInfo'][] = function ( &$software ) use ( $distributionLabel, $distributionVersion ) {
			$software[$distributionLabel] = $distributionVersion;
		};
	}
}

/**
 * Show a warning to users that mailing requires $wgSMTP.
 */
$wgHooks['SiteNoticeAfter'][] = function ( &$siteNotice, Skin $skin ) {
	global $wgSMTP, $wgEnableEmail, $wgEnableUserEmail;

	if ( !$wgEnableEmail || $wgSMTP ) {
		return;
	}
	$title = $skin->getTitle();
	if ( !$title->isSpecialPage() ) {
		return;
	}
	$specialPage = MediaWiki\MediaWikiServices::getInstance()
		->getSpecialPageFactory()
		->getPage( $title->getText() );
	if ( $specialPage == null ) {
		return;
	}
	$canonicalName = $specialPage->getName();
	// Only display this warning for pages that could result in an email getting sent.
	$specialPagesWithEmail = [ 'Preferences', 'CreateAccount' ];
	if ( $wgEnableUserEmail ) {
		$specialPagesWithEmail[] = 'Emailuser';
	}
	if ( !in_array( $canonicalName, $specialPagesWithEmail ) ) {
		return;
	}

	$warningText = 'Please note that mailing does not currently work on this wiki, because Canasta requires <a href="https://www.mediawiki.org/wiki/Manual:$wgSMTP">$wgSMTP</a> to be set in order to send emails.';
	$siteNotice .= Html::warningBox( '<span style="font-size: larger;">' . $warningText . '</span>' );
};
