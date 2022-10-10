<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

/**
 * @param $extName
 */
function cfLoadExtension( $extName ) {
	echo "Warning: As of Canasta 1.2.0, this function is deprecated. Use wfLoadExtension instead.";
	wfLoadExtension( $extName );
}

/**
 * @param $skinName
 */
function cfLoadSkin( $skinName ) {
	echo "Warning: As of Canasta 1.2.0, this function is deprecated. Use wfLoadSkin instead.";
	wfLoadSkin( $skinName );
}
