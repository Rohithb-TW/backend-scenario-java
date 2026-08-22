#!/usr/bin/env python3
"""Parse Trivy JSON report and write a GitHub Step Summary.

Usage: python3 trivy_summary.py <report.json> [label]
"""
import json, os, sys

def main():
    report_file = sys.argv[1] if len(sys.argv) > 1 else "trivy.json"
    label = sys.argv[2] if len(sys.argv) > 2 else ""
    crit, high, rows = 0, 0, []
    try:
        with open(report_file) as f:
            data = json.load(f)
        for r in data.get("Results", []):
            for v in r.get("Vulnerabilities") or []:
                sev = v.get("Severity", "")
                if sev == "CRITICAL": crit += 1
                elif sev == "HIGH":   high += 1
                if sev in ("CRITICAL","HIGH") and len(rows) < 20:
                    rows.append(
                        "| " + sev
                        + " | " + v.get("PkgName","?")
                        + " | " + v.get("VulnerabilityID","?")
                        + " | " + v.get("Title","?")[:60] + " |"
                    )
    except Exception as exc:
        print("Warning: " + str(exc), file=sys.stderr)

    blocked = crit > 0 or high > 0
    verdict = "BLOCKED: fix image CVEs." if blocked else "PASS: Image is clean."
    title = "## Trivy Image Scan"
    if label: title += " -- " + label

    lines = [title, "",
        "| Severity | Count |", "|---|---|",
        "| Critical | " + str(crit) + " |",
        "| High     | " + str(high) + " |",
        "", verdict, ""]
    if rows:
        lines += ["", "### Findings",
                  "| Severity | Package | CVE | Title |", "|---|---|---|---|"]
        lines.extend(rows)

    sep = chr(10)
    body = sep.join(lines) + sep
    sf = os.environ.get("GITHUB_STEP_SUMMARY")
    if sf:
        with open(sf, "a") as fh: fh.write(body)
    else:
        print(body)

if __name__ == "__main__":
    main()
