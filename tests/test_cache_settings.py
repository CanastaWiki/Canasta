"""Tests for the cache and session settings in CanastaDefaultSettings.php.

The main cache is APCu unless CANASTA_ENABLE_REDIS is true, and sessions
are stored in the canasta_sessions database table either way.
"""

import json
import os
import re
import shutil
import subprocess

import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SETTINGS = os.path.join(
    REPO_ROOT, "_sources", "canasta", "CanastaDefaultSettings.php"
)

pytestmark = pytest.mark.skipif(shutil.which("php") is None, reason="needs php")


def cache_section():
    with open(SETTINGS) as f:
        source = f.read()
    start = source.index("# Main cache:")
    end = source.index("# Varnish cache configuration")
    is_env_true = re.search(
        r"^function isEnvTrue\(.*?^}$", source, re.S | re.M
    ).group(0)
    return source[start:end] + "\n" + is_env_true


def settings(env):
    script = (
        "define('CACHE_DB', 'db'); define('CACHE_ACCEL', 'accel');"
        "$wgObjectCaches = []; $wgHooks = [];"
        + cache_section()
        + "echo json_encode(['main' => $wgMainCacheType,"
        " 'redis' => $wgObjectCaches['redis'] ?? null,"
        " 'session' => $wgSessionCacheType]);"
    )
    full_env = {k: v for k, v in os.environ.items() if k != "CANASTA_ENABLE_REDIS"}
    full_env.update(env)
    result = subprocess.run(
        ["php", "-r", script], env=full_env, capture_output=True, text=True,
        check=True,
    )
    return json.loads(result.stdout)


@pytest.mark.parametrize("env", [{}, {"CANASTA_ENABLE_REDIS": "false"}])
def test_apcu_without_redis(env):
    assert settings(env) == {"main": "accel", "redis": None, "session": "canasta-sessions"}


@pytest.mark.parametrize("value", ["true", "1"])
def test_redis_when_enabled(value):
    assert settings({"CANASTA_ENABLE_REDIS": value}) == {
        "main": "redis",
        "redis": {
            "class": "Wikimedia\\ObjectCache\\RedisBagOStuff",
            "servers": ["redis:6379"],
        },
        "session": "canasta-sessions",
    }


def run_cache_section(code):
    script = (
        "define('CACHE_DB', 'db'); define('CACHE_ACCEL', 'accel');"
        "$wgObjectCaches = []; $wgHooks = [];"
        + cache_section()
        + code
    )
    env = {k: v for k, v in os.environ.items() if k != "CANASTA_ENABLE_REDIS"}
    result = subprocess.run(
        ["php", "-r", script], env=env, capture_output=True, text=True,
        check=True,
    )
    return json.loads(result.stdout)


def test_sessions_use_their_own_table():
    assert run_cache_section(
        "echo json_encode($wgObjectCaches['canasta-sessions']);"
    ) == {
        "class": "SqlBagOStuff",
        "loggroup": "SQLBagOStuff",
        "tableName": "canasta_sessions",
    }


@pytest.mark.parametrize("db_type, expected", [
    ("mysql", [["canasta_sessions", "canasta_sessions.sql"]]),
    ("sqlite", []),
])
def test_update_creates_the_sessions_table_on_mysql(db_type, expected):
    tables = run_cache_section(
        "$updater = new class( '%s' ) {"
        " public $tables = [];"
        " public function __construct( private $type ) {}"
        " public function getDB() { $t = $this->type;"
        "  return new class( $t ) { public function __construct( private $t ) {}"
        "   public function getType() { return $this->t; } }; }"
        " public function addExtensionTable( $name, $path ) {"
        "  $this->tables[] = [ $name, basename( $path ) ]; }"
        "};"
        "foreach ( $wgHooks['LoadExtensionSchemaUpdates'] as $hook ) { $hook( $updater ); }"
        "echo json_encode( $updater->tables );" % db_type
    )
    assert tables == expected


def test_sessions_table_sql_copies_objectcache():
    with open(os.path.join(REPO_ROOT, "_sources", "canasta", "canasta_sessions.sql")) as f:
        assert f.read().strip() == (
            "CREATE TABLE /*_*/canasta_sessions LIKE /*_*/objectcache;"
        )


def test_image_ships_the_sessions_table_files():
    with open(os.path.join(REPO_ROOT, "Dockerfile")) as f:
        dockerfile = f.read()
    assert re.search(
        r"^COPY .*_sources/canasta/canasta_sessions\.sql .*\$MW_HOME/$",
        dockerfile, re.M,
    )
    assert re.search(r"^COPY _sources/scripts/\*\.php \$MW_HOME/maintenance/$", dockerfile, re.M)
    assert os.path.exists(
        os.path.join(REPO_ROOT, "_sources", "scripts", "createSessionsTable.php")
    )
