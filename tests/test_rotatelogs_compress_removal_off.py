"""rotatelogs-compress.sh, which Apache's rotatelogs runs after each log
rotation. tar is stubbed: the script uses GNU-only options."""

import os
import subprocess
import time

import pytest


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPT = os.path.join(REPO_ROOT, "_sources", "scripts", "rotatelogs-compress.sh")


@pytest.mark.parametrize("remove_after", ["false", ""])
def test_old_logs_compressed_when_removal_is_off(tmp_path, remove_after):
    logs = tmp_path / "logs"
    logs.mkdir()
    rotated = logs / "access_log_20261124"
    rotated.write_text("new")
    old = logs / "access_log_20261101"
    old.write_text("old")
    week_ago = time.time() - 7 * 86400
    os.utime(old, (week_ago, week_ago))

    bindir = tmp_path / "bin"
    bindir.mkdir()
    tar_log = tmp_path / "tar.log"
    (bindir / "tar").write_text('#!/bin/sh\necho "$*" >> "$TAR_LOG"\n')
    (bindir / "tar").chmod(0o755)
    env = dict(os.environ, TAR_LOG=str(tar_log),
               LOG_FILES_COMPRESS_DELAY="0",
               LOG_FILES_REMOVE_OLDER_THAN_DAYS=remove_after,
               PATH=str(bindir) + os.pathsep + os.environ["PATH"])
    result = subprocess.run(
        ["bash", SCRIPT, str(logs / "access_log.current"), str(rotated)],
        env=env, capture_output=True, text=True)

    assert result.returncode == 0, result.stderr
    calls = tar_log.read_text().splitlines()
    assert any(c.endswith(" %s" % rotated) for c in calls)
    assert any(c.endswith(" %s" % old) for c in calls)
    assert old.exists()
