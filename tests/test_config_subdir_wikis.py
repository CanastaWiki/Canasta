"""Tests for _sources/scripts/config-subdir-wikis.sh.

The script reads wikis.yaml at container startup and emits Apache
config (per-wiki public_assets rewrites + subdir-wiki img_auth.php
aliases) plus filesystem side effects (symlinks, rewritten .htaccess).
These tests run the real script in a temp workspace via subprocess
and assert on the resulting files.
"""

import pytest


class TestApacheRewriteGeneration:
    """The new public_assets rewrite logic added for #144."""

    def test_root_wiki_emits_root_rewrite(self, script_runner):
        cfg, result = script_runner([{"id": "main", "url": "localhost"}])
        assert result.returncode == 0, result.stderr
        assert "RewriteCond %{HTTP_HOST} ^localhost$ [NC]" in cfg
        assert (
            "RewriteRule ^/public_assets/(.*)$ "
            "/mediawiki/public_assets/main/$1 [L]"
        ) in cfg

    def test_subdir_wiki_emits_subdir_rewrite(self, script_runner):
        cfg, result = script_runner(
            [{"id": "docs", "url": "example.com/docs"}],
        )
        assert result.returncode == 0, result.stderr
        assert "RewriteCond %{HTTP_HOST} ^example\\.com$ [NC]" in cfg
        assert (
            "RewriteRule ^/docs/public_assets/(.*)$ "
            "/mediawiki/public_assets/docs/$1 [L]"
        ) in cfg

    def test_dots_in_hostname_are_regex_escaped(self, script_runner):
        cfg, _ = script_runner(
            [{"id": "main", "url": "wiki.example.com"}],
        )
        # Each dot is preceded by a backslash so the RewriteCond doesn't
        # accept "wikiXexampleXcom" by accident.
        assert "wiki\\.example\\.com" in cfg
        assert "wiki.example.com" not in cfg.replace("wiki\\.example\\.com", "")

    def test_port_in_hostname_preserved(self, script_runner):
        cfg, _ = script_runner(
            [{"id": "main", "url": "localhost:8443"}],
        )
        assert "RewriteCond %{HTTP_HOST} ^localhost:8443$ [NC]" in cfg

    def test_port_and_subdir_combination(self, script_runner):
        cfg, _ = script_runner(
            [{"id": "docs", "url": "localhost:8443/docs"}],
        )
        assert "RewriteCond %{HTTP_HOST} ^localhost:8443$ [NC]" in cfg
        assert (
            "RewriteRule ^/docs/public_assets/(.*)$ "
            "/mediawiki/public_assets/docs/$1 [L]"
        ) in cfg

    def test_multi_host_farm_each_wiki_has_own_host_condition(
        self, script_runner,
    ):
        cfg, _ = script_runner([
            {"id": "alpha", "url": "alpha.example.com"},
            {"id": "beta", "url": "beta.example.com"},
        ])
        # Each wiki gets its own RewriteCond+RewriteRule pair
        assert "^alpha\\.example\\.com$" in cfg
        assert "^beta\\.example\\.com$" in cfg
        assert "/mediawiki/public_assets/alpha/" in cfg
        assert "/mediawiki/public_assets/beta/" in cfg

    def test_each_wiki_gets_exactly_one_rewrite_block(self, script_runner):
        cfg, _ = script_runner([
            {"id": "main", "url": "localhost"},
            {"id": "docs", "url": "localhost/docs"},
        ])
        assert cfg.count("RewriteRule ^/public_assets/(.*)$") == 1
        assert cfg.count("RewriteRule ^/docs/public_assets/(.*)$") == 1

    def test_rerun_does_not_duplicate_directives(self, script_runner):
        # A container restart reuses the same apache2.conf; running the
        # script a second time must replace its block, not append a copy.
        wikis = [
            {"id": "main", "url": "localhost"},
            {"id": "docs", "url": "localhost/docs"},
        ]
        script_runner(wikis)
        cfg, result = script_runner(wikis)
        assert result.returncode == 0, result.stderr
        assert cfg.count("RewriteRule ^/public_assets/(.*)$") == 1
        assert cfg.count("RewriteRule ^/docs/public_assets/(.*)$") == 1
        assert cfg.count("Alias /docs/w/images/ ") == 1
        assert cfg.count("# BEGIN canasta-subdir-wikis") == 1


class TestSubdirWikiPlumbing:
    """The pre-#144 logic for subdir wikis (preserved by the rewrite)."""

    def test_subdir_wiki_creates_symlink(self, script_runner):
        # The script does:
        #   mkdir -p $WWW_ROOT/docs
        #   ln -sf $MW_HOME $WWW_ROOT/docs
        # When the target is an existing directory, `ln -sf` creates
        # the symlink INSIDE the directory using the source's basename.
        # So docs/w (== basename of $MW_HOME) is the symlink, and it
        # points back at $MW_HOME. URLs like /docs/w/index.php then
        # resolve to the same MediaWiki entry point as /w/index.php.
        _, result = script_runner(
            [{"id": "docs", "url": "example.com/docs"}],
        )
        assert result.returncode == 0, result.stderr
        ws = script_runner.workspace
        assert (ws["www_root"] / "docs").is_dir()
        link = ws["www_root"] / "docs" / ws["mw_home"].name
        assert link.is_symlink(), (
            "expected symlink at %s, got: %s"
            % (link, sorted((ws["www_root"] / "docs").iterdir()))
        )
        assert link.resolve() == ws["mw_home"].resolve()

    def test_subdir_wiki_writes_rewritten_htaccess(self, script_runner):
        _, _ = script_runner([{"id": "docs", "url": "example.com/docs"}])
        ws = script_runner.workspace
        docs_htaccess = (ws["www_root"] / "docs" / ".htaccess").read_text()
        # The img_auth.php and rest.php passthrough rules must NOT be
        # prefixed with the wiki path. Inside the subdirectory, Apache
        # has already stripped the prefix before evaluating .htaccess.
        assert "w/img_auth.php/" in docs_htaccess
        assert "docs/w/img_auth.php/" not in docs_htaccess
        assert "w/rest.php/" in docs_htaccess
        assert "docs/w/rest.php/" not in docs_htaccess
        # Both use [END] to prevent catch-all re-entry
        assert "rest.php/ - [END]" in docs_htaccess
        assert "img_auth.php/ - [END]" in docs_htaccess
        # The catch-all index.php rules DO need the prefix
        assert "docs/w/index.php" in docs_htaccess

    def test_subdir_wiki_emits_img_auth_aliases(self, script_runner):
        cfg, _ = script_runner([{"id": "docs", "url": "example.com/docs"}])
        assert (
            "Alias /docs/w/images/ /var/www/mediawiki/w/img_auth.php/" in cfg
        )
        assert (
            "Alias /docs/w/images /var/www/mediawiki/w/img_auth.php" in cfg
        )

    def test_root_wiki_does_not_create_symlink(self, script_runner):
        _, result = script_runner([{"id": "main", "url": "localhost"}])
        assert result.returncode == 0, result.stderr
        ws = script_runner.workspace
        # Only the seeded www_root + .htaccess should exist; no extra
        # subdir entries (other than the existing 'w' MW_HOME).
        names = sorted(p.name for p in ws["www_root"].iterdir())
        assert names == [".htaccess", "w"]

    def test_root_wiki_does_not_emit_img_auth_alias(self, script_runner):
        cfg, _ = script_runner([{"id": "main", "url": "localhost"}])
        # The root img_auth.php alias is set up at build time in the
        # Dockerfile; this script only handles subdir wikis.
        assert "/w/images/" not in cfg

    def test_same_subdir_under_two_hosts_processed_once(self, script_runner):
        # If the same subdir 'docs' appears under two different hosts in
        # a multi-host farm, the symlink/.htaccess work should run once,
        # but each wiki should still get its own public_assets rewrite.
        cfg, _ = script_runner([
            {"id": "alpha_docs", "url": "alpha.example.com/docs"},
            {"id": "beta_docs", "url": "beta.example.com/docs"},
        ])
        # Both wikis get their own host-conditional rewrite
        assert "/mediawiki/public_assets/alpha_docs/" in cfg
        assert "/mediawiki/public_assets/beta_docs/" in cfg
        # But the img_auth.php Alias is only emitted once (Apache would
        # warn on duplicate Aliases, and the routing is host-agnostic
        # for img_auth.php since the PHP figures out the wiki from
        # MediaWiki context anyway).
        assert (
            cfg.count("Alias /docs/w/images /var/www/mediawiki/w/img_auth.php")
            == 1
        )


class TestEdgeCases:

    def test_empty_wikis_yaml_does_not_error(self, script_runner):
        _, result = script_runner([])
        assert result.returncode == 0, result.stderr

    def test_existing_apache_conf_content_is_preserved(self, script_runner):
        ws = script_runner.workspace
        ws["apache_conf"].write_text("# pre-existing content\nServerName foo\n")
        cfg, _ = script_runner([{"id": "main", "url": "localhost"}])
        assert "# pre-existing content" in cfg
        assert "ServerName foo" in cfg
        assert "/mediawiki/public_assets/main/" in cfg

    def test_wiki_id_with_underscores(self, script_runner):
        cfg, _ = script_runner(
            [{"id": "my_wiki_id", "url": "localhost"}],
        )
        assert "/mediawiki/public_assets/my_wiki_id/" in cfg


class TestIndentationTolerance:
    """wikis.yaml appears in two valid YAML shapes in production: flat
    block style (list items at column 0, what the CLI's yaml.dump emits)
    and nested style (list items indented under 'wikis:', common from
    hand edits or other serializers). The parser must handle both, or an
    indented file silently yields no rewrite rules and every wiki's
    /public_assets/ (logos, favicons) 404s. Regression guard for the
    indented case, which shipped broken.
    """

    @pytest.mark.parametrize("indent", [0, 2, 4])
    def test_root_wiki_rewrite_generated_regardless_of_indent(
        self, script_runner, indent,
    ):
        cfg, result = script_runner(
            [{"id": "main", "url": "canasta.wiki"}], indent=indent,
        )
        assert result.returncode == 0, result.stderr
        assert "RewriteCond %{HTTP_HOST} ^canasta\\.wiki$ [NC]" in cfg
        assert (
            "RewriteRule ^/public_assets/(.*)$ "
            "/mediawiki/public_assets/main/$1 [L]"
        ) in cfg

    @pytest.mark.parametrize("indent", [0, 2, 4])
    def test_multi_host_farm_all_wikis_parsed_when_indented(
        self, script_runner, indent,
    ):
        cfg, _ = script_runner([
            {"id": "canasta", "url": "canasta.wiki", "name": "Canasta Wiki"},
            {"id": "demo", "url": "demo.canasta.wiki", "name": "demo"},
        ], indent=indent)
        assert "/mediawiki/public_assets/canasta/" in cfg
        assert "/mediawiki/public_assets/demo/" in cfg
