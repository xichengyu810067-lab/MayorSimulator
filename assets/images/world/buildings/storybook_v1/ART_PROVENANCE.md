# Storybook building art provenance

- Generator: OpenAI `image_gen`
- Postprocessor: `generate2dsprite.py` (`asset`, `single`, 256 px, bottom aligned)
- Generation date: 2026-07-31
- Raw generation background: solid `#FF00FF`
- Final delivery: transparent PNG, one canonical asset per building

Shared prompt direction: a single isolated 2D game building asset, warm watercolor
storybook illustration, whimsical civic-town architecture, cream stone, teal-blue
roofing, amber window light, gold trim, three-quarter isometric view, centered full
silhouette, no people, no readable text, no watermark, no border, solid magenta
background, no magenta on the subject.  Each of the 26 generations used a separate
building-specific description and identifying architectural cues.

The original generated sheet, processed source, clean PNG, and pipeline metadata
are retained inside each building folder.  `building-art-contact-sheet.png` under
`artifacts/screenshots/ui-tests` is the visual-QA overview.
