<?php
// If the script is not running in the MediaWiki environment, terminate execution
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

// Parse YAML configuration file containing information about the wikis
$wikiConfigurations = @yaml_parse_file(getenv('MW_VOLUME') . '/config/wikis.yaml');

// Initialize an array to map wiki IDs to their respective configurations and URLs
$wikiIdToConfigMap = [];
$urlToWikiIdMap = [];

// Populate the arrays using data from the configuration file
foreach ($wikiConfigurations['wikis'] as $wiki) {
    $urlToWikiIdMap[$wiki['url']] = $wiki['id'];
    $wikiIdToConfigMap[$wiki['id']] = $wiki;
}

$serverName = null;
$path = null;

// Retrieve the server name and request path if available
if (isset($_SERVER['SERVER_NAME'])) {
    $serverName = $_SERVER['SERVER_NAME'];
    $path = explode('/', ltrim($_SERVER['REQUEST_URI'], '/'))[0];
    $path = rtrim($path,"wiki");
}

// Determine the wiki ID and select the corresponding configuration
$wikiID = defined('MW_DB') ? MW_DB : ($urlToWikiIdMap[rtrim($serverName . '/' . $path, '/')] ?? null);

$selectedWikiConfig = $wikiIdToConfigMap[$wikiID] ?? null;

// If a matching configuration was found, configure the wiki database, else, terminate execution
if ($selectedWikiConfig) {
    $wgDBname = $wikiID;
} else {
    die( 'Unknown wiki.' );
}

foreach (glob(getenv( 'MW_VOLUME' ) . "/config/{$wikiID}/settings/*.php") as $filename) {
	require_once $filename;
}

// Configure the wiki server and URL paths
$wgServer = "http://$serverName";
$wgScriptPath = ($path !== null && $path !== '') ? "/" . $path . "/w" : "/w";
$wgArticlePath = ($path !== null && $path !== '') ? "/" . $path ."/wiki/$1" : "/wiki/$1";
