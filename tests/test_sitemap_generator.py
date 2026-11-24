"""Tests for the background sitemap generator, sitemap_generator.sh.

The real script runs one pass of its loop with stand-ins on PATH: php
records each generateSitemap.php call and writes the files it would
write, and sleep ends the script at the end of the pass. Reading
wikis.yaml still runs through the real php binary.
"""

import json
import os
import shutil
import subprocess

import pytest


pytestmark = pytest.mark.skipif(
    shutil.which("php") is None,
    reason="php is required to read wikis.yaml",
)

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPT = os.path.join(REPO_ROOT, "_sources", "scripts",
                      "maintenance-scripts", "sitemap_generator.sh")

# wikis.yaml is written as JSON, which is valid YAML; the shim stands in
# for the yaml extension where the local php lacks it.
YAML_SHIM = """<?php
if ( !function_exists( 'yaml_parse_file' ) ) {
	function yaml_parse_file( $f ) { return json_decode( file_get_contents( $f ), true ); }
}
"""

PHP_STUB = """#!/bin/bash
if [ "$1" = "-r" ]; then
    exec "$REAL_PHP" -r "require getenv('YAML_SHIM'); $2"
fi
shift
printf '%s\\n' "$*" >> "$CALLS"
for arg in "$@"; do
    case "$arg" in
        --fspath=*) fspath="${arg#--fspath=}" ;;
        --identifier=*) identifier="${arg#--identifier=}" ;;
    esac
done
if [ -n "$PHP_FAIL" ]; then
    exit 1
fi
touch "$fspath/sitemap-index-$identifier.xml" "$fspath/sitemap-$identifier-NS_0-0.xml.gz"
"""

SLEEP_STUB = """#!/bin/bash
[ "$1" = 30 ] && exit 0
kill -TERM "$PPID"
"""


@pytest.fixture
def generator(tmp_path):
    mw_volume = tmp_path / "mediawiki"
    (mw_volume / "config").mkdir(parents=True)
    mw_home = tmp_path / "w"
    mw_home.mkdir()
    (mw_home / "public_assets").symlink_to(mw_volume / "public_assets",
                                           target_is_directory=True)
    (mw_volume / "public_assets").mkdir()
    log_dir = tmp_path / "log"
    log_dir.mkdir()
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name, body in (("php", PHP_STUB), ("sleep", SLEEP_STUB)):
        stub = bin_dir / name
        stub.write_text(body)
        stub.chmod(0o755)
    shim = tmp_path / "yaml_shim.php"
    shim.write_text(YAML_SHIM)
    calls = tmp_path / "calls"

    class Generator:
        def sitemap_dir(self, wiki_id):
            return mw_volume / "public_assets" / wiki_id / "sitemap"

        def opt_in(self, wiki_id, *files):
            directory = self.sitemap_dir(wiki_id)
            directory.mkdir(parents=True, exist_ok=True)
            for name in files or ("sitemap-index-%s.xml" % wiki_id,):
                (directory / name).touch()

        def files(self, wiki_id):
            return sorted(os.listdir(self.sitemap_dir(wiki_id)))

        def run(self, wikis, env=None):
            (mw_volume / "config" / "wikis.yaml").write_text(
                json.dumps({"wikis": wikis}))
            if calls.exists():
                calls.unlink()
            run_env = os.environ.copy()
            run_env.pop("MW_SITEMAP_URL_PATH", None)
            run_env.update({
                "PATH": "%s:%s" % (bin_dir, run_env["PATH"]),
                "REAL_PHP": shutil.which("php"),
                "YAML_SHIM": str(shim),
                "CALLS": str(calls),
                "MW_HOME": str(mw_home),
                "MW_VOLUME": str(mw_volume),
                "MW_LOG": str(log_dir),
                "MW_SITE_SERVER": "https://example.com",
                "MW_SITEMAP_PAUSE_DAYS": "1",
            })
            run_env.update(env or {})
            subprocess.run(["bash", SCRIPT], env=run_env,
                           capture_output=True, text=True, timeout=30)
            return calls.read_text().splitlines() if calls.exists() else []

        def log(self):
            return "".join(p.read_text() for p in log_dir.iterdir())

    return Generator()


def option(call, name):
    for arg in call.split(" "):
        if arg.startswith("--%s=" % name):
            return arg.split("=", 1)[1]
    return None


FARM = [{"id": "de", "url": "example.com/de"},
        {"id": "en", "url": "example.com/en"}]


ROOT_WIKI = [{"id": "main", "url": "example.com"}]


def index_link(call, filename):
    """The <loc> generateSitemap.php writes into the index for filename:
    the server, then --urlpath with a trailing slash, then the file."""
    urlpath = option(call, "urlpath")
    if urlpath and not urlpath.endswith("/"):
        urlpath += "/"
    if not urlpath.startswith("/"):
        urlpath = "/" + urlpath
    return option(call, "server") + urlpath + filename


class TestServer:
    def test_root_wiki(self, generator):
        generator.opt_in("main")
        [call] = generator.run(ROOT_WIKI)
        assert option(call, "server") == "https://example.com"
        assert option(call, "urlpath") == "/public_assets/sitemap"

    def test_path_wiki_server_is_the_host_only(self, generator):
        generator.opt_in("en")
        [call] = generator.run(FARM)
        assert option(call, "server") == "https://example.com"
        assert option(call, "urlpath") == "/en/public_assets/sitemap"

    def test_port_is_kept(self, generator):
        generator.opt_in("en")
        [call] = generator.run([{"id": "en", "url": "example.com:8443/en"}])
        assert option(call, "server") == "https://example.com:8443"
        assert option(call, "urlpath") == "/en/public_assets/sitemap"

    def test_wiki_without_url_uses_mw_site_server(self, generator):
        generator.opt_in("main")
        [call] = generator.run([{"id": "main"}])
        assert option(call, "server") == "https://example.com"
        assert option(call, "urlpath") == "/public_assets/sitemap"

    def test_index_links_point_under_the_wiki(self, generator):
        generator.opt_in("main")
        generator.opt_in("en")
        calls = generator.run(ROOT_WIKI + FARM[1:])
        assert [index_link(c, "sitemap-x-NS_0-0.xml.gz") for c in calls] == [
            "https://example.com/public_assets/sitemap/sitemap-x-NS_0-0.xml.gz",
            "https://example.com/en/public_assets/sitemap/sitemap-x-NS_0-0.xml.gz",
        ]


class TestUrlPath:
    def test_defaults_to_public_assets(self, generator):
        generator.opt_in("main")
        [call] = generator.run(ROOT_WIKI)
        assert option(call, "urlpath") == "/public_assets/sitemap"

    def test_comes_from_mw_sitemap_url_path(self, generator):
        generator.opt_in("en")
        [call] = generator.run(
            FARM, env={"MW_SITEMAP_URL_PATH": "/wiki/sitemap"})
        assert option(call, "urlpath") == "/en/wiki/sitemap"

    def test_files_stay_under_the_wiki_id(self, generator):
        generator.opt_in("en")
        [call] = generator.run(
            FARM, env={"MW_SITEMAP_URL_PATH": "/wiki/sitemap"})
        assert option(call, "fspath").endswith("/public_assets/en/sitemap")


class TestIdentifier:
    def test_defaults_to_the_wiki_id(self, generator):
        generator.opt_in("en")
        [call] = generator.run(FARM)
        assert option(call, "identifier") == "en"

    def test_comes_from_sitemap_identifier(self, generator):
        generator.opt_in("de")
        generator.opt_in("en")
        wikis = [dict(FARM[0]),
                 dict(FARM[1], sitemap_identifier="mediawiki")]
        calls = generator.run(wikis)
        assert [(option(c, "wiki"), option(c, "identifier"))
                for c in calls] == [("de", "de"), ("en", "mediawiki")]

    @pytest.mark.parametrize("identifier", ["../x", "a/b", ".hidden", "a b", ""])
    def test_unsafe_identifier_skips_the_wiki(self, generator, identifier):
        generator.opt_in("de")
        generator.opt_in("en")
        wikis = [dict(FARM[0]),
                 dict(FARM[1], sitemap_identifier=identifier)]
        calls = generator.run(wikis)
        assert [option(c, "wiki") for c in calls] == ["de"]
        assert "Skipping wiki en: sitemap_identifier" in generator.log()

    def test_old_identifier_files_are_removed(self, generator):
        generator.opt_in("en", "sitemap-index-en.xml",
                         "sitemap-en-NS_0-0.xml.gz", "sitemap-en-NS_4-0.xml.gz",
                         "notes.txt")
        generator.run([dict(FARM[1], sitemap_identifier="mediawiki")])
        assert generator.files("en") == [
            "notes.txt",
            "sitemap-index-mediawiki.xml",
            "sitemap-mediawiki-NS_0-0.xml.gz",
        ]

    def test_identifier_sharing_a_prefix_is_removed(self, generator):
        generator.opt_in("en", "sitemap-index-en-old.xml",
                         "sitemap-en-old-NS_0-0.xml.gz")
        generator.run([dict(FARM[1], sitemap_identifier="en")])
        assert generator.files("en") == [
            "sitemap-en-NS_0-0.xml.gz",
            "sitemap-index-en.xml",
        ]

    def test_failed_run_keeps_the_old_files(self, generator):
        generator.opt_in("en", "sitemap-index-en.xml",
                         "sitemap-en-NS_0-0.xml.gz")
        generator.run([dict(FARM[1], sitemap_identifier="mediawiki")],
                      env={"PHP_FAIL": "1"})
        assert generator.files("en") == [
            "sitemap-en-NS_0-0.xml.gz",
            "sitemap-index-en.xml",
        ]


class TestOptIn:
    def test_wikis_without_sitemap_files_are_skipped(self, generator):
        generator.opt_in("en")
        calls = generator.run(FARM)
        assert [option(c, "wiki") for c in calls] == ["en"]

    def test_image_sets_the_url_path_default(self):
        with open(os.path.join(REPO_ROOT, "Dockerfile")) as f:
            assert "MW_SITEMAP_URL_PATH=/public_assets/sitemap" in f.read()
