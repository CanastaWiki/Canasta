"""make_dir_writable in functions.sh, which fixes group write access on the
volume directories at every container start."""

import os
import subprocess


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FUNCTIONS = os.path.join(REPO_ROOT, "_sources", "scripts", "functions.sh")


def test_batches_files_into_one_chgrp_and_chmod(tmp_path):
    tree = tmp_path / "images"
    (tree / "a").mkdir(parents=True)
    for name in ("one.png", "two.png", "a/three.png"):
        (tree / name).write_bytes(b"")
        (tree / name).chmod(0o444)
    bindir = tmp_path / "bin"
    bindir.mkdir()
    log = tmp_path / "calls.log"
    for cmd in ("chgrp", "chmod"):
        (bindir / cmd).write_text(
            '#!/bin/sh\necho "%s $#" >> "$CALL_LOG"\n' % cmd)
        (bindir / cmd).chmod(0o755)
    # Numeric IDs nobody has, so every file needs fixing.
    env = dict(os.environ, WWW_USER="99998", WWW_GROUP="99999",
               CALL_LOG=str(log),
               PATH=str(bindir) + os.pathsep + os.environ["PATH"])
    result = subprocess.run(
        ["bash", "-c", '. "%s"; make_dir_writable "%s"' % (FUNCTIONS, tree)],
        env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    # tree, a/, and three files: two arguments for chgrp/chmod plus five paths.
    assert sorted(log.read_text().splitlines()) == ["chgrp 6", "chmod 6"]
