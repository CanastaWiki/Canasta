"""robots.php and sitemap.php build their output on every request, so a
caching proxy in front of them must not keep a copy that goes stale when a
sitemap is generated. Canasta's Varnish config caches a bare no-cache
response, so the headers must carry max-age=0. They are served through php's built-in web server so
the response headers can be inspected."""

import json
import os
import shutil
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest


pytestmark = pytest.mark.skipif(
    shutil.which("php") is None,
    reason="php is required to serve robots.php and sitemap.php",
)

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CONFIGS = os.path.join(REPO_ROOT, "_sources", "configs")

# wikis.yaml is written as JSON, which is valid YAML; the shim stands in
# for the yaml extension where the local php lacks it.
ROUTER = """<?php
if ( !function_exists( 'yaml_parse_file' ) ) {
	function yaml_parse_file( $f ) { return json_decode( file_get_contents( $f ), true ); }
}
$script = getenv( 'CONFIGS_DIR' ) . '/' . basename( parse_url( $_SERVER['REQUEST_URI'], PHP_URL_PATH ) );
chdir( dirname( $script ) );
require $script;
"""


def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
def server(tmp_path):
    mw_volume = tmp_path / "mediawiki"
    (mw_volume / "config").mkdir(parents=True)
    (mw_volume / "config" / "wikis.yaml").write_text(
        json.dumps({"wikis": [{"id": "main", "url": "127.0.0.1"}]}))
    router = tmp_path / "router.php"
    router.write_text(ROUTER)
    port = _free_port()
    env = os.environ.copy()
    env.pop("ROBOTS_DISALLOWED", None)
    env.update({"MW_VOLUME": str(mw_volume), "CONFIGS_DIR": CONFIGS})
    proc = subprocess.Popen(
        ["php", "-S", "127.0.0.1:%d" % port, str(router)],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = "http://127.0.0.1:%d" % port
    deadline = time.time() + 10
    while True:
        try:
            socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
            break
        except OSError:
            if time.time() > deadline:
                proc.kill()
                pytest.fail("php built-in server did not start")
            time.sleep(0.05)
    yield base, mw_volume
    proc.kill()
    proc.wait()


def _fetch(url):
    try:
        response = urllib.request.urlopen(url)
    except urllib.error.HTTPError as error:
        response = error
    return response.status, response.headers.get("Cache-Control")


def test_robots_is_not_cached(server):
    base, _ = server
    assert _fetch(base + "/robots.php") == (200, "no-cache, max-age=0")


def test_sitemap_is_not_cached(server):
    base, mw_volume = server
    directory = mw_volume / "public_assets" / "main" / "sitemap"
    directory.mkdir(parents=True)
    (directory / "sitemap-index-main.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        "<sitemap><loc>http://127.0.0.1/s.xml.gz</loc></sitemap>"
        "</sitemapindex>\n")
    assert _fetch(base + "/sitemap.php") == (200, "no-cache, max-age=0")


def test_missing_sitemap_is_not_cached(server):
    base, _ = server
    assert _fetch(base + "/sitemap.php") == (404, "no-cache, max-age=0")


def test_no_bare_no_cache_headers():
    """Canasta's Varnish caches a response whose Cache-Control is a bare
    `no-cache`, so every page the image generates outside MediaWiki must
    also send max-age=0."""
    import pathlib
    import re
    root = pathlib.Path(__file__).resolve().parent.parent / "_sources"
    offenders = []
    for path in root.rglob("*.php"):
        for n, line in enumerate(path.read_text().splitlines(), 1):
            m = re.search(r"Cache-Control:\s*([^'\"]*)", line)
            if m and "no-cache" in m.group(1) and "max-age=0" not in m.group(1):
                offenders.append(f"{path.relative_to(root)}:{n}")
    assert not offenders, offenders
