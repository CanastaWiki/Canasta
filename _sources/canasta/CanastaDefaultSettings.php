<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

require_once "$IP/CanastaUtils.php";

$canastaLocalSettingsFilePath = getenv( 'MW_VOLUME' ) . '/config/LocalSettings.php';
if ( defined( 'MW_CONFIG_CALLBACK' ) ) {
	// Called from WebInstaller or similar entry point

	if ( !file_exists( $canastaLocalSettingsFilePath ) ) {
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
if ( !is_readable( $canastaLocalSettingsFilePath ) ) {
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
# see https://www.mediawiki.org/wiki/Manual:$wgCdnServersNoPurge
$wgUseCdn = true;
$wgCdnServersNoPurge = [];
$wgCdnServersNoPurge[] = '172.16.0.0/12';
$wgCdnServersNoPurge[] = '192.168.0.0/16';
$wgCdnServersNoPurge[] = '10.0.0.0/8';

# Include user defined LocalSettings.php file
require_once "$canastaLocalSettingsFilePath";

# Include all php files in config/settings directory
foreach (glob(getenv( 'MW_VOLUME' ) . '/config/settings/*.php') as $filename) {
	require_once $filename;
}
