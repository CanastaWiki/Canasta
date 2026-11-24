"""Code and config the web server user must not be able to write.

The web server user (www-data) only needs to read extension and skin code
and config/. Write access would let code running as www-data change what
MediaWiki loads on every request: edit bundled code, re-point an
extensions/ or skins/ link, or add a settings file under config/.
"""

import os
import re
import subprocess

import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPTS = os.path.join(REPO_ROOT, "_sources", "scripts")
DOCKERFILE = os.path.join(REPO_ROOT, "Dockerfile")
FUNCTIONS = os.path.join(SCRIPTS, "functions.sh")
RUN_ALL = os.path.join(SCRIPTS, "run-all.sh")
RUN_MAINT = os.path.join(SCRIPTS, "run-maintenance-scripts.sh")
CODE_DIRS = ["extensions", "skins", "canasta-extensions", "canasta-skins"]


def read(path):
    with open(path) as f:
        return f.read()


class TestCodeIsRootOwned:
    @pytest.mark.parametrize("name", CODE_DIRS)
    def test_not_given_to_the_web_user(self, name):
        dockerfile = read(DOCKERFILE)
        assert not re.search(
            rf'chown [^\n]*WWW_USER[^\n]*\$MW_HOME/{name}"', dockerfile
        ), f"{name} must not be chowned to the web server user"
        assert not re.search(
            rf'chmod g\+w[^\n]*\$MW_HOME/{name}"', dockerfile
        ), f"{name} must not be made group-writable"

    def test_bundled_code_is_normalized_to_root(self):
        dockerfile = read(DOCKERFILE)
        assert re.search(
            r'chown -R root:root "\$MW_HOME/canasta-extensions" '
            r'"\$MW_HOME/canasta-skins"',
            dockerfile,
        )
        assert re.search(
            r'chmod -R u=rwX,go=rX "\$MW_HOME/canasta-extensions" '
            r'"\$MW_HOME/canasta-skins"',
            dockerfile,
        )

    def test_links_user_owns_only_the_link_dirs(self):
        dockerfile = read(DOCKERFILE)
        assert re.search(r"^\s*LINKS_USER=canasta-links\b", dockerfile, re.M)
        assert re.search(
            r'useradd --system [^\n]*--shell /usr/sbin/nologin "\$LINKS_USER"',
            dockerfile,
        )
        chowns = re.findall(r'chown[^\n]*\$LINKS_USER[^\n]*', dockerfile)
        assert chowns == [
            'chown "$LINKS_USER:$LINKS_USER" "$MW_HOME/extensions" '
            '"$MW_HOME/skins" \\'
        ], "only the two link directories, and not recursively"

    def test_monitor_runs_as_links_user(self):
        text = read(RUN_MAINT)
        branch = re.search(
            r'elif \[\[ "\$script_name" == monitor-directories\.sh \]\]; then'
            r"(.*?)\n\s*else",
            text,
            re.S,
        )
        assert branch, "monitor-directories.sh needs its own branch"
        assert re.search(
            r'runuser -c "/maintenance-scripts/\$script_name" '
            r'-s /bin/bash "\$LINKS_USER"',
            branch.group(1),
        )
        assert "WWW_USER" not in branch.group(1)


class TestConfigIsNotWritable:
    def test_volume_is_not_made_writable_wholesale(self):
        text = read(RUN_ALL)
        assert not re.search(r'make_dir_writable "\$MW_VOLUME"(\s|$)', text)
        loop = re.search(r"for dir in ([^;]+); do", text)
        assert loop, "expected an explicit list of writable volume dirs"
        dirs = loop.group(1).split()
        assert "config/persistent" in dirs
        assert not any(d == "config" for d in dirs)

    def test_config_is_protected_after_the_initial_copy(self):
        text = read(RUN_ALL)
        copy = text.index('"$MW_ORIGIN_FILES"/ "$MW_VOLUME"/')
        protect = re.search(r"^protect_config$", text, re.M)
        assert protect and copy < protect.start()
        call = re.search(r"^\s*run_autoupdate\s*$", text, re.M)
        assert protect.start() < call.start()


gnu_find = subprocess.run(
    ["find", "--version"], capture_output=True, text=True
).returncode == 0


@pytest.mark.skipif(not gnu_find, reason="protect_config uses GNU find")
class TestProtectConfig:
    def run(self, volume):
        user = subprocess.run(
            ["id", "-un"], capture_output=True, text=True, check=True
        ).stdout.strip()
        return subprocess.run(
            ["bash", "-c", f'. "{FUNCTIONS}"; protect_config'],
            env={**os.environ, "MW_VOLUME": str(volume), "WWW_USER": user},
            capture_output=True,
            text=True,
        )

    def test_removes_group_and_other_write_except_persistent(self, tmp_path):
        config = tmp_path / "config"
        (config / "settings" / "global").mkdir(parents=True)
        (config / "persistent").mkdir()
        settings = config / "settings" / "global" / "Settings.php"
        settings.write_text("<?php\n")
        smw = config / "persistent" / ".smw.json"
        smw.write_text("{}")
        for path in (config, config / "settings", settings,
                     config / "persistent", smw):
            os.chmod(path, 0o777 if path.is_dir() else 0o666)

        result = self.run(tmp_path)
        assert result.returncode == 0, result.stderr

        for path in (config, config / "settings", settings):
            assert not os.stat(path).st_mode & 0o022, path
        for path in (config / "persistent", smw):
            assert os.stat(path).st_mode & 0o022 == 0o022, path

    def test_no_config_dir_is_fine(self, tmp_path):
        assert self.run(tmp_path).returncode == 0
