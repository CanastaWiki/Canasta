"""Tests for run-all.sh composer logic and run-maintenance-scripts.sh
source-vs-execute behavior.

These cover the bugs fixed for #141 / #143:
- Bug A: composer hash file used to be written to a path whose parent
  directory ($MW_VOLUME/config/persistent) didn't exist on first run,
  so the redirect failed silently and the hash was never saved →
  composer ran on every start.
- Bug B: composer hash file used to live on $MW_VOLUME (bind-mounted,
  persistent) while vendor/ lives in $MW_HOME (intra-container,
  ephemeral). After `docker compose up --force-recreate`, vendor/ was
  wiped but the hash persisted, so the script skipped composer with a
  matching hash and missing deps.
- Bug C: run-all.sh sources run-maintenance-scripts.sh to load helper
  functions, but the file had executable code at the bottom (the
  "Run maintenance scripts" entry point block) that fired as a side
  effect of sourcing, racing the explicit invocations elsewhere.
"""

import os
import re
import subprocess
import textwrap

import pytest


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ))
RMS_SCRIPT = os.path.join(
    REPO_ROOT, "_sources", "scripts", "run-maintenance-scripts.sh",
)


# ---------------------------------------------------------------------------
# Bug C: run-maintenance-scripts.sh source-vs-execute guard
# ---------------------------------------------------------------------------


def _run_under_stub_env(snippet, mw_volume, www_root, has_config=True,
                        autoupdate=False):
    """Run a bash snippet with stub helper functions and a fake canasta
    filesystem layout. Returns CompletedProcess.

    The snippet is wrapped with stubs for the helper functions that
    run-maintenance-scripts.sh's top-of-file expects, plus a stub for
    isFalse / isTrue / etc. so the script's tail can run without
    /functions.sh being present.
    """
    os.makedirs(os.path.join(mw_volume, "config"), exist_ok=True)
    os.makedirs(www_root, exist_ok=True)
    if has_config:
        # Touch wikis.yaml so the entry-point block sees a config
        open(os.path.join(mw_volume, "config", "wikis.yaml"), "w").close()
    open(os.path.join(www_root, ".maintenance"), "w").close()

    wrapped = textwrap.dedent("""
        export MW_VOLUME=%(mw_volume)s
        export WWW_ROOT=%(www_root)s
        export MW_AUTOUPDATE=%(autoupdate)s
        export USE_EXTERNAL_DB=true   # short-circuit waitdatabase
        export WG_DB_TYPE=mysql

        # Stub helpers normally provided by /functions.sh and elsewhere
        isFalse() { [ "$1" = "false" ]; }
        isTrue() { [ "$1" = "true" ]; }
        get_mediawiki_db_var() { echo ""; }
        get_mediawiki_variable() { echo ""; }

        # Trace markers — the test asserts on which of these print.
        run_autoupdate() { echo "STUB:run_autoupdate"; }
        run_maintenance_scripts() { echo "STUB:run_maintenance_scripts"; }
        waitdatabase() { echo "STUB:waitdatabase"; return 0; }

        %(snippet)s
    """) % {
        "mw_volume": mw_volume,
        "www_root": www_root,
        "autoupdate": "true" if autoupdate else "false",
        "snippet": snippet,
    }
    return subprocess.run(
        ["bash", "-c", wrapped],
        capture_output=True, text=True,
    )


class TestSourceVsExecuteGuard:
    """Bug C — sourcing the script must not execute the entry point."""

    def test_sourcing_does_not_run_entry_point(self, tmp_path):
        snippet = ". %s" % RMS_SCRIPT
        result = _run_under_stub_env(
            snippet,
            mw_volume=str(tmp_path / "mediawiki"),
            www_root=str(tmp_path / "www"),
        )
        # If the entry point fired, it would print "Checking for
        # configuration..." and call our stub run_maintenance_scripts,
        # which prints STUB:run_maintenance_scripts. Neither should
        # appear when only sourced.
        assert "Checking for configuration" not in result.stdout, (
            "sourcing fired entry point:\n%s" % result.stdout
        )
        assert "STUB:run_maintenance_scripts" not in result.stdout
        assert "STUB:run_autoupdate" not in result.stdout

    def test_sourcing_still_defines_helper_functions(self, tmp_path):
        snippet = (
            ". %s\n"
            "type waitdatabase >/dev/null && echo HAS:waitdatabase\n"
            "type run_maintenance_script_if_needed >/dev/null "
            "&& echo HAS:run_maintenance_script_if_needed\n"
        ) % RMS_SCRIPT
        result = _run_under_stub_env(
            snippet,
            mw_volume=str(tmp_path / "mediawiki"),
            www_root=str(tmp_path / "www"),
        )
        # The stub-overridden run_autoupdate / waitdatabase / etc. are
        # defined in our wrapper before the source, so the source's
        # function definitions overwrite them. After sourcing the
        # helpers should still resolve to the script's definitions.
        # We're really just confirming that the source returned cleanly
        # and the function table is intact.
        assert "HAS:waitdatabase" in result.stdout
        assert "HAS:run_maintenance_script_if_needed" in result.stdout

    def test_executing_script_fires_entry_point(self, tmp_path):
        # When run as a child process (not sourced), the entry point
        # block must still fire. We use MW_AUTOUPDATE=false so the
        # script just prints "Auto update script is disabled" and
        # then calls run_maintenance_scripts (our stub).
        env = os.environ.copy()
        mw_volume = tmp_path / "mediawiki"
        www_root = tmp_path / "www"
        (mw_volume / "config").mkdir(parents=True)
        www_root.mkdir()
        (mw_volume / "config" / "wikis.yaml").touch()
        (www_root / ".maintenance").touch()
        env.update({
            "MW_VOLUME": str(mw_volume),
            "WWW_ROOT": str(www_root),
            "MW_AUTOUPDATE": "false",
            "USE_EXTERNAL_DB": "true",
            "WG_DB_TYPE": "mysql",
        })
        # Inject stubs via a wrapper bash that pre-defines functions,
        # then EXECUTES (not sources) the script.
        wrapper = textwrap.dedent("""
            isFalse() { [ "$1" = "false" ]; }
            isTrue() { [ "$1" = "true" ]; }
            get_mediawiki_db_var() { echo ""; }
            get_mediawiki_variable() { echo ""; }
            export -f isFalse isTrue get_mediawiki_db_var get_mediawiki_variable
            bash %s
        """) % RMS_SCRIPT
        result = subprocess.run(
            ["bash", "-c", wrapper],
            env=env,
            capture_output=True, text=True,
        )
        # When EXECUTED, the entry point should fire — we should see
        # the "Checking for configuration..." prologue.
        assert "Checking for configuration" in result.stdout, (
            "expected entry point to fire when executed directly:\n"
            "stdout=%s\nstderr=%s" % (result.stdout, result.stderr)
        )


# ---------------------------------------------------------------------------
# Bugs A + B: composer hash file location
# ---------------------------------------------------------------------------


class TestComposerHashFileLocation:
    """Bugs A + B — the hash file path is read from `run-all.sh` and
    must be inside the container ($MW_HOME), not on the bind mount
    ($MW_VOLUME/config/persistent)."""

    def test_startup_writes_hash_inside_container(self):
        """The hash file path must be under $MW_HOME, not $MW_VOLUME."""
        with open(os.path.join(
            REPO_ROOT, "_sources", "scripts", "update-composer-deps.sh",
        )) as f:
            content = f.read()

        # The composer script defines a single source-of-truth variable
        # for the hash file path. It must point at $MW_HOME, not at
        # the bind-mounted $MW_VOLUME/config/persistent location.
        assert 'COMPOSER_HASH_FILE="$MW_HOME/.composer-deps-hash"' in content, (
            "expected COMPOSER_HASH_FILE to be under $MW_HOME (intra-container)"
        )
        assert "$MW_VOLUME/config/persistent/.composer-deps-hash" not in content, (
            "composer script must not write to the bind-mounted path "
            "anymore (#141)"
        )

    def test_run_all_runs_composer_update(self):
        with open(os.path.join(
            REPO_ROOT, "_sources", "scripts", "run-all.sh",
        )) as f:
            content = f.read()
        assert re.search(r"^/update-composer-deps\.sh$", content, re.MULTILINE)

    def test_extensions_skins_writes_baseline_inside_container(self):
        """The build-time baseline written by extensions-skins.php must
        also live at $MW_HOME/.composer-deps-hash so it shares the same
        lifetime as vendor/."""
        with open(os.path.join(
            REPO_ROOT, "_sources", "scripts", "extensions-skins.php",
        )) as f:
            content = f.read()
        assert (
            'file_put_contents("$MW_HOME/.composer-deps-hash"' in content
        ), "build-time baseline should be written under $MW_HOME"
        # Old bind-mount baseline path must be gone.
        assert (
            "$MW_ORIGIN_FILES/config/persistent/.composer-deps-hash"
            not in content
        ), "build-time baseline must not write to $MW_ORIGIN_FILES anymore"


class TestPersistentDirWritableBeforeAutoupdate:
    """#172 — config/persistent must be made writable by the web user
    *before* run_autoupdate, so setupStore.php (invoked by update.php) can
    persist .smw.json. The make_dir_writable on the writable volume dirs runs
    later and in the background, too late to help SMW on the current start."""

    def test_persistent_healed_before_run_autoupdate(self):
        with open(os.path.join(
            REPO_ROOT, "_sources", "scripts", "run-all.sh",
        )) as f:
            content = f.read()

        heal = content.find('make_dir_writable "$MW_VOLUME/config/persistent"')
        assert heal != -1, (
            "expected a targeted make_dir_writable on $MW_VOLUME/config/persistent"
        )

        # Match the call line itself, not the surrounding comments that
        # also mention run_autoupdate.
        call = re.search(r"^\s*run_autoupdate\s*$", content, re.MULTILINE)
        assert call is not None, "run_autoupdate call should exist"
        assert heal < call.start(), (
            "config/persistent must be healed before run_autoupdate, not after"
        )


# ---------------------------------------------------------------------------
# monitor-directories.sh: live extension/skin symlink maintenance
# ---------------------------------------------------------------------------


MONITOR_SCRIPT = os.path.join(
    REPO_ROOT, "_sources", "scripts", "maintenance-scripts",
    "monitor-directories.sh",
)


def _handle_events(events, user_dir, link_dir, canonical_dir):
    """Source monitor-directories.sh and feed synthetic inotify event
    lines ("event:file", as produced by --format '%e:%f') to its
    handle_dir_events function. Sourcing returns early via the
    BASH_SOURCE guard, so no real inotifywait runs. The missing
    /functions.sh is harmless (the script has no `set -e`)."""
    snippet = textwrap.dedent("""
        . %(script)s >/dev/null 2>&1
        set +x
        printf '%%s\\n' %(events)s \
            | handle_dir_events "%(user)s" "%(link)s" "%(canon)s"
    """) % {
        "script": MONITOR_SCRIPT,
        "events": " ".join("'%s'" % e for e in events),
        "user": user_dir,
        "link": link_dir,
        "canon": canonical_dir,
    }
    return subprocess.run(
        ["bash", "-c", snippet], capture_output=True, text=True,
    )


class TestMonitorDirectories:
    """handle_dir_events must maintain symlinks based on a stat of the
    source path, NOT on inotify's ISDIR flag. Docker Desktop on macOS
    strips ISDIR from host-side bind-mount events, so a directory create
    arrives as a bare CREATE; the watcher must still link it."""

    def _layout(self, tmp_path):
        user = tmp_path / "user-extensions"
        link = tmp_path / "extensions"
        canon = tmp_path / "canasta-extensions"
        for d in (user, link, canon):
            d.mkdir()
        return user, link, canon

    def test_bare_create_links_directory(self, tmp_path):
        """The macOS case: CREATE without ISDIR still links a dir."""
        user, link, canon = self._layout(tmp_path)
        (user / "MyExt").mkdir()
        _handle_events(["CREATE:MyExt"], user, link, canon)
        target = link / "MyExt"
        assert target.is_symlink(), "bare CREATE did not create the symlink"
        assert os.path.realpath(target) == str(user / "MyExt")

    def test_isdir_create_links_directory(self, tmp_path):
        """The Linux case stays working: CREATE,ISDIR links a dir."""
        user, link, canon = self._layout(tmp_path)
        (user / "MyExt").mkdir()
        _handle_events(["CREATE,ISDIR:MyExt"], user, link, canon)
        assert (link / "MyExt").is_symlink()

    def test_moved_to_links_directory(self, tmp_path):
        """MOVED_TO (with or without ISDIR) behaves like CREATE."""
        user, link, canon = self._layout(tmp_path)
        (user / "MyExt").mkdir()
        _handle_events(["MOVED_TO:MyExt"], user, link, canon)
        assert (link / "MyExt").is_symlink()

    def test_create_ignores_plain_file(self, tmp_path):
        """A non-directory entry must never be symlinked (e.g. .gitkeep)."""
        user, link, canon = self._layout(tmp_path)
        (user / "README").write_text("x")
        _handle_events(["CREATE:README"], user, link, canon)
        assert not (link / "README").exists(), (
            "a plain file should not be linked into extensions/"
        )

    def test_delete_reverts_to_bundled(self, tmp_path):
        """Removing a user dir that shadows a bundled one reverts the
        link to the bundled copy."""
        user, link, canon = self._layout(tmp_path)
        (canon / "MyExt").mkdir()
        # Pre-existing user override link, now the source is gone.
        (link / "MyExt").symlink_to(user / "MyExt")
        _handle_events(["DELETE:MyExt"], user, link, canon)
        target = link / "MyExt"
        assert target.is_symlink()
        assert os.path.realpath(target) == str(canon / "MyExt"), (
            "delete should revert the link to the bundled extension"
        )

    def test_delete_removes_link_when_no_bundled(self, tmp_path):
        """Removing a purely-custom user dir removes the dangling link."""
        user, link, canon = self._layout(tmp_path)
        (link / "MyExt").symlink_to(user / "MyExt")
        _handle_events(["DELETE:MyExt"], user, link, canon)
        assert not (link / "MyExt").exists() and \
            not (link / "MyExt").is_symlink(), (
            "delete with no bundled copy should remove the link"
        )

    def test_delete_leaves_unmanaged_entry_alone(self, tmp_path):
        """A delete event must not clobber a real (non-symlink) entry we
        did not create."""
        user, link, canon = self._layout(tmp_path)
        real = link / "Keep"
        real.mkdir()
        (real / "marker").write_text("x")
        _handle_events(["DELETE:Keep"], user, link, canon)
        assert real.is_dir() and (real / "marker").exists(), (
            "delete must not touch an unmanaged real directory"
        )

    def test_sourcing_does_not_launch_watchers(self, tmp_path):
        """Sourcing the script (for its functions) must not start
        inotifywait — the BASH_SOURCE guard returns first."""
        result = subprocess.run(
            ["bash", "-c",
             ". %s >/dev/null 2>&1; type handle_dir_events >/dev/null "
             "&& echo HAS:handle_dir_events" % MONITOR_SCRIPT],
            capture_output=True, text=True,
        )
        assert "HAS:handle_dir_events" in result.stdout


# ---------------------------------------------------------------------------
# Apache receives the container's stop signal
# ---------------------------------------------------------------------------


def test_run_all_execs_apache2_directly():
    """apachectl runs apache2 as a child of its shell, which would stay
    PID 1 and swallow the stop signal."""
    with open(os.path.join(REPO_ROOT, "_sources", "scripts", "run-all.sh")) as f:
        lines = [l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")]
    assert lines[-1] == "exec /usr/sbin/apache2 -DFOREGROUND"
    assert ". /etc/apache2/envvars" in lines


def test_dockerfile_stop_signal_is_graceful():
    with open(os.path.join(REPO_ROOT, "Dockerfile")) as f:
        directives = [l.split() for l in f if l.startswith("STOPSIGNAL")]
    assert directives == [["STOPSIGNAL", "SIGWINCH"]]
