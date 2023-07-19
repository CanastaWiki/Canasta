<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
    exit;
}

$original_url = getenv( 'ORIGINAL_URL' );

if (!$original_url) {
    error_log('Warning: ORIGINAL_URL does not exist in the environment variables.');
}

// Parse YAML configuration file containing information about the wikis
$wikiConfigurations = null;

try {
    $file = getenv( 'MW_VOLUME' ) . '/config/wikis.yaml';

    if ( !file_exists( $file ) ) {
        throw new Exception( 'The configuration file does not exist' );
    }

    $wikiConfigurations = yaml_parse_file( $file );

    if ( $wikiConfigurations === false ) {
        throw new Exception( 'Error parsing the configuration file' );
    }
} catch ( Exception $e ) {
    die( 'Caught exception: ' . $e->getMessage() );
}

$wikiIdToConfigMap = [];
$urlToWikiIdMap = [];

// Populate the arrays using data from the configuration file
foreach ( $wikiConfigurations['wikis'] as $wiki ) {
    $urlToWikiIdMap[$wiki['url']] = $wiki['id'];
    $wikiIdToConfigMap[$wiki['id']] = $wiki;
}

$serverName = null;
$path = null;

// Retrieve the server name and request path if available
if ( isset( $_SERVER['SERVER_NAME'] ) ) {
    $serverName = $_SERVER['SERVER_NAME'];
    $path = explode( '/', ltrim( $original_url, '/' ) )[0];
    $path = rtrim( $path, "wiki" );
}

// Prepare a key
$key = rtrim( $serverName . '/' . $path, '/' );

// Retrieve the wikiID if available
$wikiID = defined( 'MW_WIKI_NAME' ) ? MW_WIKI_NAME : null;

if ( is_null( $wikiID ) && array_key_exists( $key, $urlToWikiIdMap ) ) {
    $wikiID = $urlToWikiIdMap[$key];
} else if ( is_null( $wikiID ) ) {
    error_log( "Warning: $key does not exist in urlToWikiIdMap." );
}

$selectedWikiConfig = $wikiIdToConfigMap[$wikiID] ?? null;

// If a matching configuration was found, configure the wiki database, else, terminate execution
if (!empty($selectedWikiConfig)) {
    $wgDBname = $wikiID;

    // Set $wgSitename and $wgMetaNamespace from the configuration
    $wgSitename = $selectedWikiConfig['name'];
    $wgMetaNamespace = $selectedWikiConfig['name'];
} else {
    die('Unknown wiki.');
}

// Configure the wiki server and URL paths
$wgServer = "http://$serverName";
$wgScriptPath = !empty( $path ) ? "/" . $path . "/w" : "/w";
$wgArticlePath = !empty( $path ) ? "/" . $path ."/wiki/$1" : "/wiki/$1";
$wgCacheDirectory = "$IP/cache/$wikiID";
// $wgUploadDirectory = "$IP/images/$wikiID";
// $wgUploadPath = "$wgScriptPath/images/$wikiID";

$files = glob( getenv( 'MW_VOLUME' ) . "/config/{$wikiID}/*.php" );
if ( $files !== false && count( $files ) > 0 ) {
    $firstFile = $files[0]; // get the first file, since glob() returns files sorted lexicographically
    require_once $firstFile;
    // other actions with the $firstFile
}
