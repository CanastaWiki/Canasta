<?php

/**
 * generate-yaml.php - for a specific MediaWiki version, and a specific "type"
 * (extensions or skins), create and output YAML that matches the current
 * relevant YAML file in Canasta, but with the "commit" value set to the latest
 * revision in the relevant branch (where possible).
 *
 * Sample call:
 * php generate-yaml.php --version 1.43 --type extensions
 *
 * This script is not called during the regular operation of Canasta - rather,
 * it's a helper script that is meant to help with generating/updating
 * extensions.yaml and skins.yaml.
 *
 * @author Yaron Koren
 */

$options = getopt( 'v:t:', [ 'version:', 'type:' ] );

if ( array_key_exists( 'version', $options ) ) {
	$version = $options['version'];
} elseif ( array_key_exists( 'v', $options ) ) {
	$version = $options['v'];
} else {
	die( "Version must be set.\n" );
}

if ( array_key_exists( 'type', $options ) ) {
	$type = $options['type'];
} elseif ( array_key_exists( 't', $options ) ) {
	$type = $options['t'];
} else {
	die( "Type must be set.\n" );
}

if ( $type !== 'extensions' && $type !== 'skins' ) {
	die( "Type must be either 'extensions' or 'skins'.\n" );
}

$branch = 'REL' . str_replace( '.', '_', $version );

$yamlText = file_get_contents( "https://raw.githubusercontent.com/CanastaWiki/Canasta/refs/heads/master/_sources/configs/$type.yaml" );

$curContents = yaml_parse( $yamlText );

foreach ( $curContents[$type] as &$element ) {
	foreach ( $element as $elementName => &$details ) {
		if ( array_key_exists( 'bundled', $details ) ) {
			continue;
		}
		if ( array_key_exists( 'branch', $details ) ) {
			// If there's a branch set, just remove it - we'll hope
			// that the default branch's version can be used.
			unset( $details['branch'] );
		}
		if ( array_key_exists( 'repository', $details ) ) {
			// If it's not on Gerrit, this should be retrieved manually.
			$latestRevision = '???';
		} else {
			$latestRevision = getLatestRevisionForBranch( $type, $elementName, $branch );
		}
		$details['commit'] = $latestRevision;
	}
}

print yaml_emit( $curContents );

function getLatestRevisionForBranch( $type, $elementName, $branch ) {
	$branchPageURL = "https://gerrit.wikimedia.org/r/plugins/gitiles/mediawiki/$type/$elementName/+log/refs/heads/$branch";
	$branchPageContents = file_get_contents( $branchPageURL );
	if ( !$branchPageContents ) {
		return null;
	}
	// The first revision number we encounter will presumably be the most
	// recent one.
	preg_match( '/([0-9a-f]{40})/', $branchPageContents, $matches );
	return $matches[1];
}
