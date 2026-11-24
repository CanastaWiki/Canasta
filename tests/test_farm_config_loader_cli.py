"""Tests for the server and paths FarmConfigLoader.php sets in CLI mode.

Maintenance scripts have no request URL, so the loader takes the server
name and wiki path from the selected wiki's url in wikis.yaml: the wiki
named by --wiki, or the first wiki when none is named. The loader runs
through the real php binary with stand-ins for the MediaWiki pieces it
calls.
"""

import json
import os
import shutil
import subprocess

import pytest


pytestmark = pytest.mark.skipif(
    shutil.which("php") is None,
    reason="php is required to run FarmConfigLoader.php",
)

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOADER = os.path.join(REPO_ROOT, "_sources", "canasta", "FarmConfigLoader.php")

# wikis.yaml is written as JSON, which is valid YAML, so the Yaml
# stand-in can parse it without the Symfony component.
HARNESS = """<?php
namespace Symfony\\Component\\Yaml {
	class Yaml {
		public static function parseFile( $f ) {
			return json_decode( file_get_contents( $f ), true );
		}
	}
}
namespace {
	define( 'MEDIAWIKI', true );
	if ( $argv[2] !== '' ) {
		define( 'MW_WIKI_NAME', $argv[2] );
	}
	function canastaLoadConfigYaml( $dir ) {
	}
	$IP = '/var/www/mediawiki/w';
	require $argv[1];
	echo json_encode( [
		'dbname' => $wgDBname,
		'server' => $wgServer,
		'scriptPath' => $wgScriptPath,
		'articlePath' => $wgArticlePath,
	] );
}
"""


@pytest.fixture
def loader(tmp_path):
    mw_volume = tmp_path / "mediawiki"
    (mw_volume / "config").mkdir(parents=True)
    harness = tmp_path / "harness.php"
    harness.write_text(HARNESS)

    def _run(wikis, wiki=None, env=None):
        (mw_volume / "config" / "wikis.yaml").write_text(
            json.dumps({"wikis": wikis}))
        run_env = os.environ.copy()
        for name in ("ORIGINAL_URL", "CANASTA_ENABLE_VERY_SHORT_URLS",
                     "CANASTA_ENABLE_WIKI_DIRECTORY"):
            run_env.pop(name, None)
        run_env.update({"MW_VOLUME": str(mw_volume),
                        "MW_SITE_SERVER": "https://example.com"})
        run_env.update(env or {})
        result = subprocess.run(
            ["php", str(harness), LOADER, wiki or ""],
            env=run_env, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        return json.loads(result.stdout)

    return _run


FARM = [
    {"id": "de", "url": "example.com/de"},
    {"id": "en", "url": "example.com/en"},
]


class TestNamedWiki:
    def test_path_based_wiki_after_the_first(self, loader):
        assert loader(FARM, wiki="en") == {
            "dbname": "en",
            "server": "https://example.com",
            "scriptPath": "/en/w",
            "articlePath": "/en/wiki/$1",
        }

    def test_first_wiki_by_name(self, loader):
        result = loader(FARM, wiki="de")
        assert result["server"] == "https://example.com"
        assert result["articlePath"] == "/de/wiki/$1"

    def test_domain_based_wiki(self, loader):
        wikis = [{"id": "a", "url": "a.example.com"},
                 {"id": "b", "url": "b.example.com:8443"}]
        result = loader(wikis, wiki="b")
        assert result["server"] == "https://b.example.com:8443"
        assert result["scriptPath"] == "/w"
        assert result["articlePath"] == "/wiki/$1"

    def test_scheme_comes_from_mw_site_server(self, loader):
        result = loader(FARM, wiki="en",
                        env={"MW_SITE_SERVER": "http://localhost"})
        assert result["server"] == "http://example.com"

    def test_very_short_urls(self, loader):
        wikis = [{"id": "a", "url": "a.example.com"},
                 {"id": "b", "url": "b.example.com"}]
        result = loader(wikis, wiki="b",
                        env={"CANASTA_ENABLE_VERY_SHORT_URLS": "true"})
        assert result["server"] == "https://b.example.com"
        assert result["articlePath"] == "/$1"


class TestNoWikiNamed:
    def test_defaults_to_the_first_wiki(self, loader):
        assert loader(FARM) == {
            "dbname": "de",
            "server": "https://example.com",
            "scriptPath": "/de/w",
            "articlePath": "/de/wiki/$1",
        }
