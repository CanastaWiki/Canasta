<?php
# This file pretends to be a /sitemap.xml file (via Apache rewrite, see configs/.htaccess)

ini_set( 'display_errors', 0 );
error_reporting( 0 );

// Built per request, so a cached copy would go stale when sitemaps are
// regenerated. Canasta's Varnish config caches a bare no-cache response;
// max-age=0 stops it.
header( 'Cache-Control: no-cache, max-age=0' );

require_once __DIR__ . '/canasta-sitemaps.php';

$serverName = $_SERVER['HTTP_HOST'] ?? 'localhost';
$indexes = canastaHostSitemapIndexes( $serverName );

$ns = 'http://www.sitemaps.org/schemas/sitemap/0.9';
$out = new DOMDocument( '1.0', 'UTF-8' );
$out->formatOutput = true;
$root = $out->appendChild( $out->createElementNS( $ns, 'sitemapindex' ) );

foreach ( $indexes as $file ) {
	$in = new DOMDocument();
	$in->preserveWhiteSpace = false;
	if ( !@$in->load( $file, LIBXML_NONET ) ) {
		continue;
	}
	foreach ( $in->getElementsByTagNameNS( $ns, 'sitemap' ) as $entry ) {
		$root->appendChild( $out->importNode( $entry, true ) );
	}
}

if ( !$root->hasChildNodes() ) {
	http_response_code( 404 );
	header( 'Content-Type: text/plain' );
	echo "No sitemap has been generated for this site.\n";
	return;
}

header( 'Content-Type: application/xml; charset=UTF-8' );
echo $out->saveXML();
