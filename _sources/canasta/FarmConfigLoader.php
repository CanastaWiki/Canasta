<?php

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

// // Echo ORIGINAL_URL for debugging
$original_url = getenv('ORIGINAL_URL');

// Parse YAML configuration file containing information about the wikis
$wikiConfigurations = null;

try {
    $file = getenv('MW_VOLUME') . '/config/wikis.yaml';

    if (!file_exists($file)) {
        throw new Exception('The configuration file does not exist');
    }

    $wikiConfigurations = yaml_parse_file($file);

    if ($wikiConfigurations === false) {
        throw new Exception('Error parsing the configuration file');
    }
} catch (Exception $e) {
    die('Caught exception: ' . $e->getMessage());
}

$serverName = null;
$path = null;

// Retrieve the server name and request path if available
if (isset($_SERVER['SERVER_NAME'])) {
    $serverName = $_SERVER['SERVER_NAME'];
    $path = explode('/', ltrim($original_url, '/'))[0];
    $path = rtrim($path, "wiki");
}

// Determine the wiki ID and select the corresponding configuration
$key = rtrim($serverName . '/' . $path, '/');

if (!array_key_exists($key, $urlToWikiIdMap)) {
    // Handle the missing key. In this case, we'll log a warning.
    error_log("Warning: $key does not exist in urlToWikiIdMap. Using default wiki ID.");
} else {
    $wikiID = defined('MW_WIKI_NAME') ? MW_WIKI_NAME : $urlToWikiIdMap[$key];
}

$selectedWikiConfig = $wikiIdToConfigMap[$wikiID] ?? null;

// If a matching configuration was found, configure the wiki database, else, terminate execution
if ($selectedWikiConfig) {
    $wgDBname = $wikiID;
    
    // Set $wgSitename and $wgMetaNamespace from the configuration
    $wgSitename = $selectedWikiConfig['name'];
    $wgMetaNamespace = $selectedWikiConfig['name'];
} else {
    die( 'Unknown wiki.' );
}

// Configure the wiki server and URL paths
$wgServer = "http://$serverName";
$wgScriptPath = ($path !== null && $path !== '') ? "/" . $path . "/w" : "/w";
$wgArticlePath = ($path !== null && $path !== '') ? "/" . $path ."/wiki/$1" : "/wiki/$1";
$wgCacheDirectory = "$IP/cache/$wikiID";
// $wgUploadDirectory = "$IP/images/$wikiID";
// $wgUploadPath = "$wgScriptPath/images/$wikiID";

foreach (glob(getenv( 'MW_VOLUME' ) . "/config/{$wikiID}/*.php") as $filename) {
	require_once $filename;
}