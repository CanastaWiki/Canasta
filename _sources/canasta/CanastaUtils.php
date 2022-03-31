<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

/**
 * @param $extName
 */
function cfLoadExtension( $extName ) {
	global $wgExtensionDirectory, $wgExtensionAssetsPath, $IP, $wgScriptPath;

	$realExtDirectory = $wgExtensionDirectory;
	$realExtAssetsPath = $wgExtensionAssetsPath;
	$wgExtensionDirectory = $IP . '/canasta-extensions';
	$wgExtensionAssetsPath = $wgScriptPath . '/canasta-extensions';
	wfLoadExtension( $extName );
	$wgExtensionDirectory = $realExtDirectory;
	$wgExtensionAssetsPath = $realExtAssetsPath;
}

/**
 * @param $skinName
 */
function cfLoadSkin( $skinName ) {
	global $wgStyleDirectory, $wgStylePath, $IP, $wgScriptPath;

	$realStyleDirectory = $wgStyleDirectory;
	$realStylePath = $wgStylePath;
	$wgStyleDirectory = $IP . '/canasta-skins';
	$wgStylePath = $wgScriptPath . '/canasta-skins';
	wfLoadSkin( $skinName );
	$wgStyleDirectory = $realStyleDirectory;
	$wgStylePath = $realStylePath;
}
