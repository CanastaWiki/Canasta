"""Regression tests for the scheduled published-image rescan."""

import json
import re
import subprocess
from pathlib import Path


WORKFLOW = (
    Path(__file__).resolve().parents[1]
    / ".github"
    / "workflows"
    / "rescan-published-images.yml"
).read_text()
TOTAL_PIPELINE = "cut -f4 | sort -u | sed '/^$/d' | wc -l | tr -d ' '"
MARIADB_PACKAGES = [
    "libmariadb3",
    "mariadb-client",
    "mariadb-client-core",
    "mariadb-common",
]


def per_image_count_jq():
    match = re.search(r"COUNT=\$\(jq '(.*?)' \"\$RESULT\"\)", WORKFLOW, re.S)
    assert match, "per-image COUNT jq not found in the workflow"
    return match.group(1)


def test_both_images_are_scanned_with_their_own_tracker():
    assert "- image: canasta-base" in WORKFLOW
    assert "- image: canasta\n" in WORKFLOW
    assert "issue_title: Scheduled canasta-base image vulnerability scan" in WORKFLOW
    assert "issue_title: Scheduled canasta image vulnerability scan" in WORKFLOW


def test_one_cve_many_packages_counts_once_per_image():
    trivy = {
        "Results": [
            {
                "Vulnerabilities": [
                    {"VulnerabilityID": "CVE-1", "PkgName": package, "FixedVersion": "2"}
                    for package in MARIADB_PACKAGES
                ]
                + [{"VulnerabilityID": "CVE-2", "PkgName": "libfoo"}]
            }
        ]
    }

    result = subprocess.run(
        ["jq", per_image_count_jq()],
        input=json.dumps(trivy),
        capture_output=True,
        text=True,
        check=True,
    )

    assert result.stdout.strip() == "1"


def test_total_collapses_across_packages_and_arches():
    findings = "".join(
        f"{digest}\t{arch}\tHIGH\tCVE-1\t{package}\t1\t2\n"
        for digest, arch in [("sha256:a", "amd64"), ("sha256:b", "arm64")]
        for package in MARIADB_PACKAGES
    )

    result = subprocess.run(
        ["bash", "-o", "pipefail", "-c", TOTAL_PIPELINE],
        input=findings,
        capture_output=True,
        text=True,
        check=True,
    )

    assert result.stdout.strip() == "1"
    assert (
        'TOTAL=$(cut -f4 "$FIXABLE" | sort -u | sed \'/^$/d\' '
        "| wc -l | tr -d ' ')"
    ) in WORKFLOW
    assert "TOTAL=$((TOTAL + COUNT))" not in WORKFLOW


def test_rescan_report_labels_counts_as_cves():
    assert (
        "Trivy found **$TOTAL** distinct fixable HIGH/CRITICAL CVEs "
        "across the published images."
    ) in WORKFLOW
    assert "| Tag | Platform | Distinct fixable CVEs |" in WORKFLOW
