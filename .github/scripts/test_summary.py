#!/usr/bin/env python3
"""Parse Maven Surefire XML results and write a GitHub Step Summary.

Usage: python3 test_summary.py [surefire-reports-dir]
"""
import glob, os, sys, xml.etree.ElementTree as ET

def main():
    reports_dir = sys.argv[1] if len(sys.argv) > 1 else "target/surefire-reports"
    total = errors = failures = skipped = 0
    failed_cases = []
    for f in glob.glob(reports_dir + "/TEST-*.xml"):
        try:
            tree = ET.parse(f)
            root = tree.getroot()
            total    += int(root.get("tests", 0))
            errors   += int(root.get("errors", 0))
            failures += int(root.get("failures", 0))
            skipped  += int(root.get("skipped", 0))
            for tc in root.findall(".//testcase"):
                if tc.find("failure") is not None or tc.find("error") is not None:
                    failed_cases.append(root.get("name","?") + "." + tc.get("name","?"))
        except Exception:
            pass

    passed = total - errors - failures - skipped
    status = "All tests passed" if (errors + failures) == 0 else "Test failures detected"

    lines = ["## Build and Test Results", "",
        "| Metric  | Count |", "|---|---|",
        "| Passed  | " + str(passed)            + " |",
        "| Failed  | " + str(failures + errors) + " |",
        "| Skipped | " + str(skipped)           + " |",
        "| Total   | " + str(total)             + " |",
        "", "**" + status + "**", ""]
    if failed_cases:
        lines += ["", "### Failed Tests", "| Test |", "|---|"]
        for fc in failed_cases[:10]:
            lines.append("| " + fc + " |")

    sep = chr(10)
    body = sep.join(lines) + sep
    sf = os.environ.get("GITHUB_STEP_SUMMARY")
    if sf:
        with open(sf, "a") as fh: fh.write(body)
    else:
        print(body)

if __name__ == "__main__":
    main()
