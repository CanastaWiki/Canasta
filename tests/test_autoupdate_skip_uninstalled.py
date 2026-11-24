"""On a farm, the startup update must skip a wiki whose database has not been
created yet instead of reporting it as a failure, and must not record a
fingerprint for it."""

import os
import subprocess
import textwrap


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RMS = os.path.join(REPO_ROOT, "_sources", "scripts", "run-maintenance-scripts.sh")


def _run(tmp_path, wiki_ids, mysql_body, db_type="mysql"):
    """Run run_autoupdate with the real per-wiki update logic. php reports
    each wiki's database as db_<wiki>, and mysql runs mysql_body with the
    database name as its last argument."""
    mw_volume = tmp_path / "mediawiki"
    (mw_volume / "config").mkdir(parents=True, exist_ok=True)
    script = textwrap.dedent("""
        export MW_VOLUME=%(mw_volume)s
        export MW_VERSION=1.43 MW_CORE_VERSION=1.43.0 MW_MAINTENANCE_UPDATE=1
        php() {
            case "$*" in
                *--variable=wgDBname*) last="${!#}"; echo "db_${last#--wiki=}" ;;
                *--versions*) echo hash ;;
            esac
        }
        get_mediawiki_db_var() { echo ""; }
        . %(rms)s
        WG_DB_TYPE=%(db_type)s
        WG_DB_SERVER=db:3307
        WG_DB_USER=root
        WG_DB_PASSWORD=secret
        get_wiki_ids() { printf '%%s' "%(wiki_ids)s"; }
        waitdatabase() { return 0; }
        mysql() { echo "MYSQL $*" >> %(log)s; db="${!#}"; %(mysql_body)s }
        runuser() { echo "RAN $2"; }
        mkdir -p maintenance && touch maintenance/update.php
        run_autoupdate
    """) % {
        "mw_volume": mw_volume,
        "rms": RMS,
        "db_type": db_type,
        "wiki_ids": wiki_ids,
        "mysql_body": mysql_body,
        "log": tmp_path / "mysql.log",
    }
    result = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, cwd=tmp_path,
    )
    ran = [l for l in result.stdout.splitlines() if l.startswith("RAN ")]
    log = tmp_path / "mysql.log"
    calls = log.read_text().splitlines() if log.exists() else []
    return result, ran, calls, mw_volume / "config" / "persistent"


MISSING_BETA = textwrap.dedent("""
    if [ "$db" = db_beta ]; then
        echo "ERROR 1049 (42000): Unknown database 'db_beta'" >&2
        return 1
    fi
""")


def test_missing_database_is_skipped_not_failed(tmp_path):
    result, ran, _, persistent = _run(tmp_path, "alpha\nbeta\ngamma\n", MISSING_BETA)
    assert result.returncode == 0, result.stderr
    assert ran == [
        "RAN php maintenance/update.php --quick --wiki=alpha",
        "RAN php maintenance/update.php --quick --wiki=gamma",
    ]
    assert "beta: database not installed yet, skipping update" in result.stderr
    assert "Auto-update completed\n" in result.stderr
    assert "with errors" not in result.stderr
    assert (persistent / "maintenance_update_alpha.info").exists()
    assert not (persistent / "maintenance_update_beta.info").exists()


def test_check_uses_wiki_database_name_and_port(tmp_path):
    _, _, calls, _ = _run(tmp_path, "alpha\n", "")
    assert calls == ["MYSQL -h db -P 3307 -uroot -psecret -e SELECT 1 db_alpha"]


def test_connection_failure_still_runs_update(tmp_path):
    unreachable = (
        "echo \"ERROR 2002 (HY000): Can't connect to server on 'db'\" >&2; "
        "return 1;"
    )
    result, ran, _, _ = _run(tmp_path, "alpha\n", unreachable)
    assert ran == ["RAN php maintenance/update.php --quick --wiki=alpha"]
    assert "not installed yet" not in result.stderr


def test_non_mysql_database_is_not_checked(tmp_path):
    result, ran, calls, _ = _run(tmp_path, "alpha\n", MISSING_BETA, db_type="sqlite")
    assert calls == []
    assert ran == ["RAN php maintenance/update.php --quick --wiki=alpha"]


def test_current_fingerprint_skips_the_check(tmp_path):
    result, _, _, _ = _run(tmp_path, "alpha\n", "")
    assert result.returncode == 0, result.stderr
    (tmp_path / "mysql.log").unlink(missing_ok=True)
    result, ran, calls, _ = _run(tmp_path, "alpha\n", "")
    assert ran == [] and calls == []
