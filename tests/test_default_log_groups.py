"""Tests for the default $wgDebugLogGroups in CanastaDefaultSettings.php.

Every default log group must write a *.log file directly in $MW_LOG,
since that is the only pattern mw_log_rotator.sh rotates.
"""

import os
import re

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SETTINGS = os.path.join(
    REPO_ROOT, "_sources", "canasta", "CanastaDefaultSettings.php"
)
ROTATOR = os.path.join(
    REPO_ROOT, "_sources", "scripts", "maintenance-scripts", "mw_log_rotator.sh"
)


def read(path):
    with open(path) as f:
        return f.read()


def default_log_groups():
    body = re.search(
        r"\$wgDebugLogGroups = \[(.*?)\];", read(SETTINGS), re.S
    ).group(1)
    return dict(re.findall(r"'([\w-]+)' => (.+?),\s*$", body, re.M))


def test_exec_channel_is_logged():
    assert "exec" in default_log_groups()


def test_every_group_writes_a_rotated_log():
    groups = default_log_groups()
    assert groups
    for name, value in groups.items():
        assert re.fullmatch(
            r"getenv\( 'MW_LOG' \) \. '/[\w-]+\.log'", value
        ), f"{name} does not log to $MW_LOG/*.log: {value}"
    assert '"$MW_LOG"/*.log' in read(ROTATOR)
