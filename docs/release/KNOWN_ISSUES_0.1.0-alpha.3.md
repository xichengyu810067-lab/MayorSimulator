# 《城諾之音》 / CivicTale: Voice of Promise — Known Issues 0.1.0-alpha.3 (INTERNAL-ONLY)

## P0 — public distribution rights

- `P0-RIGHTS-001`: no owner-approved project LICENSE/COPYING and redistribution authority record.
- `P0-RIGHTS-002`: city-map background lacks author/license/permission evidence.
- `P0-RIGHTS-003`: train-station runtime asset lacks checksum-linked provenance and redistribution authorization.

These block public distribution, regardless of functional acceptance. Required
closure material is listed in `PUBLIC_RELEASE_BLOCKERS.md` and
`ASSET_PROVENANCE.md`.

## P1-001 — manual five-language native GUI evidence incomplete

- **Phenomenon:** Automated localization and native UI captures do not prove a
  human click-through and visual-layout review in every locale.
- **Reproduction:** In the exact RC, select zh-TW, zh-CN, en, ja, and ko;
  exercise the core HUD and retain locale-labelled screenshots and observations.
- **Impact:** Text clipping, layout, and input affordances are experimental in
  locales without that evidence.
- **Save impact:** No specific save risk is known; this does not replace the
  separate save durability gate.
- **Workaround:** Internal testers may use their locale and report defects.
- **Closure:** Exact-RC native GUI click-through evidence for all five locales,
  with defects resolved or explicitly accepted.

## P2 / P3

- **P2:** Windows executable/package is not code-signed.
- **P3 (non-hard-gate measured partial):** 200k population capacity groundwork
  is not a completed production target. The prior formal measurement recorded
  backup `145.038335 s` and load `185.762394 s`, both above the `120 s` limit;
  this alpha audit does not claim a new 200k benchmark, canonical matrix, or
  OS-kill pass for that scale.
