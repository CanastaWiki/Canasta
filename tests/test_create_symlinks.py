"""Tests for _sources/scripts/create-symlinks.sh.

On every start the script links each bundled extension and skin into
extensions/ and skins/, then links the user ones over them.
"""

import os
import subprocess

import pytest

from conftest import REPO_ROOT

SCRIPT = os.path.join(REPO_ROOT, "_sources", "scripts", "create-symlinks.sh")


@pytest.fixture
def mw_home(tmp_path):
    home = tmp_path / "w"
    for d in ("canasta-extensions", "canasta-skins", "user-extensions",
              "user-skins", "extensions", "skins"):
        (home / d).mkdir(parents=True)
    return home


def run(mw_home):
    result = subprocess.run(["bash", SCRIPT],
                            env=dict(os.environ, MW_HOME=str(mw_home)),
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return result


def test_links_bundled_extensions_and_skins_relatively(mw_home):
    (mw_home / "canasta-extensions" / "Foo").mkdir()
    (mw_home / "canasta-skins" / "Vector").mkdir()
    run(mw_home)
    assert os.readlink(mw_home / "extensions" / "Foo") == "../canasta-extensions/Foo"
    assert os.readlink(mw_home / "skins" / "Vector") == "../canasta-skins/Vector"


def test_user_extension_and_skin_replace_bundled(mw_home):
    for d in ("canasta-extensions/Foo", "user-extensions/Foo",
              "canasta-skins/Vector", "user-skins/Vector"):
        (mw_home / d).mkdir()
    run(mw_home)
    assert os.readlink(mw_home / "extensions" / "Foo") == "../user-extensions/Foo"
    assert os.readlink(mw_home / "skins" / "Vector") == "../user-skins/Vector"


def test_user_extension_that_is_a_symlink_is_linked(mw_home, tmp_path):
    elsewhere = tmp_path / "checkout" / "Mine"
    elsewhere.mkdir(parents=True)
    (mw_home / "user-extensions" / "Mine").symlink_to(elsewhere)
    run(mw_home)
    assert os.readlink(mw_home / "extensions" / "Mine") == "../user-extensions/Mine"


def test_bundled_symlink_is_not_linked(mw_home, tmp_path):
    elsewhere = tmp_path / "Other"
    elsewhere.mkdir()
    (mw_home / "canasta-extensions" / "Other").symlink_to(elsewhere)
    run(mw_home)
    assert not os.path.lexists(mw_home / "extensions" / "Other")


def test_real_directory_in_the_way_is_replaced(mw_home):
    (mw_home / "canasta-extensions" / "Foo").mkdir()
    stale = mw_home / "extensions" / "Foo"
    stale.mkdir()
    (stale / "old.php").write_text("")
    run(mw_home)
    assert os.readlink(stale) == "../canasta-extensions/Foo"


def test_rerun_keeps_links(mw_home):
    (mw_home / "canasta-extensions" / "Foo").mkdir()
    run(mw_home)
    run(mw_home)
    link = mw_home / "extensions" / "Foo"
    assert os.readlink(link) == "../canasta-extensions/Foo"
    assert not os.path.lexists(mw_home / "canasta-extensions" / "Foo" / "Foo")


def test_name_with_space(mw_home):
    (mw_home / "user-extensions" / "My Ext").mkdir()
    run(mw_home)
    assert os.readlink(mw_home / "extensions" / "My Ext") == "../user-extensions/My Ext"


def test_missing_user_directories_are_tolerated(mw_home):
    (mw_home / "user-extensions").rmdir()
    (mw_home / "user-skins").rmdir()
    (mw_home / "canasta-extensions" / "Foo").mkdir()
    run(mw_home)
    assert os.readlink(mw_home / "extensions" / "Foo") == "../canasta-extensions/Foo"
