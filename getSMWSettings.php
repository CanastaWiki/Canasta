<?php

/**
 * Based on code formerly contained in CanastaBase's getMediaWikiSettings.php.
 */

use MediaWiki\MediaWikiServices;
use MediaWiki\Settings\SettingsBuilder;

$mwHome = getenv( 'MW_HOME' );

if ( !defined( 'MW_CONFIG_FILE' ) && !file_exists( "$mwHome/LocalSettings.php" ) && !file_exists( "$mwHome/CommonSettings.php" ) ) {
	return;
}

require_once "$mwHome/maintenance/Maintenance.php";

class GetSMWSettings extends Maintenance {

	public function __construct() {
		parent::__construct();
		$this->addOption(
			'UpgradeKey',
			''
		);
		$this->addOption(
			'IncompleteSetupTasks',
			''
		);
	}

	public function execute() {
		$extensionRegistry = ExtensionRegistry::getInstance();
		$extThings = $extensionRegistry->getAllThings();
		if ( !array_key_exists( 'SemanticMediaWiki', $extThings ) ) {
		    $this->output( 'SMW_not_installed' );
			return;
		}

		SemanticMediaWiki::onExtensionFunction();

		if ( $this->hasOption( 'UpgradeKey' ) ) {
			$smwId = SMW\Site::id();
			this->output( $GLOBALS['smw.json'][$smwId]['upgrade_key'] ?? '' );
		} elseif ( $this->hasOption( 'IncompleteSetupTasks' ) ) {
			$SMWSetupFile = new SMW\SetupFile();
			$SMWIncompleteTasks = $SMWSetupFile->findIncompleteTasks();
			$this->output( implode( ' ', $SMWIncompleteTasks ) );
		}
	}

}

$maintClass = GetSMWSettings::class;
require RUN_MAINTENANCE_IF_MAIN;
