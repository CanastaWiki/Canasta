<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

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
