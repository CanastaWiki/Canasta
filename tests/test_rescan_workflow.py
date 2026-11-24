"""Regression tests for the scheduled published-image rescan."""

import json
import subprocess
from pathlib import Path


WORKFLOW = (
    Path(__file__).resolve().parents[1]
    / ".github"
    / "workflows"
    / "rescan-published-images.yml"
).read_text()
PER_IMAGE_JQ = "[.Results[]?.Vulnerabilities[]?.VulnerabilityID] | unique | length"
TOTAL_PIPELINE = "cut -f4 | sort -u | sed '/^$/d' | wc -l | tr -d ' '"


def test_one_cve_many_packages_counts_once_per_image():
    trivy = {
        "Results": [
            {
                "Vulnerabilities": [
                    {"VulnerabilityID": "CVE-1", "PkgName": package}
                    for package in [
                        "libmariadb3",
                        "mariadb-client",
                        "mariadb-client-core",
                        "mariadb-common",
                    ]
                ]
            }
        ]
    }

    result = subprocess.run(
        ["jq", PER_IMAGE_JQ],
        input=json.dumps(trivy),
        capture_output=True,
        text=True,
        check=True,
    )

    assert result.stdout.strip() == "1"
    assert f"COUNT=$(jq '{PER_IMAGE_JQ}' \"$RESULT\")" in WORKFLOW


def test_total_collapses_across_packages_and_arches():
    findings = "".join(
        f"{digest}\t{arch}\tHIGH\tCVE-1\t{package}\t1\t2\n"
        for digest, arch in [("sha256:a", "amd64"), ("sha256:b", "arm64")]
        for package in [
            "libmariadb3",
            "mariadb-client",
            "mariadb-client-core",
            "mariadb-common",
        ]
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
        'TOTAL=$(cut -f4 "$FINDINGS" | sort -u | sed \'/^$/d\' '
        "| wc -l | tr -d ' ')"
    ) in WORKFLOW
    assert "TOTAL=$((TOTAL + COUNT))" not in WORKFLOW


def test_rescan_report_labels_counts_as_cves():
    assert (
        "Trivy found **$TOTAL** distinct fixable HIGH/CRITICAL CVEs "
        "across the published images."
    ) in WORKFLOW
    assert "| Tag | Platform | CVEs |" in WORKFLOW
