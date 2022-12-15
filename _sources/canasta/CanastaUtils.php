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

/**
 * Not exactly a utility function, but - show a warning to users if $wgSMTP is not set.
 */
$wgHooks['SiteNoticeAfter'][] = 'showSMTPWarning';
function showSMTPWarning( &$siteNotice, Skin $skin ) {
	global $wgSMTP;

	if ( $wgSMTP !== false ) {
		return true;
	}
	$title = $skin->getTitle();
	if ( !$title->isSpecialPage() ) {
		return true;
	}
	$specialPage = MediaWiki\MediaWikiServices::getInstance()
		->getSpecialPageFactory()
		->getPage( $title->getText() );
	$canonicalName = $specialPage->getName();
	// Only display this warning for pages that could result in an email getting sent.
	if ( !in_array( $canonicalName, [ 'Preferences', 'CreateAccount', 'Emailuser' ] ) ) {
		return true;
	}

	$siteNotice .= '<div class="warningbox"><big>Please note that mailing does not currently work on this wiki, because Canasta requires <a href="https://www.mediawiki.org/wiki/Manual:$wgSMTP">$wgSMTP</a> to be set in order to send emails.</big></div>';
	return true;
}
