"""In a farm, the job runner and transcoder run runJobs.php once per wiki
with --wiki and no --server. FarmConfigLoader.php derives the wiki's
server (host only, with MW_SITE_SERVER's scheme) and paths from wikis.yaml;
a --server override would replace that with the wiki's full URL."""

import os
import subprocess
import textwrap

import pytest


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPTS = os.path.join(REPO_ROOT, "_sources", "scripts", "maintenance-scripts")


@pytest.mark.parametrize("script", ["mw_job_runner.sh", "mw_transcoder.sh"])
def test_each_wiki_runs_with_wiki_and_no_server(tmp_path, script):
    config = tmp_path / "mediawiki" / "config"
    config.mkdir(parents=True)
    (config / "wikis.yaml").write_text("wikis: []\n")
    calls = tmp_path / "php_calls"
    env = os.environ.copy()
    env.update({
        "MW_HOME": "/mw",
        "MW_VOLUME": str(tmp_path / "mediawiki"),
        "MW_JOB_RUNNER_PAUSE": "stop",
        "MW_JOB_TRANSCODER_PAUSE": "stop",
        "MW_JOB_RUNNER_MAXTIME": "60",
        "MW_JOB_RUNNER_MEMORY_LIMIT": "512M",
        "MW_LOG": str(tmp_path),
        "CALLS": str(calls),
    })
    wrapper = textwrap.dedent("""
        php() {
            [ "$1" = -r ] && { echo "main "; return; }
            echo "$*" >> "$CALLS"
        }
        sleep() { [ "$1" = stop ] && exit 0; :; }
        export -f php sleep
        bash %s
    """) % os.path.join(SCRIPTS, script)
    result = subprocess.run(
        ["bash", "-c", wrapper], env=env, capture_output=True, text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    runs = calls.read_text().splitlines()
    assert runs
    for run in runs:
        args = run.split()
        assert "--wiki=main" in args, run
        assert not any(a.startswith("--server") for a in args), run
