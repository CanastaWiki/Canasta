"""The update.php fingerprints must live on the config bind mount so they
survive container recreation."""

import os
import subprocess
import textwrap


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RMS_SCRIPT = os.path.join(
    REPO_ROOT, "_sources", "scripts", "run-maintenance-scripts.sh",
)


def _run_twice(tmp_path, fingerprint):
    mw_volume = tmp_path / "mediawiki"
    (mw_volume / "config").mkdir(parents=True)
    script_file = tmp_path / "update.php"
    script_file.touch()
    script = textwrap.dedent("""
        export MW_VOLUME=%(mw_volume)s
        get_mediawiki_db_var() { echo ""; }
        php() { :; }
        . %(rms)s
        waitdatabase() { return 0; }
        runuser() { echo "RAN"; }
        run_maintenance_script_if_needed maintenance_update_alpha "%(fingerprint)s" %(script)s
        run_maintenance_script_if_needed maintenance_update_alpha "%(fingerprint)s" %(script)s
    """) % {
        "mw_volume": mw_volume,
        "rms": RMS_SCRIPT,
        "fingerprint": fingerprint,
        "script": script_file,
    }
    result = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True,
    )
    return result, mw_volume


def test_fingerprint_written_under_config_persistent(tmp_path):
    result, mw_volume = _run_twice(tmp_path, "v-c-u-hash")
    assert result.returncode == 0, result.stderr
    fingerprint_file = mw_volume / "config" / "persistent" / "maintenance_update_alpha.info"
    assert fingerprint_file.read_text() == "v-c-u-hash\n"
    assert not (mw_volume / "maintenance_update_alpha.info").exists()


def test_matching_fingerprint_skips_second_run(tmp_path):
    result, _ = _run_twice(tmp_path, "v-c-u-hash")
    assert result.returncode == 0, result.stderr
    assert result.stdout.count("RAN") == 1
    assert "maintenance_update_alpha is up to date" in result.stderr
