"""The startup auto-update runs once, from run-all.sh before Apache starts.
The background run-maintenance-scripts.sh started afterwards must not run
it again."""

import os
import re
import subprocess
import textwrap


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPTS = os.path.join(REPO_ROOT, "_sources", "scripts")
RMS = os.path.join(SCRIPTS, "run-maintenance-scripts.sh")
RUN_ALL = os.path.join(SCRIPTS, "run-all.sh")


def _execute_entry_point(tmp_path, autoupdate):
    mw_volume = tmp_path / "mediawiki"
    www_root = tmp_path / "www"
    (mw_volume / "config").mkdir(parents=True)
    www_root.mkdir()
    (mw_volume / "config" / "wikis.yaml").touch()
    (www_root / ".maintenance").touch()
    env = os.environ.copy()
    env.update({
        "MW_VOLUME": str(mw_volume),
        "WWW_ROOT": str(www_root),
        "MW_AUTOUPDATE": autoupdate,
        "USE_EXTERNAL_DB": "true",
    })
    wrapper = textwrap.dedent("""
        isFalse() { [ "$1" != "true" ]; }
        isTrue() { [ "$1" = "true" ]; }
        get_mediawiki_db_var() { [ "$1" = wgDBtype ] && echo mysql; }
        get_wiki_ids() { echo alpha; }
        php() { :; }
        sleep() { :; }
        export -f isFalse isTrue get_mediawiki_db_var get_wiki_ids php sleep
        bash %s
    """) % RMS
    result = subprocess.run(
        ["bash", "-c", wrapper], env=env, capture_output=True, text=True,
    )
    return result, www_root


def test_background_entry_point_does_not_update(tmp_path):
    result, www_root = _execute_entry_point(tmp_path, "true")
    assert "Checking for configuration" in result.stdout, result.stderr
    assert "Check for the need to run maintenance scripts" not in result.stderr
    assert "update.php" not in result.stderr
    assert not (www_root / ".maintenance").exists()


def test_background_entry_point_with_autoupdate_disabled(tmp_path):
    result, www_root = _execute_entry_point(tmp_path, "false")
    assert "Check for the need to run maintenance scripts" not in result.stderr
    assert not (www_root / ".maintenance").exists()


def _code_lines(path):
    with open(path) as f:
        return [l for l in f if not l.lstrip().startswith("#")]


def test_run_all_is_the_only_caller():
    callers = {}
    for path in (RUN_ALL, RMS):
        for line in _code_lines(path):
            if re.match(r"^\s*run_autoupdate\s*$", line):
                callers[os.path.basename(path)] = callers.get(
                    os.path.basename(path), 0) + 1
    assert callers == {"run-all.sh": 1}


def _run_all_update_block(tmp_path, autoupdate):
    """Run run-all.sh's update block, from the configuration check up to the
    Apache rewrite setup, with run_autoupdate stubbed."""
    with open(RUN_ALL) as f:
        content = f.read()
    start = content.index('echo "Checking for MediaWiki configuration..."')
    end = content.index("# Configure Apache rewrites")
    block = content[start:end].replace(". /run-maintenance-scripts.sh", ". %s" % RMS)
    script = textwrap.dedent("""
        export MW_VOLUME=%(tmp)s MW_HOME=%(tmp)s MW_SECRET_KEY=key
        export MW_AUTOUPDATE=%(autoupdate)s
        isTrue() { [ "$1" = "true" ]; }
        get_mediawiki_db_var() { :; }
        php() { :; }
    """) % {"tmp": tmp_path, "autoupdate": autoupdate}
    script += block + "\n"
    # The block sources the real script, so stub run_autoupdate after it.
    script = script.replace(
        ". %s\n" % RMS, ". %s\nrun_autoupdate() { echo UPDATED; }\n" % RMS, 1)
    return subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True,
    )


def test_run_all_updates_when_enabled(tmp_path):
    result = _run_all_update_block(tmp_path, "true")
    assert result.stdout.count("UPDATED") == 1, result.stderr


def test_run_all_honors_mw_autoupdate(tmp_path):
    result = _run_all_update_block(tmp_path, "false")
    assert "UPDATED" not in result.stdout
    assert "Auto update script is disabled" in result.stdout
