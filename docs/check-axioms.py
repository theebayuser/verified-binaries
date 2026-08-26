#!/usr/bin/env python3
"""Check the output of docs/axiom-audit.lean.

The rule this enforces: every universal statement in the repository depends on
Lean's standard axioms, plus at most the one compiler-trust axiom inherited
from the pinned upstream CodeLib (see BV_DECIDE_INHERITED below). A
`native_decide` dependency is allowed exactly for the concrete per-input
regressions, which live in `Smoke.lean` and `Equivalence.lean` and are never
used to prove anything universal.

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

# One axiom is inherited from the pinned upstream CodeLib and tolerated for
# every theorem: upstream proves the byte-reassembly lemma
# `Wasm.SepLogic.u32Byte_reassemble` with `bv_decide`, whose LRAT certificate
# check runs through compiled code. Its trust base is the Lean compiler, the
# same as `native_decide`. Every heap-touching rule in the upstream total
# lifting library depends on that lemma, so every symbolic memory proof here
# inherits the axiom and nothing local can remove it. The pattern is pinned
# to that one upstream lemma on purpose: a bv_decide axiom from anywhere else
# still fails the audit.
BV_DECIDE_INHERITED = re.compile(
    r"^Wasm\.SepLogic\.u32Byte_reassemble\._native\.bv_decide\.ax_\d+_\d+$")

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
    standard_only = 0
    inherited = 0
    native = 0
    for name, axioms in records:
        found = {a.strip() for a in axioms.split(",") if a.strip()}
        extra = found - STANDARD
        unexplained = {a for a in extra if not BV_DECIDE_INHERITED.match(a)}
        if not extra:
            standard_only += 1
        elif not unexplained:
            inherited += 1
        elif NATIVE_OK.search(name):
            native += 1
        else:
            failures.append((name, sorted(unexplained)))

    if failures:
        for name, extra in failures:
            print(f"non-standard axioms for {name}: {', '.join(extra)}")
        return 1

    print(f"axiom audit ok: {len(records)} theorems, "
          f"{standard_only} on standard axioms only, "
          f"{inherited} also carrying the inherited upstream bv_decide axiom, "
          f"{native} quarantined native_decide regressions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
