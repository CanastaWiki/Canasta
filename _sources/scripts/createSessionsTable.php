<?php

require_once __DIR__ . '/Maintenance.php';

class CreateSessionsTable extends Maintenance {

	public function __construct() {
		parent::__construct();
		$this->addDescription(
			'Create the canasta_sessions table, which CanastaDefaultSettings.php keeps sessions in'
		);
	}

	public function execute() {
		$dbw = $this->getDB( DB_PRIMARY );
		if ( $dbw->tableExists( 'canasta_sessions', __METHOD__ ) ) {
			return;
		}
		$prefix = $dbw->tablePrefix();
		$dbw->duplicateTableStructure(
			"{$prefix}objectcache", "{$prefix}canasta_sessions", false, __METHOD__
		);
		$this->output( "Created the canasta_sessions table.\n" );
	}
}

$maintClass = CreateSessionsTable::class;
require RUN_MAINTENANCE_IF_MAIN;
