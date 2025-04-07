<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

require_once "{$IP}/CanastaUtils.php";

$canastaLocalSettingsFilePath = getenv( 'MW_VOLUME' ) . '/config/LocalSettings.php';
$canastaCommonSettingsFilePath = getenv( 'MW_VOLUME' ) . '/config/CommonSettings.php';

if ( defined( 'MW_CONFIG_CALLBACK' ) ) {
	// Called from WebInstaller or similar entry point

	if ( !file_exists( $canastaLocalSettingsFilePath ) && !file_exists( $canastaCommonSettingsFilePath ) ) {
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

// Check that user's LocalSettings.php exists
if ( !is_readable( $canastaLocalSettingsFilePath ) && !is_readable( $canastaCommonSettingsFilePath ) ) {
	// Emulate that "$IP/LocalSettings.php" does not exist

	// Set CANASTA_CONFIG_FILE for NoLocalSettings template work correctly in includes/CanastaNoLocalSettings.php
	define( "CANASTA_CONFIG_FILE", $canastaLocalSettingsFilePath );

	// Do the same what function wfWebStartNoLocalSettings() does
	require_once "$IP/includes/CanastaNoLocalSettings.php";
	die();
}

// Canasta default settings below

$wgServer = getenv( 'MW_SITE_SERVER' ) ?? 'http://localhost';

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

# We use job runner instead
$wgJobRunRate = 0;

# SVG Converters
$wgSVGConverter = 'rsvg';

# Docker specific setup
# Exclude all private IP ranges
# see https://www.mediawiki.org/wiki/Manual:$wgCdnServersNoPurge
$wgUseCdn = true;
$wgCdnServersNoPurge = [];
$wgCdnServersNoPurge[] = '10.0.0.0/8';     // 10.0.0.0 – 10.255.255.255
$wgCdnServersNoPurge[] = '172.16.0.0/12';  // 172.16.0.0 – 172.31.255.255
$wgCdnServersNoPurge[] = '192.168.0.0/16'; // 192.168.0.0 – 192.168.255.255

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

$DOCKER_MW_VOLUME = getenv( 'MW_VOLUME' );

## Set $wgCacheDirectory to a writable directory on the web server
## to make your wiki go slightly faster. The directory should not
## be publicly accessible from the web.
$wgCacheDirectory = isEnvTrue( 'MW_USE_CACHE_DIRECTORY' ) ? "$DOCKER_MW_VOLUME/l10n_cache" : false;

# Include user defined CommonSettings.php file
if ( file_exists( $canastaCommonSettingsFilePath ) ) {
	require_once "$canastaCommonSettingsFilePath";
}

# Include user defined LocalSettings.php file
if ( file_exists( $canastaLocalSettingsFilePath ) ) {
	require_once "$canastaLocalSettingsFilePath";
}

$filenames = glob( getenv( 'MW_VOLUME' ) . '/config/settings/*.php' );

if ( $filenames !== false && is_array( $filenames ) ) {
	sort( $filenames );

	foreach ( $filenames as $filename ) {
		require_once "$filename";
	}
}

require_once getenv( 'MW_HOME' ) . '/temp-extension-setup.php';

# Include the FarmConfig
if ( file_exists( getenv( 'MW_VOLUME' ) . '/config/wikis.yaml' ) ) {
	require_once "$IP/FarmConfigLoader.php";
}
