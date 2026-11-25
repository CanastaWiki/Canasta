"""waitdatabase in run-maintenance-scripts.sh, which run-all.sh sources and
calls before Apache starts."""

import os
import subprocess
import textwrap


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RMS = os.path.join(REPO_ROOT, "_sources", "scripts", "run-maintenance-scripts.sh")


def _run(tmp_path, db_type, failures=0, external="false"):
    """Source the script and call waitdatabase. The mysql stub fails
    `failures` times before it connects."""
    script = textwrap.dedent("""
        php() { :; }
        get_mediawiki_db_var() { echo ""; }
        . %(rms)s
        isTrue() { [ "$1" = "true" ]; }
        isFalse() { [ "$1" != "true" ]; }
        sleep() { :; }
        WG_DB_TYPE=%(db_type)s
        WG_DB_SERVER=db
        USE_EXTERNAL_DB=%(external)s
        mysql() {
            n=$(cat count 2>/dev/null || echo 0)
            echo $((n + 1)) > count
            [ "$n" -ge %(failures)d ]
        }
        waitdatabase
        echo "rc=$?"
    """) % {"rms": RMS, "db_type": db_type, "failures": failures,
            "external": external}
    return subprocess.run(["bash", "-c", script], capture_output=True,
                          text=True, cwd=tmp_path)


def test_unusable_settings_return_instead_of_exiting(tmp_path):
    result = _run(tmp_path, "'PHP Fatal error: oops in Settings.php'")
    assert result.returncode == 0
    assert "rc=1" in result.stdout
    assert "PHP Fatal error: oops in Settings.php" in result.stderr


def test_empty_db_type_is_reported(tmp_path):
    result = _run(tmp_path, "''")
    assert "rc=1" in result.stdout
    assert "(nothing)" in result.stderr


def test_connects_on_first_attempt(tmp_path):
    result = _run(tmp_path, "mysql")
    assert "rc=0" in result.stdout


def test_connection_on_last_attempt_succeeds(tmp_path):
    result = _run(tmp_path, "mysql", failures=60)
    assert "rc=0" in result.stdout
    assert "Successfully connected" in result.stderr


def test_no_connection_fails(tmp_path):
    result = _run(tmp_path, "mysql", failures=61)
    assert "rc=1" in result.stdout
    assert "Could not connect to the database." in result.stderr
