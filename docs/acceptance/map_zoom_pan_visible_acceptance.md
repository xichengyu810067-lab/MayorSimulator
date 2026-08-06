# Native map zoom/pan visible acceptance

This supplemental runner is deliberately separate from the canonical UI capture
contract. It does not alter that contract's four native states, 33 offscreen
states, schema, or success marker.

Run it with a fresh child directory of the project root:

```powershell
& .\tools\run_map_zoom_pan_visible_acceptance.ps1 `
  -GodotExe 'C:\Users\USER\Tools\Godot\Godot_v4.7-stable_win64_console.exe' `
  -OutputRoot '.tmp\map-zoom-pan-visible-<timestamp>'
```

The Godot script opens a native fullscreen root window, reaches the map, then
drives the existing `Main._input` path with wheel and middle-button drag input.
It writes `before`, `zoomed`, and `panned` PNGs plus transform/input metrics.
The input is scripted `InputEvent` delivery, not proof of physical mouse
hardware. The runner rejects reused output roots, diagnostics, missing or
duplicate PNG hashes, incomplete process cleanup, and source changes during the
run. This native-only acceptance remains outside the headless assertion matrix.
