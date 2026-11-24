"""Every container start creates the canasta_sessions table for each wiki whose
database exists, whether or not the auto-update ran."""

import os
import re
import subprocess
import textwrap


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RMS = os.path.join(REPO_ROOT, "_sources", "scripts", "run-maintenance-scripts.sh")
RUN_ALL = os.path.join(REPO_ROOT, "_sources", "scripts", "run-all.sh")


def _run(tmp_path, wiki_ids, missing="", failing=""):
    """Run create_sessions_tables. Wikis in `missing` have no database, and
    the table script fails for wikis in `failing`."""
    script = textwrap.dedent("""
        php() { case "$*" in *--variable=wgDBname*) last="${!#}"; echo "db_${last#--wiki=}" ;; esac; }
        get_mediawiki_db_var() { echo ""; }
        . %(rms)s
        WG_DB_TYPE=mysql
        WG_DB_SERVER=db
        get_wiki_ids() { printf '%%s' "%(wiki_ids)s"; }
        waitdatabase() { return 0; }
        mysql() {
            for w in %(missing)s; do
                if [ "${!#}" = "db_$w" ]; then echo "ERROR 1049 (42000): Unknown database" >&2; return 1; fi
            done
        }
        runuser() {
            echo "RAN $2"
            for w in %(failing)s; do
                [ "$2" = "php maintenance/createSessionsTable.php --wiki=$w" ] && return 1
            done
            return 0
        }
        create_sessions_tables
        echo "rc=$?"
    """) % {"rms": RMS, "wiki_ids": wiki_ids, "missing": missing, "failing": failing}
    result = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, cwd=tmp_path,
    )
    ran = [l for l in result.stdout.splitlines() if l.startswith("RAN ")]
    return result, ran


def test_each_wiki_gets_the_table(tmp_path):
    result, ran = _run(tmp_path, "alpha\nbeta\n")
    assert ran == [
        "RAN php maintenance/createSessionsTable.php --wiki=alpha",
        "RAN php maintenance/createSessionsTable.php --wiki=beta",
    ]
    assert "rc=0" in result.stdout


def test_single_wiki_runs_without_wiki_option(tmp_path):
    _, ran = _run(tmp_path, "")
    assert ran == ["RAN php maintenance/createSessionsTable.php"]


def test_wiki_without_database_is_skipped(tmp_path):
    _, ran = _run(tmp_path, "alpha\nbeta\n", missing="alpha")
    assert ran == ["RAN php maintenance/createSessionsTable.php --wiki=beta"]


def test_failure_is_reported_and_the_rest_still_run(tmp_path):
    result, ran = _run(tmp_path, "alpha\nbeta\n", failing="alpha")
    assert len(ran) == 2
    assert "Could not create the sessions table for wiki: alpha" in result.stderr
    assert "rc=0" in result.stdout


def test_startup_runs_it_after_the_autoupdate_gate():
    with open(RUN_ALL) as f:
        source = f.read()
    gate = re.search(
        r'^  if isTrue "\$MW_AUTOUPDATE"; then\n.*?^  fi\n  create_sessions_tables\n',
        source, re.S | re.M,
    )
    assert gate, "create_sessions_tables must run after the MW_AUTOUPDATE block, not inside it"
