"""Shared fixtures for CanastaBase tests."""

import json
import os
import subprocess

import pytest


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPT = os.path.join(REPO_ROOT, "_sources", "scripts", "config-subdir-wikis.sh")


@pytest.fixture
def workspace(tmp_path):
    """Per-test temp dir tree mirroring the canasta-image layout that
    config-subdir-wikis.sh interacts with:

        <workspace>/
            mediawiki/
                config/
                    wikis.yaml          <- WIKIS_YAML
            www/                         <- WWW_ROOT
                .htaccess               <- seeded with the production .htaccess
                w/                       <- MW_HOME
            apache2.conf                 <- APACHE_CONF (initially empty)
    """
    mw_volume = tmp_path / "mediawiki"
    mw_config = mw_volume / "config"
    mw_config.mkdir(parents=True)

    www_root = tmp_path / "www"
    www_root.mkdir()
    mw_home = www_root / "w"
    mw_home.mkdir()

    # Seed a sample .htaccess so the subdir-wiki branch has something
    # to rewrite. Mirrors the real _sources/configs/.htaccess shape.
    (www_root / ".htaccess").write_text(
        "RewriteEngine On\n"
        "RewriteRule ^/?w/rest.php/ - [L]\n"
        "RewriteRule ^/?w/img_auth.php/ - [L]\n"
        "RewriteRule ^/*$ %{DOCUMENT_ROOT}/w/index.php [L]\n"
        "RewriteRule ^/?[^/]+/w/(load|api|rest|index|img_auth)\\.php(.*)$"
        " %{DOCUMENT_ROOT}/w/$1.php$2 [L,QSA]\n"
        "RewriteCond %{DOCUMENT_ROOT}%{REQUEST_URI} !-f\n"
        "RewriteCond %{DOCUMENT_ROOT}%{REQUEST_URI} !-d\n"
        "RewriteRule ^(.*)$ %{DOCUMENT_ROOT}/w/index.php [L]\n"
    )

    apache_conf = tmp_path / "apache2.conf"
    apache_conf.touch()

    return {
        "tmp_path": tmp_path,
        "mw_volume": mw_volume,
        "wikis_yaml": mw_config / "wikis.yaml",
        "www_root": www_root,
        "mw_home": mw_home,
        "apache_conf": apache_conf,
    }


def write_wikis(wikis_yaml, wikis, indent=0):
    """Write a wikis list to wikis.yaml.

    `wikis` is a list of dicts with at least `id` and `url` keys.

    `indent` is the number of spaces before each "- id:" list item.
    Both the flat block style (indent=0, what the CLI's yaml.dump emits)
    and the nested style (indent=2, common hand-edited / library output)
    are valid YAML and occur in production, so tests exercise both.
    """
    pad = " " * indent
    lines = ["wikis:"]
    for w in wikis:
        lines.append("%s- id: %s" % (pad, w["id"]))
        lines.append("%s  url: %s" % (pad, w["url"]))
        if "name" in w:
            lines.append("%s  name: %s" % (pad, w["name"]))
    wikis_yaml.write_text("\n".join(lines) + "\n")


def run_script(workspace):
    """Run config-subdir-wikis.sh against the workspace fixture and
    return the resulting (apache_conf_text, completed_process)."""
    env = os.environ.copy()
    env.update({
        "WIKIS_YAML": str(workspace["wikis_yaml"]),
        "APACHE_CONF": str(workspace["apache_conf"]),
        "WWW_ROOT": str(workspace["www_root"]),
        "MW_HOME": str(workspace["mw_home"]),
        "MW_VOLUME": str(workspace["mw_volume"]),
    })
    result = subprocess.run(
        ["bash", SCRIPT],
        env=env,
        capture_output=True,
        text=True,
    )
    return workspace["apache_conf"].read_text(), result


@pytest.fixture
def script_runner(workspace):
    """Convenience: returns a callable that writes a wikis.yaml and runs
    the script in one step. The callable returns
    (apache_conf_text, CompletedProcess) so tests can assert on both."""
    def _run(wikis, indent=0):
        write_wikis(workspace["wikis_yaml"], wikis, indent=indent)
        return run_script(workspace)
    _run.workspace = workspace
    return _run


FARM_404 = os.path.join(REPO_ROOT, "_sources", "canasta", "CanastaFarm404.php")

# CanastaFarm404.php is normally required by FarmConfigLoader.php with
# $wikiConfigurations / $urlComponents / $directoryOnly already in scope.
# This harness reproduces that calling convention outside MediaWiki.
FARM_404_HARNESS = """<?php
$wikiConfigurations = json_decode( file_get_contents( $argv[1] ), true );
$urlComponents = [ 'path' => $argv[2] ];
$path = '';
$directoryOnly = $argv[3] === '1';
require getenv( 'FARM_404_PHP' );
"""


@pytest.fixture
def farm_page(tmp_path):
    """Render CanastaFarm404.php through the real php binary and return
    the HTML.

    The callable takes the wikis list that would come from wikis.yaml,
    an optional {wiki_id: [filenames]} map of files to create under
    public_assets/<wiki_id>/, and the directory/404 mode flag.
    """
    mw_volume = tmp_path / "farm-mediawiki"
    (mw_volume / "public_assets").mkdir(parents=True)
    harness = tmp_path / "render_farm_404.php"
    harness.write_text(FARM_404_HARNESS)

    def _render(wikis, assets=None, directory_only=True, site_server="https://example.com"):
        for wiki_id, filenames in (assets or {}).items():
            asset_dir = mw_volume / "public_assets" / wiki_id
            asset_dir.mkdir(parents=True, exist_ok=True)
            for filename in filenames:
                (asset_dir / filename).write_bytes(b"")
        config = tmp_path / "wikis.json"
        config.write_text(json.dumps({"wikis": wikis}))
        env = os.environ.copy()
        env.update({
            "FARM_404_PHP": FARM_404,
            "MW_VOLUME": str(mw_volume),
            "MW_SITE_SERVER": site_server,
            "CANASTA_ENABLE_WIKI_DIRECTORY": "true",
        })
        result = subprocess.run(
            ["php", str(harness), str(config), "/missing",
             "1" if directory_only else "0"],
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, result.stderr
        assert result.stderr == "", result.stderr
        return result.stdout

    _render.mw_volume = mw_volume
    return _render
