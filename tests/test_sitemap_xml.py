"""Tests for the /sitemap.xml combined index and the robots.txt Sitemap line.

sitemap.php merges the sitemap index of every wiki on the requesting host
that has generated sitemaps; robots.php advertises /sitemap.xml once when
there is anything to serve. Both run through the real php binary.
"""

import json
import os
import re
import shutil
import subprocess

import pytest


pytestmark = pytest.mark.skipif(
    shutil.which("php") is None,
    reason="php is required to run sitemap.php and robots.php",
)

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CONFIGS = os.path.join(REPO_ROOT, "_sources", "configs")

# wikis.yaml is written as JSON, which is valid YAML; the shim stands in
# for the yaml extension where the local php lacks it.
HARNESS = """<?php
if ( !function_exists( 'yaml_parse_file' ) ) {
	function yaml_parse_file( $f ) { return json_decode( file_get_contents( $f ), true ); }
}
$_SERVER['HTTP_HOST'] = $argv[2];
chdir( dirname( $argv[1] ) );
require $argv[1];
"""

INDEX = """<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
{entries}
</sitemapindex>
"""

ENTRY = """\t<sitemap>
\t\t<loc>{loc}</loc>
\t\t<lastmod>2026-10-09T00:00:00Z</lastmod>
\t</sitemap>"""


@pytest.fixture
def site(tmp_path):
    mw_volume = tmp_path / "mediawiki"
    (mw_volume / "config").mkdir(parents=True)
    harness = tmp_path / "harness.php"
    harness.write_text(HARNESS)

    class Site:
        def wikis(self, wikis):
            (mw_volume / "config" / "wikis.yaml").write_text(
                json.dumps({"wikis": wikis}))

        def sitemap(self, wiki_id, base, identifier=None, namespaces=(0,)):
            directory = mw_volume / "public_assets" / wiki_id / "sitemap"
            directory.mkdir(parents=True, exist_ok=True)
            name = identifier or wiki_id
            entries = "\n".join(
                ENTRY.format(loc="%s/public_assets/sitemap/sitemap-%s-NS_%d-0.xml.gz"
                             % (base, name, ns))
                for ns in namespaces)
            (directory / ("sitemap-index-%s.xml" % name)).write_text(
                INDEX.format(entries=entries))

        def request(self, script, host, env=None):
            run_env = os.environ.copy()
            run_env.pop("ROBOTS_DISALLOWED", None)
            run_env.update({"MW_VOLUME": str(mw_volume),
                            "MW_SITE_SERVER": "https://example.com"})
            run_env.update(env or {})
            result = subprocess.run(
                ["php", str(harness), os.path.join(CONFIGS, script), host],
                env=run_env, capture_output=True, text=True)
            assert result.returncode == 0, result.stderr
            return result.stdout

        def locs(self, host):
            return re.findall(r"<loc>([^<]+)</loc>",
                              self.request("sitemap.php", host))

    return Site()


class TestCombinedIndex:
    def test_single_wiki(self, site):
        site.wikis([{"id": "main", "url": "example.com"}])
        site.sitemap("main", "https://example.com", namespaces=(0, 1))
        assert site.locs("example.com") == [
            "https://example.com/public_assets/sitemap/sitemap-main-NS_0-0.xml.gz",
            "https://example.com/public_assets/sitemap/sitemap-main-NS_1-0.xml.gz",
        ]

    def test_path_based_wikis_with_a_root_wiki(self, site):
        site.wikis([{"id": "main", "url": "example.com"},
                    {"id": "docs", "url": "example.com/docs"}])
        site.sitemap("main", "https://example.com")
        site.sitemap("docs", "https://example.com/docs")
        assert site.locs("example.com") == [
            "https://example.com/public_assets/sitemap/sitemap-main-NS_0-0.xml.gz",
            "https://example.com/docs/public_assets/sitemap/sitemap-docs-NS_0-0.xml.gz",
        ]

    def test_path_based_wikis_without_a_root_wiki(self, site):
        site.wikis([{"id": "a", "url": "example.com/a"},
                    {"id": "b", "url": "example.com/b"}])
        site.sitemap("a", "https://example.com/a")
        site.sitemap("b", "https://example.com/b")
        assert site.locs("example.com") == [
            "https://example.com/a/public_assets/sitemap/sitemap-a-NS_0-0.xml.gz",
            "https://example.com/b/public_assets/sitemap/sitemap-b-NS_0-0.xml.gz",
        ]

    def test_domain_based_wikis_each_get_their_own(self, site):
        site.wikis([{"id": "a", "url": "a.example.com"},
                    {"id": "b", "url": "b.example.com"}])
        site.sitemap("a", "https://a.example.com")
        site.sitemap("b", "https://b.example.com")
        assert site.locs("a.example.com") == [
            "https://a.example.com/public_assets/sitemap/sitemap-a-NS_0-0.xml.gz"]
        assert site.locs("b.example.com") == [
            "https://b.example.com/public_assets/sitemap/sitemap-b-NS_0-0.xml.gz"]

    @pytest.mark.parametrize("url, host", [
        ("localhost:8443", "localhost:8443"),
        ("localhost:8443", "localhost"),
        ("localhost", "localhost:8443"),
    ])
    def test_ports_are_matched_either_way(self, site, url, host):
        site.wikis([{"id": "main", "url": url}])
        site.sitemap("main", "https://%s" % url)
        assert len(site.locs(host)) == 1

    def test_index_named_after_the_database_is_found(self, site):
        site.wikis([{"id": "main", "url": "example.com"}])
        site.sitemap("main", "https://example.com", identifier="maindb")
        assert site.locs("example.com") == [
            "https://example.com/public_assets/sitemap/sitemap-maindb-NS_0-0.xml.gz"]

    def test_wikis_without_sitemaps_are_left_out(self, site):
        site.wikis([{"id": "main", "url": "example.com"},
                    {"id": "docs", "url": "example.com/docs"}])
        site.sitemap("docs", "https://example.com/docs")
        assert site.locs("example.com") == [
            "https://example.com/docs/public_assets/sitemap/sitemap-docs-NS_0-0.xml.gz"]

    def test_output_is_a_sitemap_index(self, site):
        site.wikis([{"id": "main", "url": "example.com"}])
        site.sitemap("main", "https://example.com")
        body = site.request("sitemap.php", "example.com")
        assert body.startswith('<?xml version="1.0" encoding="UTF-8"?>')
        assert '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' in body
        assert "<lastmod>2026-10-09T00:00:00Z</lastmod>" in body

    @pytest.mark.parametrize("host", ["example.com", "other.example.com"])
    def test_nothing_to_serve(self, site, host):
        site.wikis([{"id": "main", "url": "example.com"}])
        body = site.request("sitemap.php", host)
        assert "<sitemapindex" not in body
        assert "No sitemap" in body

    def test_wiki_ids_cannot_escape_public_assets(self, site):
        site.wikis([{"id": "../outside", "url": "example.com"}])
        assert site.locs("example.com") == []


class TestRobots:
    def test_advertises_sitemap_xml_once(self, site):
        site.wikis([{"id": "main", "url": "example.com"},
                    {"id": "docs", "url": "example.com/docs"}])
        site.sitemap("main", "https://example.com")
        site.sitemap("docs", "https://example.com/docs")
        body = site.request("robots.php", "example.com")
        assert re.findall(r"(?m)^Sitemap: .*$", body) == [
            "Sitemap: https://example.com/sitemap.xml"]

    def test_no_sitemap_line_without_sitemaps(self, site):
        site.wikis([{"id": "main", "url": "example.com"}])
        body = site.request("robots.php", "example.com")
        assert "Sitemap:" not in body
        assert "User-agent: *" in body

    def test_other_hosts_are_not_advertised(self, site):
        site.wikis([{"id": "a", "url": "a.example.com"},
                    {"id": "b", "url": "b.example.com"}])
        site.sitemap("a", "https://a.example.com")
        assert "Sitemap:" not in site.request("robots.php", "b.example.com")

    def test_disallowed_site_has_no_sitemap_line(self, site):
        site.wikis([{"id": "main", "url": "example.com"}])
        site.sitemap("main", "https://example.com")
        body = site.request("robots.php", "example.com",
                            env={"ROBOTS_DISALLOWED": "true"})
        assert "Sitemap:" not in body
        assert "Disallow: /" in body


class TestRewriteRules:
    def _rules(self):
        with open(os.path.join(CONFIGS, ".htaccess")) as f:
            return [line.strip() for line in f if line.startswith("RewriteRule")]

    def test_robots_and_sitemap_are_case_sensitive(self):
        rules = self._rules()
        assert "RewriteRule ^/?robots\\.txt$ robots.php [L]" in rules
        assert "RewriteRule ^/?sitemap\\.xml$ sitemap.php [L]" in rules

    def test_they_come_before_the_short_url_catch_all(self):
        rules = self._rules()
        catch_all = rules.index("RewriteRule ^(.*)$ %{DOCUMENT_ROOT}/w/index.php [L]")
        assert rules.index("RewriteRule ^/?sitemap\\.xml$ sitemap.php [L]") < catch_all
        assert rules.index("RewriteRule ^/?robots\\.txt$ robots.php [L]") < catch_all

    def test_image_ships_the_scripts(self):
        with open(os.path.join(REPO_ROOT, "Dockerfile")) as f:
            dockerfile = f.read()
        for name in ("robots.php", "sitemap.php", "canasta-sitemaps.php"):
            assert "_sources/configs/%s" % name in dockerfile
