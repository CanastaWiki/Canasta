<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

## The URL base path to the directory containing the wiki;
## defaults for all runtime URL paths are based off of this.
## For more information on customizing the URLs
## (like /w/index.php/Page_title to /wiki/Page_title) please see:
## https://www.mediawiki.org/wiki/Manual:Short_URL
$wgScriptPath = "/w";
$wgScriptExtension = ".php";
$wgArticlePath = '/wiki/$1';
$wgStylePath = $wgScriptPath . '/canasta-skins';

## The URL path to static resources (images, scripts, etc.)
$wgResourceBasePath = $wgScriptPath;

# SyntaxHighlight_GeSHi
$wgPygmentizePath = '/usr/bin/pygmentize';

# We use job runner instead
$wgJobRunRate = 0;

# Docker specific setup
# see https://www.mediawiki.org/wiki/Manual:$wgCdnServersNoPurge
$wgUseCdn = true;
$wgCdnServersNoPurge = [];
$wgCdnServersNoPurge[] = '172.16.0.0/12';

/**
 * @param $extName
 */
function cfLoadExtension( $extName ) {
	global $wgExtensionDirectory, $wgExtensionAssetsPath;

	$realExtDirectory = $wgExtensionDirectory;
	$realExtAssetsPath = $wgExtensionAssetsPath;
	$wgExtensionDirectory .= '/../canasta-extensions';
	$wgExtensionAssetsPath .= '/../canasta-extensions';
	wfLoadExtension( $extName );
	$wgExtensionDirectory = $realExtDirectory;
	$wgExtensionAssetsPath = $realExtAssetsPath;
}

/**
 * @param $skinName
 */
function cfLoadSkin( $skinName ) {
	global $wgStyleDirectory, $wgStylePath;

	$realStyleDirectory = $wgStyleDirectory;
	$realStylePath = $wgStylePath;
	$wgStyleDirectory .= '/../canasta-skins';
	$wgStylePath .= '/../canasta-skins';
	wfLoadSkin( $skinName );
	$wgStyleDirectory = $realStyleDirectory;
	$wgStylePath = $realStylePath;
}
