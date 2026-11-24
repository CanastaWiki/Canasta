"""Tests for verify-composer-deps.php — the build-time guardrail that fails
the image build when a bundled extension's Composer dependency did not land in
vendor/ (issue #186).

Motivating incident: MediaWiki 1.43.9 required wikimedia/css-sanitizer 6.2.1
while the bundled TemplateStyles pin required ^5.x, so the unified
`composer update` failed resolution and installed none of the merged extension
dependencies — yet the image shipped, surfacing as a runtime
`Class "Elastica\\Client" not found` fatal. This self-test makes that a red
build instead of a broken release.
"""

import json
import os
import shutil
import subprocess

import pytest


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VERIFY = os.path.join(REPO_ROOT, "_sources", "scripts", "verify-composer-deps.php")

pytestmark = pytest.mark.skipif(
    shutil.which("php") is None, reason="php not available"
)


def _write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))


def _setup_mw_home(tmp_path, includes, ext_requires, installed):
    """Build a fake MW_HOME with composer.local.json, extension composer.json
    files, and vendor/composer/installed.json.

    `installed` is a list of package dicts (each at least {"name": ...},
    optionally with "provide"/"replace").
    """
    mw_home = tmp_path / "w"
    mw_home.mkdir()
    _write_json(mw_home / "composer.local.json",
                {"extra": {"merge-plugin": {"include": list(includes)}}})
    for rel, require in ext_requires.items():
        _write_json(mw_home / rel, {"require": require})
    _write_json(mw_home / "vendor" / "composer" / "installed.json",
                {"packages": installed})
    return mw_home


def _run(mw_home):
    return subprocess.run(["php", VERIFY, str(mw_home)],
                          capture_output=True, text=True)


def test_fails_when_required_package_missing(tmp_path):
    mw_home = _setup_mw_home(
        tmp_path,
        includes=["extensions/Elastica/composer.json"],
        ext_requires={"extensions/Elastica/composer.json":
                      {"ruflin/elastica": "^7.0", "php": ">=8.1"}},
        installed=[{"name": "some/other-package"}],
    )
    result = _run(mw_home)
    assert result.returncode == 1
    assert "ruflin/elastica" in result.stderr
    assert "Elastica" in result.stderr


def test_passes_when_satisfied(tmp_path):
    mw_home = _setup_mw_home(
        tmp_path,
        includes=["extensions/Elastica/composer.json"],
        ext_requires={"extensions/Elastica/composer.json":
                      {"ruflin/elastica": "^7.0", "php": ">=8.1",
                       "ext-curl": "*"}},
        installed=[{"name": "ruflin/elastica"}],
    )
    result = _run(mw_home)
    assert result.returncode == 0
    assert result.stderr.strip() == ""


def test_accepts_provided_virtual_package(tmp_path):
    """A virtual package satisfied via another package's 'provide' must not
    read as missing."""
    mw_home = _setup_mw_home(
        tmp_path,
        includes=["extensions/Foo/composer.json"],
        ext_requires={"extensions/Foo/composer.json": {"psr/log": "^3.0"}},
        installed=[{"name": "monolog/monolog", "provide": {"psr/log": "*"}}],
    )
    result = _run(mw_home)
    assert result.returncode == 0
    assert result.stderr.strip() == ""


def test_reports_every_missing_package(tmp_path):
    mw_home = _setup_mw_home(
        tmp_path,
        includes=["extensions/Elastica/composer.json",
                  "extensions/SemanticMediaWiki/composer.json"],
        ext_requires={
            "extensions/Elastica/composer.json": {"ruflin/elastica": "^7.0"},
            "extensions/SemanticMediaWiki/composer.json":
                {"onoi/message-reporter": "^1.0", "data-values/geo": "*"},
        },
        installed=[{"name": "data-values/geo"}],
    )
    result = _run(mw_home)
    assert result.returncode == 1
    assert "ruflin/elastica" in result.stderr
    assert "onoi/message-reporter" in result.stderr
    # data-values/geo is installed, so it must NOT be reported.
    assert "data-values/geo" not in result.stderr


def test_noop_when_vendor_or_config_absent(tmp_path):
    """No installed.json yet (composer never ran) → nothing to verify, exit 0
    so non-composer builds aren't blocked."""
    mw_home = tmp_path / "w"
    mw_home.mkdir()
    _write_json(mw_home / "composer.local.json",
                {"extra": {"merge-plugin": {"include":
                 ["extensions/Elastica/composer.json"]}}})
    result = _run(mw_home)
    assert result.returncode == 0
