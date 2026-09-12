# 《城諾之音》 / CivicTale: Voice of Promise Current Release Control

- Control task: `019fc87e-d138-7010-a95c-29ca1fb678bf`.
- Product authority: `30_core` branch `main`.
- Current target: `0.1.0-alpha.3`, Windows x64, INTERNAL-ONLY.
- Release source: `d55c62033c9d9b50d9ae359f9f9c63ce7079f0d1` (tree
  `211e454b6ff3d3297fc08f6d47af81adb3a992d3`).
- Tag contract: no tag is created by this audit. Existing `v0.1.0-alpha.1`
  and `v0.1.0-alpha.2` tags are immutable and must never be moved.
- Product version authority: root `VERSION`; Windows metadata remains `0.1.0.0`.
- Historic alpha.1 baseline: `dac20a65365b62a1ba370d7be8317536f67be755`; it is not the alpha.1 tag source and is not this RC source. The alpha.2 source and evidence are historical only.
- Distribution: no push, remote tag, GitHub Release, public upload, or public release.
- Internal verdict: **CONDITIONAL GO** for access-controlled Windows x64 testing.
  The 2026-08-10 fresh acceptance passed on the exact source above; P1-001
  still requires manual five-language native-GUI evidence. Public release
  remains NO-GO due to `P0-RIGHTS-001..003`.

## Recomputed time gates

The live audit started after 09:00 Asia/Taipei on 2026-08-10. 07:00 and 09:00
are elapsed checkpoints, not automatically successful or "missed" labels.
Record actual evidence against each checkpoint; timing never overrides a NO-GO.

## Exact acceptance

- Canonical single-run acceptance: PASS; assertion matrix 67/67 product-clean,
  OS-kill 5/5, Windows exported-product smoke exit 0 with zero product and
  ObjectDB leak diagnostics.
- Native Windows UI acceptance: PASS; 4 native captures at 2880x1800 and 33
  supplemental captures. This is not five-language manual click-through proof.
- Stable Windows ZIP: `MayorSimulator-Windows-x86_64-0.1.0-alpha.3.zip`,
  `59764222` bytes, SHA-256
  `35bc170c96e91b6c89153cf4b7ed1555b701eed516c640f2f7a2b1fbe7bb72d5`.
