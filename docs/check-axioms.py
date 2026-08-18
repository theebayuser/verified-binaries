#!/usr/bin/env python3
"""Check the output of docs/axiom-audit.lean.

The rule this enforces: every universal statement in the repository depends on
Lean's standard axioms only. A `native_decide` dependency is allowed exactly
for the concrete per-input regressions, which live in `Smoke.lean` and
`Equivalence.lean` and are never used to prove anything universal.

Grepping the log for a marker string does not work. Lean does not print
`Lean.ofReduceBool` here: a `native_decide` dependency shows up as a generated
axiom named `<theorem>._native.native_decide.ax_1_1`, and the pretty printer
wraps long axiom lists across lines, so line-oriented matching also mis-attributes
axioms to the wrong theorem. This parses whole records instead.

Usage: check-axioms.py <axioms.log> [expected-record-count]
"""

import re
import sys

STANDARD = {"propext", "Classical.choice", "Quot.sound"}

# Theorems allowed to carry a native_decide axiom, by module.
NATIVE_OK = re.compile(r"\.(Smoke|Equivalence)\.")

RECORD = re.compile(r"'([^']+)' depends on axioms: \[([^\]]*)\]", re.S)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: check-axioms.py <axioms.log> [expected-record-count]")
        return 2

    text = open(sys.argv[1], encoding="utf-8").read()
    records = RECORD.findall(text)

    if not records:
        print("no '#print axioms' records found; the audit did not run")
        return 1

    if len(sys.argv) > 2:
        expected = int(sys.argv[2])
        if len(records) != expected:
            print(f"expected {expected} audited theorems, found {len(records)}")
            return 1

    failures = []
    for name, axioms in records:
        found = {a.strip() for a in axioms.split(",") if a.strip()}
        extra = found - STANDARD
        if extra and not NATIVE_OK.search(name):
            failures.append((name, sorted(extra)))

    if failures:
        for name, extra in failures:
            print(f"non-standard axioms for {name}: {', '.join(extra)}")
        return 1

    audited = len(records)
    native = sum(1 for name, ax in records if {a.strip() for a in ax.split(",")} - STANDARD)
    print(f"axiom audit ok: {audited} theorems, {audited - native} on standard axioms only, "
          f"{native} quarantined native_decide regressions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
