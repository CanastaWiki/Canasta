<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

/**
 * @param $extName
 */
function cfLoadExtension( $extName ) {
	echo "Error: As of Canasta 1.3.0, the cfLoadExtension function has been removed. Use wfLoadExtension instead.\r\n";
	echo "The following extension was loaded with cfLoadExtension, but needs to be loaded with wfLoadExtension instead: $extName";
	die();
}

/**
 * @param $skinName
 */
function cfLoadSkin( $skinName ) {
	echo "Error: As of Canasta 1.3.0, the cfLoadSkin function has been removed. Use wfLoadSkin instead.\r\n";
	echo "The following skin was loaded with cfLoadSkin, but needs to be loaded with wfLoadSkin instead: $skinName";
	die();
}
