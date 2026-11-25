"""Both images write /tmp/canasta-version from VERSION: line 1 is the label
Special:Version shows, line 2 the version `canasta version` reads. The canasta
image is built on canasta-base and writes its own label over the file."""

import os
import re

import pytest


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def version_file_writer(dockerfile):
    with open(os.path.join(REPO_ROOT, dockerfile)) as f:
        source = f.read()
    assert re.search(r"^COPY VERSION /tmp/$", source, re.M), dockerfile
    match = re.search(
        r"^RUN printf '%s\\n%s\\n' '(\[[^']*\])' \"\$\(cat /tmp/VERSION\)\""
        r" > /tmp/canasta-version && rm /tmp/VERSION$",
        source, re.M)
    assert match, dockerfile
    return match.group(1)


@pytest.mark.parametrize("dockerfile,label", [
    ("Dockerfile", "[https://canasta.wiki/ Canasta (base)]"),
    ("Dockerfile.canasta", "[https://canasta.wiki/ Canasta]"),
])
def test_image_writes_version_file(dockerfile, label):
    assert version_file_writer(dockerfile) == label
