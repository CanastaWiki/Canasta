<?php
// Shared by robots.php and sitemap.php; defines functions only.

/**
 * Sitemap index files of the wikis served on the requesting host.
 *
 * A wiki matches when the host part of its wikis.yaml url equals the
 * request's Host header, with or without a port on either side. Wikis
 * without generated sitemap files are skipped.
 *
 * @return string[] Absolute paths of sitemap index files
 */
function canastaHostSitemapIndexes( string $serverName ): array {
	$mwVolume = rtrim( getenv( 'MW_VOLUME' ) ?: '/mediawiki', '/' );
	$wikisYaml = "$mwVolume/config/wikis.yaml";
	$config = file_exists( $wikisYaml ) ? yaml_parse_file( $wikisYaml ) : null;
	if ( !$config || !isset( $config['wikis'] ) || !is_array( $config['wikis'] ) ) {
		return [];
	}

	$serverNameNoPort = preg_replace( '/:.*$/', '', $serverName );
	$indexes = [];
	foreach ( $config['wikis'] as $wiki ) {
		$wikiId = (string)( $wiki['id'] ?? '' );
		if ( $wikiId === '' || preg_match( '#[/\\\\]|^\.#', $wikiId ) ) {
			continue;
		}
		$wikiUrl = (string)( $wiki['url'] ?? '' );
		$slashPos = strpos( $wikiUrl, '/' );
		$wikiDomain = $slashPos !== false ? substr( $wikiUrl, 0, $slashPos ) : $wikiUrl;
		$wikiDomainNoPort = preg_replace( '/:.*$/', '', $wikiDomain );
		if ( $wikiDomain !== $serverName &&
			$wikiDomain !== $serverNameNoPort &&
			$wikiDomainNoPort !== $serverName &&
			$wikiDomainNoPort !== $serverNameNoPort ) {
			continue;
		}
		$found = glob( "$mwVolume/public_assets/$wikiId/sitemap/sitemap-index-*.xml" ) ?: [];
		sort( $found );
		array_push( $indexes, ...$found );
	}
	return $indexes;
}
