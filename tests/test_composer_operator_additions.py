"""Tests for the composer include handling: the image keeps the bundled list
(composer.canasta.json), config/composer.local.json holds only the operator's
additions, and update-composer-deps.sh runs composer only when those change.

The build runs the real extensions-skins.php (with yaml_parse stubbed by
json_decode, since php-yaml is usually absent outside the image) and the
startup runs the real create-symlinks.sh and update-composer-deps.sh, with a
stub `composer` on PATH that logs its calls.
"""

import json
import re
import os
import shutil
import subprocess
import textwrap

import pytest


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPTS = os.path.join(REPO_ROOT, "_sources", "scripts")

pytestmark = pytest.mark.skipif(
    shutil.which("php") is None, reason="php not available"
)

YAML_STUB = """<?php
if (!function_exists('yaml_parse')) {
    function yaml_parse($text) { return json_decode($text, true); }
}
"""

COMPOSER_STUB = textwrap.dedent("""\
    #!/bin/bash
    echo "composer $*" >> "$STUB_LOG"
    echo "stub composer output"
    if [ -n "$STUB_INSTALLED" ]; then
      mkdir -p "$MW_HOME/vendor/composer"
      printf '%s' "$STUB_INSTALLED" > "$MW_HOME/vendor/composer/installed.json"
    fi
    exit "${STUB_EXIT:-0}"
    """)

BUNDLED = {"Foo": {"require": {"foo/lib": "^1"}},
           "Bar": {"require": {"bar/lib": "^1"}}}


def _write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))


def _read_json(path):
    return json.loads(path.read_text())


class Instance:
    """A fake image ($MW_HOME, $MW_ORIGIN_FILES) and instance ($MW_VOLUME)."""

    def __init__(self, tmp_path):
        self.tmp = tmp_path
        self.mw_home = tmp_path / "w"
        self.mw_volume = tmp_path / "mediawiki"
        self.origin = tmp_path / "origin"
        self.log = tmp_path / "composer.log"
        self.config = self.mw_volume / "config" / "composer.local.json"
        self.failed = (self.mw_volume / "config" / "persistent"
                       / "composer-update.failed")
        for d in ("extensions", "skins", "canasta-skins", "user-extensions",
                  "user-skins", "maintenance"):
            (self.mw_home / d).mkdir(parents=True, exist_ok=True)
        (self.mw_volume / "config").mkdir(parents=True)
        self.origin.mkdir()
        for name, data in BUNDLED.items():
            _write_json(self.mw_home / "canasta-extensions" / name
                        / "composer.json", data)
        for script in ("composer-local.php", "verify-composer-deps.php"):
            shutil.copy(os.path.join(SCRIPTS, script),
                        self.mw_home / "maintenance" / script)
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        (bin_dir / "composer").write_text(COMPOSER_STUB)
        (bin_dir / "composer").chmod(0o755)
        (tmp_path / "yaml_stub.php").write_text(YAML_STUB)
        self.env = os.environ.copy()
        self.env.update({
            "PATH": "%s:%s" % (bin_dir, self.env["PATH"]),
            "MW_HOME": str(self.mw_home),
            "MW_VOLUME": str(self.mw_volume),
            "MW_ORIGIN_FILES": str(self.origin),
            "MW_VERSION": "REL1_43",
            "STUB_LOG": str(self.log),
        })

    def build(self, real_dirs=()):
        """Run extensions-skins.php with Foo and Bar bundled and needing
        composer. Names in real_dirs are bundled as real directories in
        extensions/, as composer-installed packages are."""
        for name in real_dirs:
            _write_json(self.mw_home / "extensions" / name / "composer.json",
                        {"require": {"real/lib": "^1"}})
        contents = self.tmp / "contents.json"
        _write_json(contents, {"extensions": [
            {name: {"bundled": True, "additional steps": ["composer update"]}}
            for name in list(BUNDLED) + list(real_dirs)
        ]})
        result = subprocess.run(
            ["php", "-d", "auto_prepend_file=%s" % (self.tmp / "yaml_stub.php"),
             os.path.join(SCRIPTS, "extensions-skins.php"), str(contents)],
            env=self.env, capture_output=True, text=True,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        self.log.unlink()
        return result

    def start(self, **env):
        """Run the startup steps: create-symlinks.sh, then the composer
        update. Returns (CompletedProcess, composer was invoked)."""
        run_env = dict(self.env, **env)
        subprocess.run(["bash", os.path.join(SCRIPTS, "create-symlinks.sh")],
                       env=run_env, capture_output=True, text=True, check=True)
        if self.log.exists():
            self.log.unlink()
        result = subprocess.run(
            ["bash", os.path.join(SCRIPTS, "update-composer-deps.sh")],
            env=run_env, capture_output=True, text=True,
        )
        return result, self.log.exists()

    def effective(self):
        return _read_json(self.mw_home / "composer.local.json")

    def includes(self):
        return self.effective()["extra"]["merge-plugin"]["include"]

    def user_extension(self, name, data):
        _write_json(self.mw_home / "user-extensions" / name / "composer.json",
                    data)


IMAGE_INCLUDES = ["extensions/Foo/composer.json", "extensions/Bar/composer.json"]


@pytest.fixture
def inst(tmp_path):
    instance = Instance(tmp_path)
    instance.build()
    return instance


def test_build_keeps_list_in_image_and_does_not_seed_config(inst):
    assert not (inst.origin / "config" / "composer.local.json").exists()
    bundled = _read_json(inst.mw_home / "composer.canasta.json")
    assert bundled["extra"]["merge-plugin"]["include"] == IMAGE_INCLUDES
    assert inst.includes() == IMAGE_INCLUDES


def test_new_instance_uses_build_vendor(inst):
    result, ran = inst.start()
    assert result.returncode == 0, result.stderr
    assert not ran, "composer must not run without operator content"
    assert not inst.config.exists()


def test_old_bundled_copy_skips_composer(inst):
    # A copy seeded by an older image: its own bundled list, including an
    # extension the image no longer bundles.
    _write_json(inst.config, {"extra": {"merge-plugin": {"include": [
        "extensions/Foo/composer.json",
        "extensions/Gone/composer.json",
    ]}}})
    result, ran = inst.start()
    assert result.returncode == 0, result.stderr
    assert not ran
    assert inst.includes() == IMAGE_INCLUDES


def test_operator_additions_merged_with_image_list(inst):
    inst.user_extension("Mine", {"require": {"mine/lib": "^2"}})
    _write_json(inst.config, {
        "require": {"some/package": "^1.0"},
        "repositories": [{"type": "vcs", "url": "https://example.com/r.git"}],
        "extra": {"merge-plugin": {"include": [
            "extensions/Foo/composer.json",
            "extensions/Gone/composer.json",
            "extensions/Mine/composer.json",
        ]}},
    })
    result, ran = inst.start()
    assert result.returncode == 0, result.stderr
    assert ran
    effective = inst.effective()
    assert inst.includes() == IMAGE_INCLUDES + ["extensions/Mine/composer.json"]
    assert effective["require"] == {"some/package": "^1.0"}
    assert effective["repositories"][0]["url"] == "https://example.com/r.git"

    result, ran = inst.start()
    assert not ran, "unchanged operator content must not rerun composer"

    inst.user_extension("Mine", {"require": {"mine/lib": "^3"}})
    result, ran = inst.start()
    assert ran, "a changed user extension composer.json must rerun composer"


def test_override_of_bundled_extension_is_operator_content(inst):
    inst.user_extension("Foo", {"require": {"foo/lib": "^2"}})
    result, ran = inst.start()
    assert result.returncode == 0, result.stderr
    assert ran, "an overridden bundled extension must be resolved"
    assert inst.includes() == IMAGE_INCLUDES

    result, ran = inst.start()
    assert not ran

    inst.user_extension("Foo", {"require": {"foo/lib": "^3"}})
    result, ran = inst.start()
    assert ran


def test_exclude_bundled_removes_include(inst):
    _write_json(inst.config, {"extra": {"canasta": {"exclude-bundled": [
        "extensions/Bar/composer.json",
    ]}}})
    result, ran = inst.start()
    assert result.returncode == 0, result.stderr
    assert ran
    assert inst.includes() == ["extensions/Foo/composer.json"]


def test_exclude_of_unbundled_include_is_no_change(inst):
    _write_json(inst.config, {"extra": {"canasta": {"exclude-bundled": [
        "extensions/Gone/composer.json",
    ]}}})
    result, ran = inst.start()
    assert not ran
    assert inst.includes() == IMAGE_INCLUDES


def test_hash_stable_when_bundled_dir_becomes_symlink(tmp_path):
    inst = Instance(tmp_path)
    inst.build(real_dirs=["Bootstrap"])
    # The instance holds a copy of the build-time list, as older images
    # seeded it.
    shutil.copy(inst.mw_home / "composer.local.json", inst.config)
    # At runtime the bundled copy is reached through a symlink, with a
    # composer.json that differs from the build-time directory's.
    shutil.rmtree(inst.mw_home / "extensions" / "Bootstrap")
    _write_json(inst.mw_home / "canasta-extensions" / "Bootstrap"
                / "composer.json", {"require": {"real/lib": "^1.0"}})
    result, ran = inst.start()
    assert result.returncode == 0, result.stderr
    assert (inst.mw_home / "extensions" / "Bootstrap").is_symlink()
    assert not ran


def test_failure_recorded_and_cleared_on_success(inst):
    _write_json(inst.config, {"require": {"some/package": "^1.0"}})
    result, ran = inst.start(STUB_EXIT="2")
    assert ran
    assert "composer update failed" in result.stderr
    text = inst.failed.read_text()
    assert "exit 2" in text
    assert "extensions/Foo/composer.json" in text
    assert "stub composer output" in text

    result, ran = inst.start(STUB_EXIT="2")
    assert ran, "a failed update must be retried on the next start"

    result, ran = inst.start()
    assert ran
    assert not inst.failed.exists()


def test_failure_cleared_when_no_update_needed(inst):
    inst.failed.parent.mkdir(parents=True)
    inst.failed.write_text("old failure\n")
    result, ran = inst.start()
    assert not ran
    assert not inst.failed.exists()


def test_missing_bundled_dependency_after_update_is_a_failure(inst):
    # composer exits 0 but leaves a bundled extension's package out of
    # vendor/, as an update from a stale include list does.
    _write_json(inst.config, {"require": {"some/package": "^1.0"}})
    installed = json.dumps({"packages": [
        {"name": "foo/lib"}, {"name": "some/package"}]})
    result, ran = inst.start(STUB_INSTALLED=installed)
    assert ran
    assert "bar/lib" in inst.failed.read_text()

    result, ran = inst.start(STUB_INSTALLED=installed)
    assert ran, "the hash must not be saved when verification fails"


def test_other_operator_keys_reach_effective_file(inst):
    _write_json(inst.config, {
        "config": {"platform": {"php": "8.2.0"}},
        "minimum-stability": "dev",
        "prefer-stable": True,
        "autoload": {"psr-4": {"My\\": "extensions/Mine/src/"}},
        "extra": {
            "merge-plugin": {
                "include": ["extensions/Foo/composer.json"],
                "merge-extra": True,
            },
            "canasta": {"exclude-bundled": []},
        },
    })
    result, ran = inst.start()
    assert result.returncode == 0, result.stderr
    assert ran, "carried keys are operator content"
    effective = inst.effective()
    assert effective["config"] == {"platform": {"php": "8.2.0"}}
    assert effective["minimum-stability"] == "dev"
    assert effective["prefer-stable"] is True
    assert effective["autoload"] == {"psr-4": {"My\\": "extensions/Mine/src/"}}
    assert effective["extra"]["merge-plugin"] == {
        "include": IMAGE_INCLUDES, "merge-extra": True}
    assert "canasta" not in effective["extra"]

    result, ran = inst.start()
    assert not ran

    _write_json(inst.config, {"config": {"platform": {"php": "8.3.0"}}})
    result, ran = inst.start()
    assert ran, "a changed config key must rerun composer"
    assert inst.effective()["config"]["platform"]["php"] == "8.3.0"
    assert "minimum-stability" not in inst.effective()


def test_extra_canasta_not_passed_to_composer(inst):
    _write_json(inst.config, {"extra": {"canasta": {"exclude-bundled": [
        "extensions/Bar/composer.json"]}}})
    inst.start()
    assert "canasta" not in inst.effective()["extra"]


def test_old_copy_with_empty_keys_is_no_operator_content(inst):
    _write_json(inst.config, {
        "require": {},
        "extra": {"merge-plugin": {"include": IMAGE_INCLUDES}},
    })
    result, ran = inst.start()
    assert not ran
    assert inst.effective() == {
        "extra": {"merge-plugin": {"include": IMAGE_INCLUDES}}}


@pytest.mark.parametrize("text", [
    '{"require": {"some/package": "^1.0"},}',
    '[{"require": {"some/package": "^1.0"}}]',
])
def test_unparsable_operator_file_leaves_vendor_alone(inst, text):
    _write_json(inst.config, {"require": {"some/package": "^1.0"}})
    result, ran = inst.start()
    assert ran
    effective = (inst.mw_home / "composer.local.json").read_text()
    saved_hash = (inst.mw_home / ".composer-deps-hash").read_text()

    inst.config.write_text(text)
    result, ran = inst.start()
    assert result.returncode == 3
    assert not ran, "composer must not run without the operator's content"
    assert (inst.mw_home / "composer.local.json").read_text() == effective
    assert (inst.mw_home / ".composer-deps-hash").read_text() == saved_hash
    failed = inst.failed.read_text()
    assert "(exit 3)" in failed
    assert "config/composer.local.json could not be parsed" in failed
    assert str(inst.config) in failed

    _write_json(inst.config, {"require": {"some/package": "^1.0"}})
    result, ran = inst.start()
    assert not ran
    assert not inst.failed.exists()


def test_run_all_continues_after_composer_failure():
    with open(os.path.join(SCRIPTS, "run-all.sh")) as f:
        content = f.read()
    assert not re.search(r"^\s*set\s+-[a-z]*e", content, re.MULTILINE)
    assert re.search(r"^/update-composer-deps\.sh$", content, re.MULTILINE)


@pytest.mark.parametrize("failure", [
    {"STUB_EXIT": "2"},
    {"STUB_INSTALLED": json.dumps({"packages": [{"name": "foo/lib"}]})},
], ids=["composer", "verify"])
def test_failure_then_revert_reruns_composer(inst, failure):
    _write_json(inst.config, {"require": {"some/package": "^1.0"}})
    result, ran = inst.start()
    assert ran
    hash_file = inst.mw_home / ".composer-deps-hash"
    saved_hash = hash_file.read_text()

    # An include is added, the update fails, and the include is reverted.
    inst.user_extension("Mine", {"require": {"mine/lib": "^2"}})
    _write_json(inst.config, {
        "require": {"some/package": "^1.0"},
        "extra": {"merge-plugin": {"include": ["extensions/Mine/composer.json"]}},
    })
    result, ran = inst.start(**failure)
    assert ran
    assert inst.failed.exists()
    assert not hash_file.exists()

    _write_json(inst.config, {"require": {"some/package": "^1.0"}})
    complete = json.dumps({"packages": [
        {"name": n} for n in ("foo/lib", "bar/lib", "some/package")]})
    result, ran = inst.start(STUB_INSTALLED=complete)
    assert ran, "vendor/ may be half-updated, so composer must rerun"
    assert not inst.failed.exists()
    assert hash_file.read_text() == saved_hash


def test_build_hash_kept_on_success_and_skip(inst):
    hash_file = inst.mw_home / ".composer-deps-hash"
    baseline = hash_file.read_text()
    result, ran = inst.start()
    assert not ran
    assert hash_file.read_text() == baseline


def test_exit_code_passes_through(inst):
    _write_json(inst.config, {"require": {"some/package": "^1.0"}})
    result, ran = inst.start(STUB_EXIT="2")
    assert ran
    assert result.returncode == 2

    installed = json.dumps({"packages": [{"name": "foo/lib"}]})
    result, ran = inst.start(STUB_INSTALLED=installed)
    assert ran
    assert result.returncode == 1, "verify-composer-deps.php exits 1"

    complete = json.dumps({"packages": [
        {"name": n} for n in ("foo/lib", "bar/lib", "some/package")]})
    result, ran = inst.start(STUB_INSTALLED=complete)
    assert ran
    assert result.returncode == 0

    result, ran = inst.start()
    assert not ran
    assert result.returncode == 0
