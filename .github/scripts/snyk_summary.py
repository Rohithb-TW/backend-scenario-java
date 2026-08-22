#!/usr/bin/env python3
"""Parse Snyk JSON report and write a GitHub Step Summary.

Usage: python3 snyk_summary.py <report.json> <label> <snyk_exit_code>
"""
import json, os, sys

def main():
    report_file = sys.argv[1] if len(sys.argv) > 1 else "snyk-report.json"
    label = sys.argv[2] if len(sys.argv) > 2 else ""
    exit_code = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    try:
        with open(report_file) as f:
            data = json.load(f)
        vulns = data.get("vulnerabilities", [])
    except Exception:
        vulns = []

    crit = [v for v in vulns if v.get("severity") == "critical"]
    high = [v for v in vulns if v.get("severity") == "high"]
    blocked = bool(crit or high)

    rows = []
    for v in (crit + high)[:20]:
        rows.append(
            "| " + v.get("severity","?").upper()
            + " | " + v.get("packageName","?")
            + " | " + v.get("id","?")
            + " | " + v.get("title","?") + " |"
        )

    verdict = (
        "BLOCKED: Critical/High CVEs detected. Deployment halted."
        if blocked else "PASS: No Critical/High vulnerabilities found."
    )
    title = "## Snyk SCA Gate"
    if label:
        title += " -- " + label

    lines = [title, "",
        "| Severity | Count |", "|---|---|",
        "| Critical | " + str(len(crit)) + " |",
        "| High     | " + str(len(high)) + " |",
        "", verdict, ""]
    if rows:
        lines += ["", "### Top findings",
                  "| Severity | Package | CVE | Title |", "|---|---|---|---|"]
        lines.extend(rows)

    sep = chr(10)
    body = sep.join(lines) + sep
    sf = os.environ.get("GITHUB_STEP_SUMMARY")
    if sf:
        with open(sf, "a") as fh: fh.write(body)
    else:
        print(body)
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
