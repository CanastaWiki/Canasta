"""Tests for _sources/scripts/create-storage-dirs.sh.

On every container start the script creates each wiki's cache, images and
public_assets directories under MW_VOLUME, sets their ownership, and makes
sure images/.htaccess denies direct access. chown and stat are stubbed: the
test can't change ownership, and the stubs record what the script asked for.
"""

import os
import subprocess

import pytest

from conftest import REPO_ROOT, write_wikis

SCRIPT = os.path.join(REPO_ROOT, "_sources", "scripts", "create-storage-dirs.sh")
STORAGE = ("cache", "images", "public_assets")


def _bash_has_readarray():
    result = subprocess.run(["bash", "-c", "readarray -t x <<< a"],
                            capture_output=True)
    return result.returncode == 0


pytestmark = pytest.mark.skipif(not _bash_has_readarray(),
                                reason="needs bash 4 or later")


@pytest.fixture
def run(workspace):
    bindir = workspace["tmp_path"] / "bin"
    bindir.mkdir()
    log = workspace["tmp_path"] / "chown.log"
    (bindir / "chown").write_text('#!/bin/sh\necho "$*" >> "$CHOWN_LOG"\n')
    (bindir / "stat").write_text("#!/bin/sh\necho 1234\n")
    for stub in ("chown", "stat"):
        (bindir / stub).chmod(0o755)
    mw_volume = workspace["mw_volume"]
    (mw_volume / "public_assets").mkdir()

    def _run(wiki_ids):
        write_wikis(workspace["wikis_yaml"],
                    [{"id": i, "url": "example.com/" + i} for i in wiki_ids])
        env = dict(os.environ, MW_VOLUME=str(mw_volume),
                   WWW_USER="www-data", WWW_GROUP="www-data",
                   CHOWN_LOG=str(log),
                   PATH=str(bindir) + os.pathsep + os.environ["PATH"])
        result = subprocess.run(["bash", SCRIPT], env=env,
                                capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        return log.read_text().splitlines() if log.exists() else []

    _run.mw_volume = mw_volume
    _run.htaccess = mw_volume / "images" / ".htaccess"
    return _run


def test_creates_each_wikis_directories(run):
    run(["main", "docs", "fr"])
    for wiki in ("main", "docs", "fr"):
        for storage in STORAGE:
            assert (run.mw_volume / storage / wiki).is_dir()


def test_sets_ownership(run):
    calls = run(["main"])
    v = run.mw_volume
    assert calls == [
        "-R www-data:www-data %s" % (v / "cache" / "main"),
        "-R www-data:www-data %s" % (v / "images" / "main"),
        "1234:www-data %s" % (v / "public_assets" / "main"),
    ]


def test_keeps_existing_content(run):
    page = run.mw_volume / "images" / "main" / "a" / "ab" / "Logo.png"
    page.parent.mkdir(parents=True)
    page.write_bytes(b"png")
    run(["main"])
    assert page.read_bytes() == b"png"


def test_creates_htaccess(run):
    run(["main"])
    assert run.htaccess.read_text() == "Deny from All\n"


def test_adds_rule_to_existing_htaccess(run):
    run.htaccess.parent.mkdir(parents=True)
    run.htaccess.write_text("Options -Indexes\n")
    run(["main"])
    assert run.htaccess.read_text() == "Options -Indexes\nDeny from All\n"


def test_keeps_htaccess_that_has_the_rule(run):
    run.htaccess.parent.mkdir(parents=True)
    run.htaccess.write_text("Options -Indexes\nDeny from All\n")
    run(["main"])
    assert run.htaccess.read_text() == "Options -Indexes\nDeny from All\n"


def test_rule_added_once_across_restarts(run):
    run(["main"])
    run(["main"])
    run(["main", "docs"])
    assert run.htaccess.read_text().count("Deny from All") == 1
    assert (run.mw_volume / "cache" / "docs").is_dir()
