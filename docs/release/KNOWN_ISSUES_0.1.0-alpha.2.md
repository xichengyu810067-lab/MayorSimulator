# 《城諾之音》 / CivicTale: Voice of Promise — Known Issues 0.1.0-alpha.2 (INTERNAL-ONLY)

Internal Alpha is **CONDITIONAL GO** only after this exact RC’s Windows
acceptance passes. Public release is **NO-GO** while the three P0 items in
`PUBLIC_RELEASE_BLOCKERS.md` remain open.

## P1-001 — historical Godot ObjectDB lifecycle diagnostic

- **Phenomenon:** The first alpha.1 Windows smoke ended with `WARNING: 2 ObjectDB instances were leaked at exit`.
- **Discovery / reproduction:** It was found in the first Windows smoke stderr. A later verbose diagnostic, a retry, and the clean exact alpha.1 RC did not reproduce it. Alpha.2 must reject any recurrence independently.
- **Impact:** A recurrence invalidates that RC smoke until diagnosed. This is a Godot object-lifetime teardown diagnostic, **not** data exfiltration or a packaged-data leak.
- **Instance types:** The non-verbose original gave only a count; no class/type was obtained. Clean follow-up runs had no leaked instances to enumerate.
- **Save impact:** No corruption was observed in separate OS-kill checks, but this warning cannot prove there is no lifecycle side effect.
- **Workaround:** Run fresh exported-product Windows smoke for every RC; do not whitelist the warning.
- **Closure:** Reproduce with type/owner information, repair teardown, add a targeted regression check, then pass fresh exact-commit acceptance without it.

## P1-002 — manual five-language GUI evidence incomplete

- **Phenomenon:** Automated localization assertions do not prove a human click-through and visual-layout review in every locale.
- **Reproduction:** Select zh-TW, zh-CN, en, ja, and ko in native Windows GUI; exercise controls and retain locale-labelled screenshots/observations. This is incomplete for this RC.
- **Impact:** Text clipping, layout, and input affordances remain experimental in unreviewed locales.
- **Save impact:** No specific save risk is known; automated state checks do not replace visual/manual acceptance.
- **Workaround:** Internal testers may use their locale and report defects; do not represent language UI as fully manually certified.
- **Closure:** Real native-GUI click-through evidence for all five locales on this exact RC, with defects resolved or explicitly accepted.

## P2 / P3

- **P2:** Windows executable/package is not code-signed.
- **P2:** Linux is not an alpha.2 deliverable and has no Linux-host smoke claim.
- **P3:** The former “10:00 missed” claim is invalid. At the recorded 2026-08-10 02:55:33 +08:00 check, 05:30/07:30/09:00/09:30/10:00 were future; assess them by actual evidence, never in advance.
