# Courtroom V1 assets

These project-bound assets implement the judicial hearing as independent layers so Godot can animate attendance by procedural stage. No image contains baked UI text, a real-world flag, a national seal, a logo, or a watermark.

| File | Role |
| --- | --- |
| `courtroom_interior.png` | Empty 16:9 civic administrative courtroom with a three-seat bench, clerk station, counsel tables, gallery and evidence monitor. |
| `judicial_panel.png` | Transparent three-judge collegiate bench. |
| `defense_table.png` | Transparent mayor and defense-counsel table. |
| `court_clerk.png` | Transparent court clerk and docket station. |

## Generation prompt set

- Interior: polished storybook semi-realism; warm cream, muted teal and golden-brown civic courtroom; realistic centered three-seat bench, clerk station, two counsel tables, public gallery and evidence monitor; empty room; no people or text.
- Judicial panel: three diverse adult civic judges in dark navy robes behind one wooden bench; dignified straight-on pose; isolated chroma-green background; no text or symbols.
- Defense table: mayor and professional defense counsel presenting an evidence binder at one counsel table; isolated chroma-green background; no text or symbols.
- Court clerk: experienced clerk at a compact docket station with binder, monitor and microphone; isolated chroma-green background; no text or symbols.

The character sources were converted to transparent PNGs with the ImageGen chroma-key helper using corner auto-key, soft matte and spill cleanup. The runtime loads the PNG files safely even before Godot has created an import cache.
