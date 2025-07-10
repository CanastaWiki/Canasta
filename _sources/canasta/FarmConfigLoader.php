<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

// Get the original URL from the environment variables
$original_url = getenv( 'ORIGINAL_URL' );
$serverName = "";
$path = "";

// Check if the original URL is defined, else throw an exception
if ( $original_url === false && !defined( 'MW_WIKI_NAME' ) ) {
	return;
}

// Parse the original URL
$urlComponents = parse_url( $original_url );

// Check if URL parsing was successful, else throw an exception
if ( $urlComponents === false ) {
	throw new Exception( 'Error: Failed to parse the original URL' );
}

// Extract the server name (host) from the URL
if ( isset( $urlComponents['host'] ) ) {
	$serverName = $urlComponents['host'];
}

// Extract the path from the URL, if any
if ( isset( $urlComponents['path'] ) ) {
	// Split the path into parts
	$pathParts = explode( '/', trim( $urlComponents['path'], '/' ) );

	// Check if path splitting was successful, else throw an exception
	if ( $pathParts === false ) {
		throw new Exception( 'Error: Failed to split the path into parts' );
	}

	// If there is a path, store the first directory in the variable $path
	if ( count( $pathParts ) > 0 ) {
		$firstDirectory = $pathParts[0];
	}

	// If the first directory is not "wiki" or "w", store it in the variable $path
	if ( $firstDirectory != "wiki" && $firstDirectory != "w" ) {
		$path = $firstDirectory;
	}
}

// Parse the YAML configuration file containing the wiki information
$wikiConfigurations = null;

try {
	// Get the file path of the YAML configuration file
	$file = getenv( 'MW_VOLUME' ) . '/config/wikis.yaml';

	// Check if the configuration file exists, else throw an exception
	if ( !file_exists( $file ) ) {
		throw new Exception( 'The configuration file does not exist' );
	}

	// Parse the configuration file
	$wikiConfigurations = yaml_parse_file( $file );

	// Check if file parsing was successful, else throw an exception
	if ( $wikiConfigurations === false ) {
		throw new Exception( 'Error parsing the configuration file' );
	}
} catch ( Exception $e ) {
	die( 'Caught exception: ' . $e->getMessage() );
}

$wikiIdToConfigMap = [];
$urlToWikiIdMap = [];

// Populate the arrays with data from the configuration file
if ( isset( $wikiConfigurations ) && isset( $wikiConfigurations['wikis'] ) && is_array( $wikiConfigurations['wikis'] ) ) {
	foreach ( $wikiConfigurations['wikis'] as $wiki ) {
		// Check if 'url' and 'id' are set before using them
		if ( isset( $wiki['url'] ) && isset( $wiki['id'] ) ) {
			$urlToWikiIdMap[$wiki['url']] = $wiki['id'];
			$wikiIdToConfigMap[$wiki['id']] = $wiki;
		} else {
			throw new Exception( 'Error: The wiki configuration is missing either the url or id attribute.' );
		}
	}
} else {
	throw new Exception( 'Error: Invalid wiki configurations.' );
}

// Prepare the key using the server name and the path
if ( empty( $path ) ) {
	$key = $serverName;
} else {
	$key = $serverName . '/' . $path;
}

// Retrieve the wikiID if available
$wikiID = defined( 'MW_WIKI_NAME' ) ? MW_WIKI_NAME : null;

// Check if the key is null or if it exists in the urlToWikiIdMap, else throw an exception
if ( $key === null ) {
	throw new Exception( "Error: Key is null." );
} elseif ( $wikiID === null && array_key_exists( $key, $urlToWikiIdMap ) ) {
	$wikiID = $urlToWikiIdMap[$key];
} elseif ( $wikiID === null ) {
	HttpStatus::header( 404 );
	header( 'Cache-Control: no-cache' );
	header( 'Content-Type: text/html; charset=utf-8' );
	echo("URL not found");
	throw new Exception( "Error: $key does not exist in urlToWikiIdMap." );
}

// Get the configuration for the selected wiki
$selectedWikiConfig = $wikiIdToConfigMap[$wikiID] ?? null;

// Check if a matching configuration was found. If so, configure the wiki database, else terminate execution
if ( !empty( $selectedWikiConfig ) ) {
	// Set database name to the wiki ID
	$wgDBname = $wikiID;

	// Set site name and meta namespace from the configuration, or use the wiki ID if 'name' is not set
	$wgSitename = isset( $selectedWikiConfig['name'] ) ? $selectedWikiConfig['name'] : $wikiID;
	$wgMetaNamespace = isset( $selectedWikiConfig['name'] ) ? $selectedWikiConfig['name'] : $wikiID;
} else {
	die( 'Unknown wiki.' );
}

// Configure the wiki server and URL paths
$wgServer = "https://$serverName";
$wgScriptPath = !empty( $path )
	? "/$path/w"
	: "/w";

$wgArticlePath = !empty( $path )
	? "/$path/wiki/$1"
	: "/wiki/$1";
$wgCacheDirectory = "$IP/cache/$wikiID";
$wgUploadDirectory = "$IP/images/$wikiID";

// Load additional configuration files specific to the wiki ID
$files = glob( getenv( 'MW_VOLUME' ) . "/config/{$wikiID}/*.php" );

$wgEnableUploads = true;

// Check if the glob function was successful, else continue with the execution
if ( $files !== false && is_array( $files ) ) {
	// Sort the files
	sort( $files );

	// Include each file
	foreach ( $files as $filename ) {
		require_once "$filename";
	}
}
