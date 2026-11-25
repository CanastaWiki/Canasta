"""Tests for _sources/scripts/rotatelogs-compress.sh.

Apache's rotatelogs calls the script with the log it just closed as $2. The
script gzips that file, then cleans up the log directory.
"""

import os
import subprocess
import tarfile
import time

import pytest

from conftest import REPO_ROOT

SCRIPT = os.path.join(REPO_ROOT, "_sources", "scripts", "rotatelogs-compress.sh")
DAY = 24 * 60 * 60


def _tar_has_transform():
    result = subprocess.run(["tar", "--help"], capture_output=True, text=True)
    return "--transform" in result.stdout


pytestmark = pytest.mark.skipif(not _tar_has_transform(),
                                reason="needs GNU tar")


def run(log_file, **env):
    env = dict(os.environ, LOG_FILES_COMPRESS_DELAY="0", **env)
    return subprocess.run(["bash", SCRIPT, "unused", str(log_file)],
                          env=env, capture_output=True, text=True)


def age(path, days):
    then = time.time() - days * DAY
    os.utime(path, (then, then))


def members(archive):
    with tarfile.open(archive) as tar:
        return tar.getnames()


def test_compresses_the_closed_log(tmp_path):
    log = tmp_path / "access_log.20260101"
    log.write_text("GET /\n")
    result = run(log, LOG_FILES_REMOVE_OLDER_THAN_DAYS="10")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not log.exists()
    archive = tmp_path / "access_log.20260101.tar.gz"
    assert members(archive) == ["access_log.20260101"]


def test_removes_and_compresses_old_logs(tmp_path):
    log = tmp_path / "access_log.20260110"
    log.write_text("new\n")
    expired = tmp_path / "access_log.20251201.tar.gz"
    expired.write_text("")
    age(expired, 11)
    stale = tmp_path / "error_log.20260105"
    stale.write_text("old\n")
    age(stale, 5)
    current = tmp_path / "error_log.current"
    current.write_text("")
    age(current, 30)
    hidden = tmp_path / ".keep"
    hidden.write_text("")
    age(hidden, 30)

    result = run(log, LOG_FILES_REMOVE_OLDER_THAN_DAYS="10")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not expired.exists()
    assert not stale.exists()
    assert members(tmp_path / "error_log.20260105.tar.gz") == ["error_log.20260105"]
    assert current.exists()
    assert hidden.exists()


def test_missing_log_is_reported(tmp_path):
    result = run(tmp_path / "gone.log", LOG_FILES_REMOVE_OLDER_THAN_DAYS="10")
    assert result.returncode == 0
    assert "does not exist" in result.stdout


def test_without_a_file_does_nothing(tmp_path):
    result = subprocess.run(["bash", SCRIPT], cwd=tmp_path,
                            capture_output=True, text=True)
    assert result.returncode == 0
    assert result.stdout == ""
