# Hunting Sky-Holes: Debugging Mixed-Resolution Voxel LOD Seams on Metal

*An engineering case study from the VoxelGame project.*

## Abstract

VoxelGame renders distant terrain with level-of-detail (LOD) meshing: near chunks
use full per-voxel detail, far chunks merge voxels into coarser aggregates to save
vertices. This produces **mixed-resolution seams** where a fine chunk meets a coarse
one. Those seams leaked the sky-colored background through the terrain — a "see-through
glitch" that moved farther away each time we fixed one layer of the problem.

This document records the full investigation: the diagnostic instrumentation we built,
the ten distinct root causes we found and fixed, the false diagnoses that cost us time,
and the general principle that finally made the fix robust across every LOD level. The
central lesson is that a coarse LOD cell is a *volumetric approximation*, and the
ordinary "don't draw a face if the neighbor is solid" rule quietly breaks against that
approximation in several different ways.

## 1. Problem statement

A player looking toward the horizon saw thin holes in the terrain that showed the sky
dome behind it. The holes:

- appeared near the boundary between two LOD levels,
- were easy to find but hard to describe precisely,
- and — critically — **moved to the next LOD transition each time we fixed the current one.**

The terrain data itself was correct. The world genuinely had solid voxels where the
sky showed through. This was a *rendering* defect in how the mesher turned coarse voxel
aggregates into triangles at LOD boundaries.

## 2. Background

- **Voxel** — a solid/empty cell in a 3D grid (`VoxelWorld`).
- **Chunk** — a fixed-size block of voxels meshed as a unit (`VoxelChunkIndex`).
- **LOD stride** — how many voxels a coarse cell merges per axis. Stride 1 = full
  detail; stride 2 merges 2×2×2 voxels into one cell; stride 4 merges 4×4×4, and so on.
  The default chain is stride `1, 2, 4, 8` at increasing camera distance
  (`LODConfiguration`).
- **Mixed-LOD seam** — the shared plane where a chunk at one stride touches a neighbor
  at a different stride. The two sides disagree about where surfaces and edges fall,
  which is the source of every defect in this study.

A coarse cell is treated as **solid if any voxel inside its stride cube is solid**.
This aggregation is what makes coarse LOD cheap, and it is also what breaks naive
face-culling: a cell can be "solid" while most of its volume — and specifically its
boundary — is empty.

## 3. Diagnostic methodology

We could not fix what we could not see. The bulk of the work was building instrumentation
that turned a vague visual complaint into exact numbers.

### 3.1 The diagnostics recorder

`LODSeamDiagnosticsRecorder` keeps a rolling buffer of per-frame snapshots and writes a
JSON dump plus screenshots to `.build/diagnostics/` when the app exits. Writing under the
project (not the macOS temp directory) matters: temp files disappeared between repro
cycles before we could read them.

Each snapshot grew over the investigation to include:

- camera position, yaw, pitch;
- the crosshair target cell / face / distance;
- nearby chunk LOD levels, visibility, and vertex counts;
- mixed-LOD boundary height samples on both sides;
- local voxel occupancy slices;
- recent per-chunk LOD transitions;
- **ray/seam intersections** along the full camera ray;
- **seam-patch emission evaluations** (the exact per-subface decision at the ray hit);
- **a CPU voxel raymarch** along the exact center ray.

### 3.2 Screenshots that actually show what the crosshair sees

Three iterations were needed before the screenshot could be trusted:

1. **Whole-window capture** — wrong. The image center is not the crosshair center
   because of the title bar / window frame offset.
2. **Content-bounds capture** — closer, but the crosshair overlay itself painted the
   center pixels, so "what is under the crosshair" was hidden behind the reticle.
3. **Composited content capture + center crop** — the approach that finally worked.
   Capture the already-composited window content at the view's bounds and save a small
   crop centered on the crosshair for fast inspection. An earlier attempt hid the overlay
   views and re-rendered a "scene-only" frame, but hiding overlays and forcing a redraw
   desynchronized the `CAMetalLayer` drawable and produced stale/blank captures. The
   reliable path is to capture the composited frame and crop it — never to re-render with
   overlays toggled off.

A separate coordinate bug lived here too: `CGWindowListCreateImage` expects
top-left CG screen coordinates, but AppKit's `convertToScreen` returns bottom-left
coordinates. Without flipping Y (`cgY = screenHeight - appkitY - height`) the crop
sampled the wrong band of the screen and reported grass where the hole actually was.

### 3.3 The CPU raymarch: the ground-truth oracle

The decisive tool was a CPU voxel raymarch along the exact center ray. It answers one
question with no rendering involved: **should the center pixel be terrain or sky,
according to world data?**

Comparing the raymarch verdict against the rendered pixel splits every ambiguous case
cleanly:

- raymarch = air, pixel = sky → correct (real sky/valley, not a bug);
- raymarch = solid, pixel = sky → **render hole** (the bug).

Extending this to a grid of rays over the center crop and comparing against the
screenshot's sky mask produced a definitive map of render holes versus real terrain
silhouette, ending several rounds of "is that a bug or just the horizon?" guessing.

### 3.4 Offline reproduction

Because the world is deterministic, the final root cause was reproduced **without
launching the app at all**: instantiate the same world, generate the LOD2 mesh for the
exact chunk the raymarch flagged, and assert that a face exists at the hit position.
This converted a 90-second interactive repro into a sub-6-second unit test and pinned
the defect to face emission rather than draw/culling.

## 4. Root causes (in the order they surfaced)

The defect was not one bug. It was a stack of independent bugs that each hid the next.
Fixing one simply exposed the one behind it — which is why the hole appeared to "move
farther away" after every pass.

1. **Overlap-only seam handling.** The original coarse mesher just extended sampling by
   one stride to overlap its neighbor. This left T-junction cracks at the LOD0/LOD1
   boundary.
2. **Edge topology mismatch.** Coarse faces met finer faces with mismatched
   triangulation. Fix: subdivide only the boundary edges that touch a finer neighbor so
   the coarse edge shares the finer mesh's vertices.
3. **Corner pinholes.** Where two mixed-LOD seams met at a corner, a perimeter-only
   triangle fan left a hole. Fix: subdivide the whole face as a 2D grid so the interior
   corner vertex exists.
4. **Coarse cube overgrowth.** A coarse cell was meshed as a full stride-height cube even
   when only one voxel layer was occupied, so its top face floated a voxel above the real
   surface and opened a slit. Fix: emit faces against the cell's *actual occupied vertical
   span*.
5. **Back-face culling of the seam patch.** The seam patch existed but was single-sided
   and back-facing from the player's side. Fix: emit transition boundary quads
   double-sided.
6. **Side-quad vertical compression.** Side seam subquads were derived by slicing the
   already-shrunk coarse face, compressing one occupied fine row into half the intended
   height. Fix: build side subquads from world-space clipped vertical bounds.
7. **Top-edge raster cracks.** Coarse top faces met seam patches at mathematically exact
   edges, leaving razor-thin gaps. Fix: a small overlap margin so adjacent seam pieces
   cover each other.
8. **Top-skirt gaps.** The highest occupied subrow needed to reach the coarse ceiling, and
   had to emit even when the neighbor row was solid. Fix: conservative top-skirt emission.
9. **Mutual face culling (the core insight).** At a seam, the fine chunk culled its face
   because the coarse neighbor was solid, *and* the coarse chunk culled its seam patch
   because the fine neighbor was solid. **Both sides assumed the other would draw the
   face, so neither did.** Fix: coarse seam subfaces emit unconditionally — the coarse
   cell is solid, so its boundary must be watertight.
10. **Invisible solid interior (intra-chunk).** Even away from chunk seams, coarse cells
    inside a chunk culled their shared faces against solid neighbors. A ray grazing the
    terrain surface entered a solid coarse cell and exited through culled internal faces
    without ever hitting geometry, so the distant terrain silhouette dropped out. Fix:
    coarse cells on the terrain surface (the cell above is air) emit their side faces even
    when the lateral neighbor is solid.

## 5. The unifying principle

Every fix above is a special case of one statement:

> **A coarse LOD cell is a volumetric approximation. Any boundary it presents to open
> space — a chunk seam, a terrain surface, a mixed-resolution edge — must be watertight,
> because the ordinary "neighbor is solid, so skip the face" optimization assumes
> per-voxel precision that coarse cells do not have.**

Once framed that way, the general fix is to stop culling coarse boundary faces against an
aggregate neighbor and instead always emit them where the cell faces reachable space. The
cost is extra triangles at LOD boundaries; the benefit is a seam that cannot leak
regardless of how the LOD rings are configured.

## 6. Generalizing across LOD levels

The fix must survive future LOD changes. Two safeguards:

- **No level-specific code.** Seam and surface emission reference only strides and
  occupancy, never a hardcoded LOD index. Adding a stride-16 or stride-32 ring needs no
  new mesher code.
- **Stride-chain validation.** Seam stitching requires each coarser stride to be a
  multiple of every finer stride. `LODConfiguration.validateStrideChain()` enforces this
  at renderer startup, so a non-divisible configuration (e.g. strides 2 and 3) fails fast
  with a clear error instead of silently reintroducing holes.

## 7. False diagnoses (the expensive detours)

The most reusable part of this story is the wrong turns, because each one looked
convincing:

- **"The world data is wrong."** No — the raymarch always confirmed the terrain was
  solid. This was consistently a render bug, never a generation bug.
- **"The center pixel is grass, so it's fixed."** The whole-window screenshot's center
  was offset from the crosshair by the title bar, and later the crosshair overlay itself
  colored the center. The screenshot lied twice for structural reasons before the
  composited content-bounds capture with a crosshair-centered crop made it trustworthy.
- **"It's just sky above the horizon."** Tempting whenever the ray pointed near the
  skyline. The grid raymarch disproved it: the world had solid exactly where the pixel
  showed sky.
- **"The seam telemetry says both sides are solid, so the patch is correctly skipped."**
  True for that subface, but the *fine* side had already culled its face too. The
  per-subface view hid the mutual-culling interaction.
- **"The 24-meter focus point is where the hole is."** The fallback focus clamp reported a
  proxy point, not the actual farther seam the ray passed through. Logging full ray/seam
  intersections replaced the proxy with the truth.
- **"The seam fix is already general."** It was LOD-agnostic in code, but silently
  depended on divisible strides. Generality had to be *guaranteed* with validation, not
  assumed.

## 8. Tooling footnote: the Metal toolchain

Midway through, `swift build` began failing with
`cannot execute tool 'metal' due to missing Metal Toolchain` even though `xcrun -find
metal` worked. The cause was the SwiftPM shader plugin's invocation path, not a missing
toolchain. The fix was to resolve the absolute `metal`/`metallib` tool paths with
`xcrun -sdk macosx -find …` and invoke them directly. Worth recording because the error
message points at a system install problem when the real issue was in the build script.

## 9. Verification

Each fix shipped with a regression test in `VoxelMesherTests`, covering: coarse-boundary
edge stitching, partial seam exposure, double-sided seam faces, occupied-height top
faces, corner interior vertices, top-edge overlap, top-skirt emission, and — as the
final anchor — an offline test that regenerates the exact LOD2 chunk from the deterministic
world and asserts the previously-missing boundary face now exists. LOD configuration
validity (default chain valid, powers-of-two valid, non-divisible rejected) is tested at
the configuration layer.

## 10. Lessons for future voxel LOD work

1. **Build the oracle first.** A CPU raymarch against world data separates "render bug"
   from "reality" in one step and would have saved most of the detours.
2. **Make instrumentation show exactly what the user sees** — capture the composited
   content bounds, crop around the crosshair, and account for the reticle overlay and
   coordinate space. A lying screenshot is worse than none.
3. **Reproduce offline from deterministic state.** Interactive repro loops are slow and
   noisy; a unit test on the exact flagged chunk is fast and permanent.
4. **Treat coarse cells as volumes, not scaled voxels.** Their boundaries against open
   space must be watertight; per-voxel culling assumptions do not transfer.
5. **Guarantee generality, don't assume it.** If a fix depends on a configuration
   property (divisible strides), validate that property at startup.

## Appendix: source map

- `Sources/VoxelGameKit/World/VoxelMesher.swift` — seam stitching, transition boundary
  faces, occupied-height faces, terrain-surface emission.
- `Sources/VoxelGameKit/Rendering/LODConfiguration.swift` — LOD chain and
  `validateStrideChain()`.
- `Sources/VoxelGameKit/Rendering/Renderer.swift` — seam configuration, ray/seam
  intersections, CPU raymarch diagnostics.
- `Sources/VoxelGameKit/Rendering/RendererDiagnostics.swift` — diagnostic snapshot types.
- `Sources/VoxelGame/UI/LODSeamDiagnosticsRecorder.swift` — JSON + screenshot capture.
- `Tests/VoxelGameKitTests/VoxelMesherTests.swift` — seam and LOD regression tests.
