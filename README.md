# VoxelGame

VoxelGame is a small first-person voxel demo built directly on top of Apple's Metal API with Swift Package Manager. There is no game engine hiding the graphics work: the project opens a native AppKit window, builds chunk meshes from voxel data, and sends them to Metal for rendering so you can study the full path from world data to pixels on screen.

The current build aims for a cleaner play view than a traditional always-on debug overlay: a compact contextual HUD stays out of the center of the screen, transient banners confirm mode changes, and a larger debug inspector can be opened on demand. The world generation now blends broad traversable plains, hillier pockets, and cave-rich regions so the terrain is easier to roam while still leaving space to explore.

## Build and run

### Prerequisites

- macOS with Xcode or the Xcode Command Line Tools installed
- Metal command-line tools available through `xcrun`

If `swift build` fails with `xcrun: error: unable to find utility "metal"`, install the Metal toolchain from Xcode first.

```bash
swift build -c release
./.build/release/VoxelGame
```

Or use the helper script:

```bash
./run.sh
```

## Controls

| Input | Action |
| --- | --- |
| W / A / S / D | Move |
| Mouse | Look around |
| Space | Jump |
| Left click | Remove block |
| Right click | Place block |
| Tab | Toggle the debug inspector and release/re-capture the mouse |
| M | Toggle material debug mode |
| F1 | Toggle HUD |
| 1-5 | Select block type (`1` Grass, `2` Dirt, `3` Stone, `4` Moss, `5` Snow) |
| Esc | Release mouse / close inspector (quit with Cmd+Q or menu) |
| Shift | Sprint (hold) |
| F | Toggle fly mode (Space up, Shift down; also Game ▸ Toggle Fly Mode ⌥⌘F) |

The **File** menu manages worlds: **New World** (⌘N, random seed), **New World from
Seed…** (⇧⌘N — type a number or any phrase), **Open World…** (⌘O), **Open Recent**,
**Revert to Saved**, **Save World** (⌘S), **Save World As…** (⇧⌘S), and **Reset
World…** (asks first and keeps the current seed).  The world also auto-saves when you
quit, so block edits and your position survive across sessions, and the window title
shows the active seed.

The **Game** menu has **Toggle Fly Mode** (⌥⌘F, checkmark shows the current state),
**Copy World Seed** (⇧⌘C — puts the seed on the clipboard for sharing), and a **Sound
Effects** toggle.  Block place/break sounds and the ambient wind are synthesized in
code at launch — like the texture atlas, the project ships zero binary assets.
The **Debug Inspector** (Tab) includes sliders for **mouse sensitivity** and
**field of view** — both are saved between launches.

## Architecture overview

- `VoxelGame` — thin AppKit executable that creates the window, captures input, and drives the frame loop.
- `VoxelGameKit` — reusable library that contains the voxel world, meshing, renderer, player controller, and scene logic.
- `MetalShaderCompiler` + `BuildMetalShaders` — build-time tools that compile `.metal` shader files into the `.metallib` bundle used by the app.

## Key concepts

- **Voxels** — `Sources/VoxelGameKit/World/VoxelWorld.swift` stores the world as solid or empty cells plus their material data. This is the core 3D grid everything else reads from.
- **Terrain generation** — `Sources/VoxelGameKit/World/VoxelTerrainGenerator.swift` blends low-frequency plains, hill masks, domain warping, and depth-aware cave carving to create a more traversable but still exploratory world.
- **Chunking** — `Sources/VoxelGameKit/World/VoxelChunkIndex.swift` divides the world into fixed-size chunk coordinates. Working chunk-by-chunk keeps updates and rendering manageable instead of touching the whole world every frame.
- **Meshing** — `Sources/VoxelGameKit/World/VoxelMesher.swift` turns visible voxel faces into triangles the GPU can draw. Voxels are easy to edit, but GPUs need vertex data.
- **Level of Detail (LOD)** — `Sources/VoxelGameKit/Rendering/LODConfiguration.swift` defines how distant chunks switch to coarser voxel sampling. This lowers vertex count for far-away terrain where fine detail is harder to see.
- **Frustum culling** — `Sources/VoxelGameKit/Rendering/FrustumCuller.swift` skips chunks outside the camera's view pyramid. If the camera cannot possibly see a chunk, the renderer avoids drawing it.
- **Occlusion culling** — `Sources/VoxelGameKit/Rendering/ChunkOcclusionCuller.swift` tries to skip chunks that are blocked by other terrain. This is an extra visibility test on top of frustum culling.
- **Materials** — `Sources/VoxelGameKit/World/BlockMaterialType.swift` defines block surface types such as grass or stone. The renderer uses that material choice to pick colors from the texture atlas.
- **Metal pipeline** — `Sources/VoxelGameKit/Rendering/RenderPipelineFactory.swift` creates the Metal render pipeline state that connects shaders, color output, and depth testing. It is the configuration that tells the GPU how to turn vertices into shaded pixels.

## Testing

```bash
swift test
```

## Further reading

- [Hunting Sky-Holes: Debugging Mixed-Resolution Voxel LOD Seams on Metal](docs/mixed-lod-seam-debugging.md)
  — an engineering case study on the diagnostic tooling and the ten root causes behind
  the LOD seam "see-through" glitch, including the false diagnoses along the way.
- [LOD-Seam Diagnostics Instrumentation](docs/diagnostics-instrumentation.md)
  — an archive of the debug diagnostics subsystem that was removed after the seam fix:
  what it did, where it hooked in, and how to bring it back for a future LOD regression.
