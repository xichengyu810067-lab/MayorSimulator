# Train Station Runtime Asset Provenance Blocker

Status: release-blocking provenance gap as of 2026-08-02.

## Asset identity

The runtime registry maps `train_station` to
`res://assets/images/world/buildings/storybook_v1/train_station/clean.png`.
The checked files have these deterministic identities:

| File | Bytes | Dimensions / mode | SHA-256 |
|---|---:|---|---|
| `raw.png` | 1,948,398 | 1254 x 1254 RGB | `8EF3C6400895E51DD69FF07AEC5D620C2ED969EA6CA5299F76EB4C78BD363256` |
| `clean-full.png` | 1,492,782 | 1254 x 1254 RGBA | `EBB90A8B6A1C33715D4EC140181FACBFD711A328379E290BA3DD8C5F68C846B5` |
| `clean.png` | 72,577 | 256 x 256 RGBA | `02100EC526DEE75C042463AF0141218606251B693AE2F88158534618A20C6BB9` |

The PNGs contain no embedded metadata. Both the validated handoff extraction
and the recovered workspace contain the same three byte-identical PNGs, but
those package copies are not independent provenance for how the asset was
generated or whether it may be redistributed.

## Why adjacent records cannot be copied

The other 26 building directories contain `pipeline-meta.json` records whose
inputs are named `raw-sheet.png`. The train-station directory instead contains
`raw.png` and no pipeline record. `ART_PROVENANCE.md` explicitly describes 26
generations and says each retained per-item pipeline metadata; it therefore
cannot establish that the later train-station asset used the same generator,
prompt, postprocessor, parameters, author, model, or date.

The repository does not contain the referenced `generate2dsprite.py`. Git shows
the train-station files only in the 2026-08-01 baseline commit
`e0fdf852a2cf27e173f3340f435d5e7f0ee03782`; this proves repository presence,
not how the images were created. Filesystem creation and modification times are
also not provenance and must not be used to reconstruct missing fields.

## Missing evidence

- Original generation receipt or durable source record identifying the
  generator/provider and, if recorded, the exact model/version.
- Exact train-station prompt and any input/reference images, or an explicit
  attestation that those records were not retained.
- Processing command or log identifying the postprocessor implementation and
  version/commit, exact input, parameters, and output mapping.
- A trustworthy timestamp or dated generation record; filesystem timestamps
  alone are insufficient.
- Source/author or rights-holder attribution where applicable, plus the license
  or other permission covering project redistribution.
- A checksum-linked chain connecting the supplied source record, processing
  record, and the three asset hashes above.

## Acceptable closure evidence

Close this blocker only with contemporaneous records or a signed/attributed
attestation that supplies the missing facts without inference. The evidence must
name these exact SHA-256 identities (or provide a reproducible transformation
that produces them), identify which facts are unknown, and keep provenance
separate from redistribution permission. A copied neighboring
`pipeline-meta.json`, guessed prompt/model, or filesystem timestamp is not
acceptable.

## Release gate

Public release packaging must fail or remain unpublished while this runtime
asset has no provenance and redistribution-rights closure. After acceptable
evidence is added, update the item metadata and the scope of
`ART_PROVENANCE.md`, regenerate `RUNTIME_ASSET_LEDGER.json` and `.md`, verify the
three hashes, and run the canonical single-run release evidence gate. Static
ledger success only proves runtime coverage and file integrity; it does not
clear this blocker.
