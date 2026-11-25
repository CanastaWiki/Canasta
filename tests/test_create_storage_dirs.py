"""Tests for _sources/scripts/create-storage-dirs.sh.

On every container start the script creates each wiki's cache, images and
public_assets directories under MW_VOLUME, sets their ownership, and makes
sure images/.htaccess denies direct access. chown and stat are stubbed: the
test can't change ownership, and the stubs record what the script asked for.

Wiki IDs come from get_wiki_ids in functions.sh, which reads wikis.yaml with
yaml_parse_file. The php extension providing it is not installed here, so a
php wrapper defines it with json_decode and wikis.yaml is written as JSON,
which is valid YAML.
"""

import json
import os
import shutil
import subprocess

import pytest

from conftest import REPO_ROOT

SCRIPTS = os.path.join(REPO_ROOT, "_sources", "scripts")
SCRIPT = os.path.join(SCRIPTS, "create-storage-dirs.sh")
STORAGE = ("cache", "images", "public_assets")

pytestmark = pytest.mark.skipif(shutil.which("php") is None,
                                reason="needs php")

PHP_WRAPPER = """#!/bin/sh
if [ "$1" = "-r" ]; then
    code=$2
    shift 2
    exec "$REAL_PHP" -r "if (!function_exists('yaml_parse_file')) {
        function yaml_parse_file(\\$f) { return json_decode(file_get_contents(\\$f), true); }
    } $code" "$@"
fi
exec "$REAL_PHP" "$@"
"""


@pytest.fixture
def run(workspace):
    bindir = workspace["tmp_path"] / "bin"
    bindir.mkdir()
    log = workspace["tmp_path"] / "chown.log"
    (bindir / "chown").write_text('#!/bin/sh\necho "$*" >> "$CHOWN_LOG"\n')
    (bindir / "stat").write_text("#!/bin/sh\necho 1234\n")
    (bindir / "php").write_text(PHP_WRAPPER)
    for stub in ("chown", "stat", "php"):
        (bindir / stub).chmod(0o755)
    mw_volume = workspace["mw_volume"]
    (mw_volume / "public_assets").mkdir()
    with open(SCRIPT) as f:
        body = f.read().replace(
            ". /functions.sh", ". %s" % os.path.join(SCRIPTS, "functions.sh"))

    def _run(wiki_ids, wikis=None):
        if wikis is None:
            wikis = [{"id": i, "url": "example.com/" + i} for i in wiki_ids]
        workspace["wikis_yaml"].write_text(json.dumps({"wikis": wikis}))
        env = dict(os.environ, MW_VOLUME=str(mw_volume),
                   WWW_USER="www-data", WWW_GROUP="www-data",
                   CHOWN_LOG=str(log), REAL_PHP=shutil.which("php"),
                   PATH=str(bindir) + os.pathsep + os.environ["PATH"])
        result = subprocess.run(["bash", "-c", body], env=env,
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


def test_sets_ownership_of_the_directories_only(run):
    calls = run(["main"])
    v = run.mw_volume
    assert calls == [
        "www-data:www-data %s" % (v / "cache" / "main"),
        "www-data:www-data %s" % (v / "images" / "main"),
        "1234:www-data %s" % (v / "public_assets" / "main"),
    ]


def test_all_digit_id_has_no_quotes(run):
    run(["2024"])
    for storage in STORAGE:
        assert sorted(p.name for p in (run.mw_volume / storage).iterdir()
                      if p.is_dir()) == ["2024"]


def test_id_inside_a_name_is_not_a_wiki(run):
    run(None, wikis=[{"id": "main", "url": "example.com",
                      "name": "Wiki id: secret"}])
    assert sorted(p.name for p in (run.mw_volume / "cache").iterdir()) == ["main"]


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
