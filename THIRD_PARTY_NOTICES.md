# Third-party notices

This file records the third-party runtime component that is verifiably used by
the current project tree. It is **not** a license for the project's own source
code, data, writing, or media. No project-level license has been selected; that
decision remains with the project owner.

## Godot Engine 4.7

Mayor Simulator MVP is built with and distributed using Godot Engine 4.7.
Godot Engine is licensed under the MIT/Expat license. The official license and
the exhaustive notices for components incorporated into the engine are:

- <https://godotengine.org/license/>
- <https://github.com/godotengine/godot/blob/4.7-stable/COPYRIGHT.txt>
- `GODOT_COPYRIGHT.txt` is the byte-identical local copy pinned to the
  `4.7-stable` source tag and is shipped with both release packages.

Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Project media provenance (not third-party packages)

- The six runtime WAV files under `assets/audio/storybook_v1/` are documented
  as original deterministic synthesis produced by
  `tools/audio/generate_storybook_audio.py`, without third-party recordings,
  samples, melodies, or sound libraries.
- The active Storybook UI, building, tutorial, and NPC art has local generation
  provenance records identifying OpenAI `image_gen` and the project's local
  post-processing pipeline. Source sheets, prompts, archives, preview GIFs,
  pipeline metadata, concepts, and the root reference image are development
  material and are excluded by the release presets.
- The runtime city background at
  `assets/images/world/backgrounds/city-map-background.png` is a pre-existing
  project asset migrated from `幻想遊戲地圖風景.png` (SHA-256
  `B968762C5F8756B26874D1B3610D889D2472B251C7E6F3D052B9C0533612E119`).
  The repository does not establish its author or license. Public distribution
  therefore requires the project owner to confirm the usage rights or approve
  a replacement before release.
- The current tree contains no `addons/`, GDExtension, native DLL, bundled
  third-party font, or external runtime package. If any such dependency is
  added later, this notice must be updated before distribution.
