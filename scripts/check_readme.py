#!/usr/bin/env python3
"""Local English prose check. The score counts style patterns, not authorship."""
import argparse
import hashlib
import json
import re
from pathlib import Path

PATTERNS = {
    "marketing_filler": r"\b(?:seamless(?:ly)?|effortless(?:ly)?|game[- ]chang(?:er|ing)|cutting[- ]edge|revolutionary|supercharge|unleash|unlock|best[- ]in[- ]class|unparalleled)\b",
    "generic_setup": r"\b(?:in today's (?:world|fast[- ]paced)|in the digital age|look no further|it(?:'s| is) worth noting|at its core|at the heart of|delve into|let's dive in)\b",
    "canned_ending": r"\b(?:in conclusion|in summary|the possibilities are endless|take it to the next level|embrace the future)\b",
    "formulaic_reframe": r"\b(?:not just|more than just)\b[^.!?\n]{0,100}\bbut\b",
}


def check(text):
    # Code, tables, and image markup are not prose.
    lines = []
    in_code = False
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            in_code = not in_code
            continue
        if in_code or line.lstrip().startswith(("|", "<", "![")):
            continue
        line = re.sub(r"`[^`]*`", "", line)
        line = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", line)
        lines.append((number, line))
    findings = []
    for number, line in lines:
        for name, pattern in PATTERNS.items():
            for match in re.finditer(pattern, line, re.IGNORECASE):
                findings.append({"line": number, "pattern": name, "text": match.group()})
    return {
        "style_penalty_out_of_100": min(100, len(findings) * 10),
        "rubric": "10 points per configured phrase match, capped at 100; lower is better.",
        "findings": findings,
        "word_count": len(re.findall(r"\b[\w'-]+\b", "\n".join(line for _, line in lines))),
        "sha256": hashlib.sha256(text.encode()).hexdigest(),
        "limitation": "A phrase linter, not an AI-authorship detector. Review facts and voice separately.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    args = parser.parse_args()
    print(json.dumps(check(args.file.read_text()), indent=2))
