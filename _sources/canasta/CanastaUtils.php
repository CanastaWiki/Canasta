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

/**
 * Not exactly a utility function, but - show a warning to users if $wgSMTP is not set.
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
