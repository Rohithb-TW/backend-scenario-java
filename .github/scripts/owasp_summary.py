#!/usr/bin/env python3
"""Parse OWASP Dependency-Check JSON report and write a GitHub Step Summary.

Usage: python3 owasp_summary.py <report.json> [label] [exit_code]
"""
import json, os, sys

def main():
    report_file = sys.argv[1] if len(sys.argv) > 1 else "target/dependency-check-report.json"
    label = sys.argv[2] if len(sys.argv) > 2 else ""
    exit_code = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    deps, crit, high, rows = 0, 0, 0, []
    try:
        with open(report_file) as f:
            data = json.load(f)
        for dep in data.get("dependencies", []):
            vulns = dep.get("vulnerabilities", [])
            if vulns: deps += 1
            for v in vulns:
                score = (v.get("cvssv3",{}).get("baseScore",0)
                         or v.get("cvssv2",{}).get("score",0))
                if score >= 9:   crit += 1
                elif score >= 7: high += 1
                if score >= 7 and len(rows) < 15:
                    sl = "CRITICAL" if score >= 9 else "HIGH"
                    rows.append(
                        "| " + sl
                        + " | " + dep.get("fileName","?")
                        + " | " + v.get("name","?")
                        + " | " + str(score)
                        + " | " + v.get("description","?")[:60] + " |"
                    )
    except Exception as exc:
        print("Warning: " + str(exc), file=sys.stderr)

    blocked = exit_code != 0
    verdict = ("MERGE BLOCKED: High/Critical CVSS vulns found." if blocked
               else "PASS: No High/Critical CVSS vulns.")
    title = "## OWASP Dependency-Check"
    if label: title += " -- " + label

    lines = [title, "",
        "| Metric | Count |", "|---|---|",
        "| Affected deps    | " + str(deps)  + " |",
        "| Critical CVSS>=9 | " + str(crit)  + " |",
        "| High CVSS 7-8.9  | " + str(high)  + " |",
        "", verdict, ""]
    if rows:
        lines += ["", "### Findings",
                  "| Severity | Package | CVE | CVSS | Description |",
                  "|---|---|---|---|---|"]
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
