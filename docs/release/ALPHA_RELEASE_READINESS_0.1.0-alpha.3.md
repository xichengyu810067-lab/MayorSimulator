# Alpha Release Readiness — 0.1.0-alpha.3

This is the live-source readiness record. Alpha.1 and alpha.2 evidence is
historical and cannot certify this candidate.

| Gate | Required evidence | Status before alpha.3 acceptance |
| --- | --- | --- |
| Version uniqueness | `VERSION`, Windows metadata, immutable prior tags | PASS: alpha.3 is unused; no tag is created |
| Assertions | Fresh exact-source canonical 67-test matrix | PASS: 67/67 product-clean |
| Save durability | Fresh exact-source OS-kill QA | PASS: 5/5 |
| Native Windows UI | Fresh exact-source native capture/smoke | PASS: 4 native, 33 supplemental captures |
| Export/package | Fresh Windows x64 ZIP, fingerprint, content scan | PASS: SHA-256 `35bc170c…72d5`; no handoff/chat/private-path/credential hits |
| Internal verdict | All current evidence tied to one source commit | CONDITIONAL GO: manual five-language GUI P1 remains |
| Public verdict | Rights P0 closure | NO-GO |

The 200k capacity work is measured partial/P3 and is not an Internal MVP hard
gate. It must not be reported as complete.
