"""Tests for _sources/scripts/update-images-permissions.sh.

The script makes everything under $MW_VOLUME/images writable by the web
server group, touching only what the web server user cannot already write.
chgrp is stubbed: the test can't change a file's group.
"""

import grp
import os
import pwd
import stat
import subprocess

import pytest

from conftest import REPO_ROOT

SCRIPTS = os.path.join(REPO_ROOT, "_sources", "scripts")


@pytest.fixture
def run(tmp_path):
    # The script sources /functions.sh, so run a copy that sources the
    # repository's.
    script = tmp_path / "update-images-permissions.sh"
    with open(os.path.join(SCRIPTS, "update-images-permissions.sh")) as f:
        text = f.read()
    assert ". /functions.sh" in text
    script.write_text(text.replace(
        ". /functions.sh", ". " + os.path.join(SCRIPTS, "functions.sh")))
    bindir = tmp_path / "bin"
    bindir.mkdir()
    log = tmp_path / "chgrp.log"
    (bindir / "chgrp").write_text('#!/bin/sh\necho "$*" >> "$CHGRP_LOG"\n')
    (bindir / "chgrp").chmod(0o755)
    mw_volume = tmp_path / "mediawiki"
    (mw_volume / "images").mkdir(parents=True)

    def _run():
        env = dict(os.environ, MW_VOLUME=str(mw_volume),
                   WWW_USER=pwd.getpwuid(os.getuid()).pw_name,
                   WWW_GROUP=grp.getgrgid(os.getgid()).gr_name,
                   CHGRP_LOG=str(log),
                   PATH=str(bindir) + os.pathsep + os.environ["PATH"])
        result = subprocess.run(["bash", str(script)], env=env,
                                capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        return log.read_text().splitlines() if log.exists() else []

    _run.images = mw_volume / "images"
    return _run


def mode(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def test_makes_unwritable_files_group_writable(run):
    sub = run.images / "main" / "a"
    sub.mkdir(parents=True)
    upload = sub / "Logo.png"
    upload.write_bytes(b"png")
    upload.chmod(0o444)
    sub.chmod(0o555)
    calls = run()
    group = grp.getgrgid(os.getgid()).gr_name
    # find may batch the paths into fewer chgrp calls.
    assert all(c.split()[0] == group for c in calls)
    assert sorted(a for c in calls for a in c.split()[1:]) == sorted(
        [str(sub), str(upload)])
    assert mode(upload) == 0o464
    assert mode(sub) == 0o575


def test_leaves_writable_files_alone(run):
    upload = run.images / "main" / "Logo.png"
    upload.parent.mkdir()
    upload.write_bytes(b"png")
    upload.chmod(0o644)
    assert run() == []
    assert mode(upload) == 0o644
