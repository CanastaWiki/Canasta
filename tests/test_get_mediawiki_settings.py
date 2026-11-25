"""Tests for the output formats of _sources/canasta/getMediawikiSettings.php.

The startup scripts read settings through this script and parse what it
prints, so each --format must print exactly what they expect. MediaWiki's
maintenance framework is replaced by stubs that run execute() with the
command-line options; the stubs define each class under its namespaced name
and its global alias, as MediaWiki does.
"""

import json
import os
import shutil
import subprocess
import textwrap
from hashlib import md5

import pytest

from conftest import REPO_ROOT

SCRIPT = os.path.join(REPO_ROOT, "_sources", "canasta", "getMediawikiSettings.php")

pytestmark = pytest.mark.skipif(shutil.which("php") is None,
                                reason="php not available")

MAINTENANCE_STUB = textwrap.dedent(r"""
    <?php
    namespace MediaWiki\Settings {
        class SettingsBuilder {}
    }
    namespace MediaWiki\Config {
        class StubConfig {
            public function has( $name ) {
                return array_key_exists( $name, $GLOBALS['stubConfig'] );
            }
            public function get( $name ) {
                return $GLOBALS['stubConfig'][$name];
            }
        }
    }
    namespace MediaWiki {
        class MediaWikiServices {
            public static function getInstance() { return new self; }
            public function getMainConfig() { return new Config\StubConfig; }
        }
    }
    namespace MediaWiki\Json {
        class FormatJson {
            public static function encode( $value ) { return json_encode( $value ); }
        }
    }
    namespace MediaWiki\Specials {
        class SpecialVersion {
            public static function getVersion( $flags = '' ) { return '1.43.1'; }
        }
    }
    namespace MediaWiki\Utils {
        class GitInfo {
            private $path;
            public function __construct( $path ) { $this->path = $path; }
            public function getHeadSHA1() {
                return $GLOBALS['stubGit'][$this->path] ?? false;
            }
        }
    }
    namespace MediaWiki\Registration {
        class ExtensionRegistry {
            public static function getInstance() { return new self; }
            public function getAllThings() { return $GLOBALS['stubExtensions']; }
        }
    }
    namespace MediaWiki\Maintenance {
        abstract class Maintenance {
            public const DB_NONE = 0;
            private $options = [];
            public function __construct() {}
            public function addOption( $name, ...$rest ) {}
            public function hasOption( $name ) {
                return array_key_exists( $name, $this->options );
            }
            public function getOption( $name, $default = null ) {
                return $this->options[$name] ?? $default;
            }
            public function output( $out ) { echo $out; }
            public function finalSetup( ?\MediaWiki\Settings\SettingsBuilder $settingsBuilder = null ) {}
            public function loadArgs( array $args ) {
                foreach ( $args as $arg ) {
                    if ( preg_match( '/^--([^=]+)(?:=(.*))?$/s', $arg, $m ) ) {
                        $this->options[$m[1]] = $m[2] ?? 1;
                    }
                }
            }
        }
    }
    namespace {
        class_alias( MediaWiki\Json\FormatJson::class, 'FormatJson' );
        class_alias( MediaWiki\Specials\SpecialVersion::class, 'SpecialVersion' );
        class_alias( MediaWiki\Utils\GitInfo::class, 'GitInfo' );
        class_alias( MediaWiki\Registration\ExtensionRegistry::class, 'ExtensionRegistry' );
        class_alias( MediaWiki\Maintenance\Maintenance::class, 'Maintenance' );
        $settings = json_decode( getenv( 'STUB_SETTINGS' ), true );
        $stubConfig = $settings['config'];
        $stubExtensions = $settings['extensions'];
        $stubGit = $settings['git'];
        foreach ( $settings['globals'] as $name => $value ) {
            $GLOBALS[$name] = $value;
        }
        define( 'RUN_MAINTENANCE_IF_MAIN', __DIR__ . '/doMaintenance.php' );
    }
    """).lstrip()

DO_MAINTENANCE_STUB = textwrap.dedent("""\
    <?php
    $maintenance = new $maintClass();
    $maintenance->loadArgs( array_slice( $argv, 1 ) );
    $maintenance->execute();
    """)


@pytest.fixture
def settings(tmp_path):
    mw_home = tmp_path / "w"
    (mw_home / "maintenance").mkdir(parents=True)
    (mw_home / "LocalSettings.php").write_text("<?php\n")
    (mw_home / "maintenance" / "Maintenance.php").write_text(MAINTENANCE_STUB)
    (mw_home / "maintenance" / "doMaintenance.php").write_text(DO_MAINTENANCE_STUB)

    def _run(*args, config=None, extensions=None, git=None, globals_=None):
        stub = {"config": config or {}, "extensions": extensions or {},
                "git": git or {}, "globals": globals_ or {}}
        env = dict(os.environ, MW_HOME=str(mw_home),
                   STUB_SETTINGS=json.dumps(stub))
        result = subprocess.run(
            ["php", "-d", "display_errors=stderr", SCRIPT] + list(args),
            env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout

    return _run


SERVERS = ["db1", "db2"]


@pytest.mark.parametrize("fmt, expected", [
    ("string", "mysql"),
    ("json", '"mysql"'),
    ("md5", md5(b"mysql").hexdigest()),
    ("first", "mysql"),
    ("semicolon", "mysql"),
    ("space", "mysql"),
])
def test_string_value(settings, fmt, expected):
    out = settings("--variable=wgDBtype", "--format=" + fmt,
                   config={"wgDBtype": "mysql"})
    assert out == expected


def test_string_is_the_default_format(settings):
    assert settings("--variable=wgDBtype", config={"wgDBtype": "mysql"}) == "mysql"


@pytest.mark.parametrize("fmt, expected", [
    ("json", '["db1","db2"]'),
    ("first", "db1"),
    ("semicolon", "db1;db2"),
    ("space", "db1 db2"),
    ("md5", md5(b'["db1","db2"]').hexdigest()),
])
def test_array_value(settings, fmt, expected):
    out = settings("--variable=wgServers", "--format=" + fmt,
                   config={"wgServers": SERVERS})
    assert out == expected


def test_array_defaults_to_json(settings):
    out = settings("--variable=wgDBservers",
                   config={"wgDBservers": [{"host": "db", "type": "mysql"}]})
    assert json.loads(out) == [{"host": "db", "type": "mysql"}]


def test_first_of_empty_array_is_empty(settings):
    assert settings("--variable=wgDBservers", "--format=first",
                    config={"wgDBservers": []}) == ""


def test_json_format_is_case_insensitive(settings):
    assert settings("--variable=wgDBtype", "--format=JSON",
                    config={"wgDBtype": "mysql"}) == '"mysql"'


def test_falls_back_to_global(settings):
    out = settings("--variable=wgSomethingGlobal",
                   globals_={"wgSomethingGlobal": "from-global"})
    assert out == "from-global"


def test_unknown_variable_is_empty(settings):
    assert settings("--variable=wgNoSuchSetting") == ""


def test_versions(settings, tmp_path):
    ext_path = str(tmp_path / "extensions" / "Foo")
    out = settings("--versions", extensions={
        "Foo": {"version": "1.2", "path": ext_path + "/extension.json"},
        "Bar": {"version": "3.0"},
        "Baz": {"path": "/nowhere/extension.json"},
    }, git={ext_path: "0123456789abcdef"})
    assert json.loads(out) == {
        "MediaWiki": "1.43.1",
        "Foo": "1.2 (0123456)",
        "Bar": "3.0",
        "Baz": " ()",
    }


def test_versions_md5_is_md5_of_the_json(settings):
    extensions = {"Bar": {"version": "3.0"}}
    out = settings("--versions", "--format=md5", extensions=extensions)
    expected = json.dumps({"MediaWiki": "1.43.1", "Bar": "3.0"},
                          separators=(",", ":")).encode()
    assert out == md5(expected).hexdigest()
