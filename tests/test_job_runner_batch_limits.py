"""The general job batch in mw_job_runner.sh is bounded by
MW_JOB_RUNNER_MAXTIME, and also by MW_JOB_RUNNER_MAXJOBS when it is set.
runJobs.php reads --maxtime=0 as no time limit. Every runJobs.php call runs
under MW_JOB_RUNNER_MEMORY_LIMIT; without --memory-limit it uses 150M."""

import os
import subprocess
import textwrap

import pytest


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPT = os.path.join(
    REPO_ROOT, "_sources", "scripts", "maintenance-scripts", "mw_job_runner.sh"
)


def _php_calls(tmp_path, maxtime="60", maxjobs="", farm=False):
    calls = tmp_path / "php_calls"
    if farm:
        config = tmp_path / "mediawiki" / "config"
        config.mkdir(parents=True)
        (config / "wikis.yaml").write_text("wikis: []\n")
    env = os.environ.copy()
    env.update({
        "MW_HOME": "/mw",
        "MW_VOLUME": str(tmp_path / "mediawiki"),
        "MW_JOB_RUNNER_PAUSE": "stop",
        "MW_JOB_RUNNER_MAXTIME": maxtime,
        "MW_JOB_RUNNER_MAXJOBS": maxjobs,
        "MW_JOB_RUNNER_MEMORY_LIMIT": "512M",
        "MW_LOG": str(tmp_path),
        "CALLS": str(calls),
    })
    wrapper = textwrap.dedent("""
        php() {
            [ "$1" = -r ] && { echo "main,wiki.example.com "; return; }
            echo "$*" >> "$CALLS"
        }
        sleep() { [ "$1" = stop ] && exit 0; :; }
        export -f php sleep
        bash %s
    """) % SCRIPT
    result = subprocess.run(
        ["bash", "-c", wrapper], env=env, capture_output=True, text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    return calls.read_text().splitlines()


def _general_batch_args(tmp_path, maxtime, maxjobs):
    general = [c for c in _php_calls(tmp_path, maxtime, maxjobs) if "--type=" not in c]
    assert len(general) == 1, general
    return general[0].split()[1:]


@pytest.mark.parametrize("maxtime,maxjobs,expected", [
    ("60", "", ["--maxtime=60"]),
    ("30", "500", ["--maxtime=30", "--maxjobs=500"]),
    ("0", "10", ["--maxtime=0", "--maxjobs=10"]),
    ("", "10", ["--maxjobs=10"]),
])
def test_general_batch_limits(tmp_path, maxtime, maxjobs, expected):
    assert _general_batch_args(tmp_path, maxtime, maxjobs) == ["--memory-limit=512M"] + expected


@pytest.mark.parametrize("farm", [False, True])
def test_every_run_uses_the_memory_limit(tmp_path, farm):
    calls = _php_calls(tmp_path, farm=farm)
    assert len(calls) == 5, calls
    for call in calls:
        assert "--memory-limit=512M" in call.split(), call


def test_dockerfile_defaults_bound_batch_by_time():
    with open(os.path.join(REPO_ROOT, "Dockerfile")) as f:
        dockerfile = f.read()
    assert "MW_JOB_RUNNER_MAXTIME=60 \\" in dockerfile
    assert "MW_JOB_RUNNER_MAXJOBS= \\" in dockerfile
