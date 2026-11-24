<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

use Symfony\Component\Yaml\Yaml;

// Very-short-URL mode for wiki farms.
//
// When CANASTA_ENABLE_VERY_SHORT_URLS is false (the default), wikis can
// be at either bare hostnames or hostname/subdir URLs, and page URLs
// look like https://example.com/wiki1/wiki/PageName. The first segment
// of the request path is treated as a wiki identifier.
//
// When set to true, the "/wiki" segment goes away — page URLs become
// root-relative (https://wiki1.example.com/PageName) via
// $wgArticlePath = "/$1". Each wiki must then be on its own unique
// hostname with no path component, because there is no longer a path
// segment available to identify the wiki. Incompatible with the wiki
// directory feature and with any path-based wiki in wikis.yaml; both
// conditions are checked below.
$veryShortUrls = filter_var(
    getenv( 'CANASTA_ENABLE_VERY_SHORT_URLS' ),
    FILTER_VALIDATE_BOOLEAN
);

// Get the original URL from the environment variables
$original_url = getenv( 'ORIGINAL_URL' );
$serverName = "";
$path = "";

// Without a request URL (maintenance scripts), the server name and path
// come from the selected wiki's url in wikis.yaml instead
$useWikiUrl = false;

// Check if the original URL is defined
if ( $original_url === false ) {
	// In CLI mode, use the wiki named by --wiki, or else the first wiki
	if ( PHP_SAPI === 'cli' || defined( 'MW_WIKI_NAME' ) ) {
		$useWikiUrl = true;
	} else {
		return;
	}
}

// Parse the original URL
if ( !$useWikiUrl ) {
	$urlComponents = parse_url( $original_url );

	// Check if URL parsing was successful, else throw an exception
	if ( $urlComponents === false ) {
		throw new Exception( 'Error: Failed to parse the original URL' );
	}

	// Extract the server name (host) from the URL
	if ( isset( $urlComponents['host'] ) ) {
		$serverName = $urlComponents['host'];
		// Include port if present
		if ( isset( $urlComponents['port'] ) ) {
			$serverName .= ':' . $urlComponents['port'];
		}
	}

	// Extract the path from the URL, if any.
	//
	// In very-short-URL mode the path is intentionally left empty
	// — the first URL segment is a page title, not a wiki identifier.
	if ( !$veryShortUrls && isset( $urlComponents['path'] ) ) {
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
	$wikiConfigurations = Yaml::parseFile( $file );
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
			// In very-short-URL mode, every wiki must be on its own
			// unique hostname with no path component. Reject path-based
			// URLs early with a clear message — the alternative is
			// silently routing the wrong wiki to the wrong host. See
			// issue #138.
			if ( $veryShortUrls && strpos( $wiki['url'], '/' ) !== false ) {
				throw new Exception(
					"FarmConfigLoader: CANASTA_ENABLE_VERY_SHORT_URLS is "
					. "true but wiki '" . $wiki['id'] . "' has a path-based "
					. "URL ('" . $wiki['url'] . "'). Path-based wikis are "
					. "incompatible with very short URLs — each wiki must "
					. "be on its own unique hostname. Either remove this "
					. "wiki, change its URL to a unique hostname, or set "
					. "CANASTA_ENABLE_VERY_SHORT_URLS to false."
				);
			}
			if ( $veryShortUrls && isset( $urlToWikiIdMap[$wiki['url']] ) ) {
				throw new Exception(
					"FarmConfigLoader: hostname '" . $wiki['url'] . "' is "
					. "claimed by both wiki '" . $urlToWikiIdMap[$wiki['url']]
					. "' and wiki '" . $wiki['id'] . "'. Each wiki must be "
					. "on a unique hostname when CANASTA_ENABLE_VERY_SHORT_URLS "
					. "is true."
				);
			}
			$urlToWikiIdMap[$wiki['url']] = $wiki['id'];
			$wikiIdToConfigMap[$wiki['id']] = $wiki;
		} else {
			throw new Exception( 'Error: The wiki configuration is missing either the url or id attribute.' );
		}
	}
} else {
	throw new Exception( 'Error: Invalid wiki configurations.' );
}

// In very-short-URL mode, the wiki directory feature is incompatible
// — the directory route /wikis would collide with a page titled
// "Wikis" on any wiki using root-relative short URLs.
if ( $veryShortUrls
	&& getenv( 'CANASTA_ENABLE_WIKI_DIRECTORY' ) === 'true'
) {
	throw new Exception(
		"FarmConfigLoader: CANASTA_ENABLE_VERY_SHORT_URLS is true and "
		. "CANASTA_ENABLE_WIKI_DIRECTORY is true, but these features "
		. "are incompatible. The wiki directory is served at /wikis, "
		. "which collides with a page titled 'Wikis' on any wiki using "
		. "root-relative short URLs. Disable one or the other."
	);
}

// Prepare the key using the server name and the path
if ( empty( $path ) ) {
	$key = $serverName;
} else {
	$key = $serverName . '/' . $path;
}

// Retrieve the wikiID if available
$wikiID = defined( 'MW_WIKI_NAME' ) ? MW_WIKI_NAME : null;

if ( $useWikiUrl ) {
	// In CLI mode without specific wiki, default to the first wiki
	if ( $wikiID === null ) {
		$firstWiki = reset( $wikiConfigurations['wikis'] );
		if ( $firstWiki !== false && isset( $firstWiki['id'] ) ) {
			$wikiID = $firstWiki['id'];
		}
	}
	// Parse the wiki's URL to set serverName and path
	if ( $wikiID !== null && isset( $wikiIdToConfigMap[$wikiID] ) ) {
		$wikiUrl = $wikiIdToConfigMap[$wikiID]['url'];
		if ( strpos( $wikiUrl, '/' ) !== false ) {
			// URL contains a path component (e.g., "example.com/wiki1")
			$urlParts = explode( '/', $wikiUrl, 2 );
			$serverName = $urlParts[0];
			$path = $urlParts[1];
		} else {
			$serverName = $wikiUrl;
			$path = '';
		}
		$key = $wikiUrl;
	}
}

// Check if the path is the wiki directory route
if ( $path === 'wikis' && $wikiID === null ) {
	if ( getenv( 'CANASTA_ENABLE_WIKI_DIRECTORY' ) === 'true' ) {
		header( 'Cache-Control: no-cache, max-age=0' );
		header( 'Content-Type: text/html; charset=utf-8' );
		$directoryOnly = true;
		require __DIR__ . '/CanastaFarm404.php';
		exit;
	}
}

// Check if the key is null or if it exists in the urlToWikiIdMap, else throw an exception
if ( $key === null ) {
	throw new Exception( "Error: Key is null." );
} elseif ( $wikiID === null && array_key_exists( $key, $urlToWikiIdMap ) ) {
	$wikiID = $urlToWikiIdMap[$key];
} elseif ( $wikiID === null ) {
	HttpStatus::header( 404 );
	header( 'Cache-Control: no-cache, max-age=0' );
	header( 'Content-Type: text/html; charset=utf-8' );
	$directoryOnly = false;
	require __DIR__ . '/CanastaFarm404.php';
	exit;
}

// Get the configuration for the selected wiki
$selectedWikiConfig = $wikiIdToConfigMap[$wikiID] ?? null;

// Check if a matching configuration was found. If so, configure the wiki database, else terminate execution
if ( !empty( $selectedWikiConfig ) ) {
	// Set database name to the wiki ID
	$wgDBname = $wikiID;

	// Set site name from the configuration, or use the wiki ID if 'name' is not set
	$wgSitename = isset( $selectedWikiConfig['name'] ) ? $selectedWikiConfig['name'] : $wikiID;
	// Set meta namespace from site name with spaces replaced by underscores (required for valid namespace names)
	$wgMetaNamespace = str_replace( ' ', '_', $wgSitename );
} else {
	die( 'Unknown wiki.' );
}

// Configure the wiki server and URL paths
$scheme = parse_url( getenv( 'MW_SITE_SERVER' ) ?: 'https://localhost', PHP_URL_SCHEME ) ?: 'https';
$wgServer = "$scheme://$serverName";
$wgScriptPath = !empty( $path )
	? "/$path/w"
	: "/w";

// In very-short-URL mode, page URLs are root-relative (no /wiki/
// segment). $wgScriptPath stays at /w because MediaWiki's own files
// (api.php, load.php, edit forms, etc.) still live under /w/. The
// per-wiki Settings.php loaded below can still override $wgArticlePath
// if a particular wiki needs a different shape.
if ( $veryShortUrls ) {
	$wgArticlePath = "/$1";
} else {
	$wgArticlePath = !empty( $path )
		? "/$path/wiki/$1"
		: "/wiki/$1";
}
$wgCacheDirectory = "$IP/cache/$wikiID";
$wgUploadDirectory = "$IP/images/$wikiID";

// Load additional configuration files specific to the wiki ID
// Check new path first (config/settings/wikis/<wiki_id>/), fall back to legacy path (config/<wiki_id>/)
$wikiConfigDir = getenv( 'MW_VOLUME' ) . "/config/settings/wikis/{$wikiID}";
if ( !is_dir( $wikiConfigDir ) ) {
	$wikiConfigDir = getenv( 'MW_VOLUME' ) . "/config/{$wikiID}";
}

// Load extensions/skins from per-wiki YAML files (e.g. settings.yaml)
// before user PHP files so that user settings can configure loaded extensions.
canastaLoadConfigYaml( $wikiConfigDir );

$files = glob( $wikiConfigDir . '/*.php' );

// Check if the glob function was successful, else continue with the execution
if ( $files !== false && is_array( $files ) ) {
	// Sort the files
	sort( $files );

	// Include each file
	foreach ( $files as $filename ) {
		require_once "$filename";
	}
}
