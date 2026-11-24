"""Tests for _sources/canasta/CanastaFarm404.php.

The wiki directory resolves each card's logo from
public_assets/<wiki_id>/logo.<ext>, which the web server grants
anonymously, and only falls back to the client-side siteinfo lookup when
a wiki has no such file. These tests render the real page through php.
"""

import shutil

import pytest


pytestmark = pytest.mark.skipif(
    shutil.which("php") is None,
    reason="php is required to render CanastaFarm404.php",
)


class TestServerSideLogoResolution:
    """Private wikis get a logo without an anonymous API call (#230)."""

    def test_logo_file_becomes_a_src(self, farm_page):
        html = farm_page(
            [{"id": "main", "url": "example.com", "name": "Main"}],
            assets={"main": ["logo.png"]},
        )
        assert 'src="https://example.com/public_assets/logo.png"' in html
        assert "data-api=" not in html

    def test_subdir_wiki_logo_url_keeps_the_path(self, farm_page):
        html = farm_page(
            [{"id": "docs", "url": "example.com/docs", "name": "Docs"}],
            assets={"docs": ["logo.svg"]},
        )
        assert 'src="https://example.com/docs/public_assets/logo.svg"' in html

    def test_wiki_without_a_logo_file_keeps_the_api_fallback(self, farm_page):
        html = farm_page([{"id": "main", "url": "example.com", "name": "Main"}])
        assert 'data-api="https://example.com/w/api.php"' in html
        assert "src=" not in html

    def test_only_the_wiki_without_a_logo_falls_back(self, farm_page):
        html = farm_page(
            [
                {"id": "main", "url": "example.com", "name": "Main"},
                {"id": "docs", "url": "example.com/docs", "name": "Docs"},
            ],
            assets={"main": ["logo.png"]},
        )
        assert 'src="https://example.com/public_assets/logo.png"' in html
        assert 'data-api="https://example.com/docs/w/api.php"' in html

    def test_svg_wins_over_png(self, farm_page):
        html = farm_page(
            [{"id": "main", "url": "example.com"}],
            assets={"main": ["logo.png", "logo.svg"]},
        )
        assert 'src="https://example.com/public_assets/logo.svg"' in html
        assert "logo.png" not in html

    def test_capitalized_name_and_extension_are_matched(self, farm_page):
        html = farm_page(
            [{"id": "main", "url": "example.com"}],
            assets={"main": ["Logo.PNG"]},
        )
        assert 'src="https://example.com/public_assets/Logo.PNG"' in html

    def test_unrelated_asset_files_are_ignored(self, farm_page):
        html = farm_page(
            [{"id": "main", "url": "example.com"}],
            assets={"main": ["favicon.ico", "logo-wide.png", "mylogo.png"]},
        )
        assert "src=" not in html
        assert 'data-api="https://example.com/w/api.php"' in html

    def test_logos_also_render_on_the_404_page(self, farm_page):
        html = farm_page(
            [{"id": "main", "url": "example.com"}],
            assets={"main": ["logo.png"]},
            directory_only=False,
        )
        assert "404" in html
        assert 'src="https://example.com/public_assets/logo.png"' in html

    def test_http_scheme_is_carried_into_the_logo_url(self, farm_page):
        html = farm_page(
            [{"id": "main", "url": "localhost:8080"}],
            assets={"main": ["logo.png"]},
            site_server="http://localhost:8080",
        )
        assert 'src="http://localhost:8080/public_assets/logo.png"' in html


class TestLogoLookupSafety:
    """The wiki ID is used as a path segment, and wikis.yaml is hand-editable."""

    def test_wiki_id_with_a_traversal_segment_is_refused(self, farm_page):
        (farm_page.mw_volume / "public_assets" / "victim").mkdir(parents=True)
        (farm_page.mw_volume / "public_assets" / "victim" / "logo.png").write_bytes(b"")
        html = farm_page([{"id": "../public_assets/victim", "url": "example.com"}])
        assert "src=" not in html

    def test_wiki_id_with_a_leading_dot_is_refused(self, farm_page):
        html = farm_page(
            [{"id": ".hidden", "url": "example.com"}],
            assets={".hidden": ["logo.png"]},
        )
        assert "src=" not in html

    def test_missing_wiki_id_falls_back_without_error(self, farm_page):
        html = farm_page([{"url": "example.com", "name": "Main"}])
        assert 'data-api="https://example.com/w/api.php"' in html


class TestDirectoryMarkup:
    """The stylesheet must not hide a logo the server already resolved."""

    def test_only_the_api_placeholder_starts_hidden(self, farm_page):
        html = farm_page([{"id": "main", "url": "example.com"}])
        assert ".wiki-card .logo img[data-api]{display:none}" in html
        assert ".wiki-card .logo img{max-width:80px;max-height:80px}" in html

    def test_wiki_name_and_link_still_render(self, farm_page):
        html = farm_page(
            [{"id": "main", "url": "example.com", "name": "Main Wiki"}],
            assets={"main": ["logo.png"]},
        )
        assert '<a href="https://example.com">' in html
        assert "Main Wiki" in html
