# VoxelEngine

VoxelEngine is a small first-person voxel engine built directly on top of Apple's Metal API with Swift Package Manager. It is unapologetically macOS-only: instead of hiding the graphics work behind an abstraction layer, the engine keeps the full path from world data to pixels on screen small and readable so you can study every step — voxel storage, chunk meshing, LOD, culling, and the Metal render pipeline.

The engine is the main product of this repository. It ships together with **VoxelDemo**, a compact first-person demo game built on top of the engine that exercises all of it end to end: a native AppKit window, mouse-look input, block editing, procedural sound, world saving, and a debug inspector. The dependency points one way only — the demo imports the engine, never the reverse — so the engine stays reusable for other games.

## Repository layout

| Part | Target | What it is |
| --- | --- | --- |
| **Engine** (main product) | `VoxelEngine` | Library: voxel world + terrain generation, chunk meshing, LOD, frustum/occlusion culling, Metal renderer + shaders, player physics, world persistence |
| **Demo game** (showcase) | `VoxelDemo` | Executable: AppKit window, input mapping, HUD/UI overlays, menus, procedural sound effects, save/load UX |
| Build tooling | `MetalShaderCompiler` + `BuildMetalShaders` | Build-time compilation of `.metal` shader source into the `.metallib` the engine loads at runtime |

The demo aims for a cleaner play view than a traditional always-on debug overlay: a gradient sky with a soft sun sits behind the world, distance fog melts far terrain into the horizon, a block hotbar lines the bottom of the screen, and footsteps ground your movement. The world generation blends broad traversable plains, hillier pockets, and cave-rich regions, then scatters trees and sandy basins, so the terrain feels like a place to roam and build.

## Build and run

### Prerequisites

- macOS with Xcode or the Xcode Command Line Tools installed
- Metal command-line tools available through `xcrun`

If `swift build` fails with `xcrun: error: unable to find utility "metal"`, install the Metal toolchain from Xcode first.

```bash
swift build -c release
./.build/release/VoxelDemo
```

Or use the helper script:

```bash
./run.sh
```

## Controls (demo game)

| Input | Action |
| --- | --- |
| W / A / S / D | Move |
| Mouse | Look around |
| Space | Jump |
| Left click | Remove block |
| Right click | Place block |
| 1-8 / Scroll | Select block for the hotbar |
| Tab | Toggle the debug inspector and release/re-capture the mouse |
| M | Toggle material debug mode |
| F1 | Toggle HUD |
| Esc | Release mouse / close inspector (quit with Cmd+Q or menu) |
| Shift | Sprint (hold) |
| F | Toggle fly mode (Space up, Shift down; also Game ▸ Toggle Fly Mode ⌥⌘F) |

The bottom-center **hotbar** shows the eight block types — Grass, Dirt, Stone, Moss, Snow, Sand, Wood, Leaves — with the active one highlighted. Pick a slot with the number keys or the scroll wheel.

The **File** menu manages worlds: **New World** (⌘N, random seed), **New World from
Seed…** (⇧⌘N — type a number or any phrase), **Open World…** (⌘O), **Open Recent**,
**Revert to Saved**, **Save World** (⌘S), **Save World As…** (⇧⌘S), and **Reset
World…** (asks first and keeps the current seed).  The world also auto-saves when you
quit, so block edits and your position survive across sessions, and the window title
shows the active seed.

The **Game** menu has **Toggle Fly Mode** (⌥⌘F, checkmark shows the current state),
**Copy World Seed** (⇧⌘C — puts the seed on the clipboard for sharing), and a **Sound
Effects** toggle.  Block place/break sounds, footsteps, a landing thud, and the ambient
wind are all synthesized in code at launch — like the texture atlas, the project ships
zero binary assets.

Use **VoxelDemo ▸ Settings…** (⌘,) for the native Settings window. It groups the
persisted **render resolution**, **aspect ratio**, **mouse sensitivity**, **invert look
Y**, **field of view**, **sound effects**, and **master volume** controls into Display,
Controls, and Sound tabs.

The **View** menu now handles the native display and presentation options:
**Window Size** presets, **Aspect Ratio** locking (**Free**, **16:9**, **16:10**,
**4:3**), **Render Resolution** from **50%** to **200%**, **Enter Full Screen**
(^⌘F), plus the existing debug-inspector / HUD / minimap / crosshair toggles. Render
resolution is the main GPU-cost lever: **50%** renders one quarter as many pixels as
**100%**, then the Metal layer scales the image back up to the window.

The **Window** menu provides the standard macOS **Minimize** (⌘M), **Zoom**, and
**Bring All to Front** commands. The main window also remembers its size and position
between launches, and an aspect-ratio lock survives relaunches too.

The **Debug Inspector** (Tab) still exposes **mouse sensitivity** and **field of view**
in-game for quick tuning, and those values stay in sync with the Settings window.

## Key engine concepts

- **Voxels** — `Sources/VoxelEngine/World/VoxelWorld.swift` stores the world as solid or empty cells plus their material data. This is the core 3D grid everything else reads from.
- **Terrain generation** — `Sources/VoxelEngine/World/VoxelTerrainGenerator.swift` blends low-frequency plains, hill masks, domain warping, and depth-aware cave carving, then decorates the surface with sandy basins and deterministic seeded trees (so the same seed always grows the same forest).
- **Chunking** — `Sources/VoxelEngine/World/VoxelChunkIndex.swift` divides the world into fixed-size chunk coordinates. Working chunk-by-chunk keeps updates and rendering manageable instead of touching the whole world every frame.
- **Meshing** — `Sources/VoxelEngine/World/VoxelMesher.swift` turns visible voxel faces into triangles the GPU can draw. Voxels are easy to edit, but GPUs need vertex data.
- **Level of Detail (LOD)** — `Sources/VoxelEngine/Rendering/LODConfiguration.swift` defines how distant chunks switch to coarser voxel sampling. This lowers vertex count for far-away terrain where fine detail is harder to see.
- **Frustum culling** — `Sources/VoxelEngine/Rendering/FrustumCuller.swift` skips chunks outside the camera's view pyramid. If the camera cannot possibly see a chunk, the renderer avoids drawing it.
- **Occlusion culling** — `Sources/VoxelEngine/Rendering/ChunkOcclusionCuller.swift` tries to skip chunks that are blocked by other terrain. This is an extra visibility test on top of frustum culling.
- **Materials** — `Sources/VoxelEngine/World/BlockMaterialType.swift` defines the eight block surfaces (grass, dirt, stone, moss, snow, sand, wood, leaves) plus a reusable `swatchColor` any palette UI can draw. The renderer uses the material choice to pick tiles from the procedural atlas.
- **Atmosphere** — `Sources/VoxelEngine/Rendering/SkyConfiguration.swift` groups the sky gradient, sun, and fog. A full-screen sky pass draws the background, per-vertex hemispheric + sun lighting shades surfaces, and exponential distance fog fades far terrain into the horizon (which also hides distant LOD transitions).
- **Metal pipeline** — `Sources/VoxelEngine/Rendering/RenderPipelineFactory.swift` creates the Metal render pipeline state that connects shaders, color output, and depth testing. It is the configuration that tells the GPU how to turn vertices into shaded pixels.

## How the demo uses the engine

The demo game is deliberately thin. `Sources/VoxelDemo/UI/MetalView.swift` owns the
window's Metal layer and per-frame loop, but everything it draws and simulates comes
from engine types: it builds a `GameScene` (world + player + editing), forwards mapped
input to the scene, and hands the camera state to the engine's `Renderer` each frame.
Game-specific choices — key bindings, HUD and hotbar design, sound recipes, menus, and
the chosen sky mood — live in the demo, so replacing them does not touch engine code.

## Testing

```bash
swift test
```

Engine behavior is covered by `Tests/VoxelEngineTests` (world, meshing, LOD seams,
culling, persistence, renderer caches); the demo's app-level behavior — input mapping,
sound, startup, recent-worlds list — is covered by `Tests/VoxelDemoTests`.

## Further reading

- [Hard-Earned Lessons Ledger](docs/LESSONS.md)
  — the append-only ledger of hard-earned lessons: superseded knowledge stays
  documented instead of being deleted.
- [Hunting Sky-Holes: Debugging Mixed-Resolution Voxel LOD Seams on Metal](docs/mixed-lod-seam-debugging.md)
  — an engineering case study on the diagnostic tooling and the ten root causes behind
  the LOD seam "see-through" glitch, including the false diagnoses along the way.
- [LOD-Seam Diagnostics Instrumentation](docs/diagnostics-instrumentation.md)
  — an archive of the debug diagnostics subsystem that was removed after the seam fix:
  what it did, where it hooked in, and how to bring it back for a future LOD regression.
