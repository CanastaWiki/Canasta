"""On a farm, a failed update.php for one wiki must not stop the startup
update pass from reaching the wikis after it."""

import os
import subprocess
import textwrap


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RMS = os.path.join(REPO_ROOT, "_sources", "scripts", "run-maintenance-scripts.sh")


def _run(tmp_path, wiki_ids, failing):
    script = textwrap.dedent("""
        export MW_VOLUME=%(tmp)s
        php() { :; }
        get_mediawiki_db_var() { echo ""; }
        . %(rms)s
        get_wiki_ids() { printf '%%s' "%(wiki_ids)s"; }
        run_maintenance_script_if_needed() {
            echo "RAN $1"
            case " %(failing)s " in *" $1 "*) return 3 ;; esac
        }
        run_autoupdate
    """) % {"tmp": tmp_path, "rms": RMS, "wiki_ids": wiki_ids,
            "failing": " ".join(failing)}
    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    ran = [l for l in result.stdout.splitlines() if l.startswith("RAN ")]
    return result, ran


def test_farm_continues_past_a_failed_wiki(tmp_path):
    result, ran = _run(tmp_path, "alpha\nbeta\ngamma\n", ["maintenance_update_beta"])
    assert ran == [
        "RAN maintenance_update_alpha",
        "RAN maintenance_update_beta",
        "RAN maintenance_update_gamma",
    ]
    assert result.returncode == 3
    assert "running for wiki: beta" in result.stderr
    assert "Auto-update completed with errors" in result.stderr


def test_farm_without_failures_succeeds(tmp_path):
    result, _ = _run(tmp_path, "alpha\nbeta\n", [])
    assert result.returncode == 0, result.stderr
    assert "Auto-update completed\n" in result.stderr


def test_single_wiki_failure_is_returned(tmp_path):
    result, ran = _run(tmp_path, "", ["maintenance_update"])
    assert ran == ["RAN maintenance_update"]
    assert result.returncode == 3
