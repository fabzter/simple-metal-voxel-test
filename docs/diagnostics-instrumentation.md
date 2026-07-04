# LOD-Seam Diagnostics Instrumentation (removed — archived for future revival)

*Companion to [Hunting Sky-Holes](mixed-lod-seam-debugging.md).*

## Why this document exists

During the mixed-LOD "see-through" bug hunt (documented in the research paper above)
VoxelGame grew a large, purpose-built diagnostics subsystem: a per-frame snapshot
recorder, a CPU voxel raymarch "oracle", ray/seam intersection logging, and
screenshot capture with a crosshair-centered crop.

Once the bug was fixed, that scaffolding was **removed** to slim the codebase and drop
its per-frame cost. This document is the archive: it records exactly what existed, where
it hooked in, and how to bring it back if a future seam/LOD regression needs the same
tooling. The two dedicated files were never committed to git, so **this write-up is the
only recovery reference** — treat the API sketches below as the reconstruction spec.

## What was removed (and what was deliberately kept)

**Removed — the diagnostics scaffolding:**

| Piece | Location (former) | Role |
|---|---|---|
| `LODSeamDiagnosticsRecorder` | `Sources/VoxelGame/UI/LODSeamDiagnosticsRecorder.swift` (whole file) | Rolling per-frame snapshot buffer; JSON + PNG dump to `.build/diagnostics/` |
| Diagnostic value types | `Sources/VoxelGameKit/Rendering/RendererDiagnostics.swift` (whole file) | `LODDiagnosticsSnapshot`, `ChunkSnapshot`, `MixedBoundarySnapshot`, `BoundaryHeightSample`, `OccupancySlice`, `RayBoundaryIntersectionSnapshot`, `SeamPatchEvaluationSnapshot`, `LODTransitionSnapshot`, `CenterRayMarchSnapshot` |
| Snapshot builder + helpers | `Renderer.swift` | `makeLODDiagnosticsSnapshot(...)` and its private helpers (nearby chunks, mixed boundaries, boundary height samples, occupancy slices, recent transitions, ray/boundary intersections, seam-patch evaluations, **CPU `makeCenterRayMarch`**), plus `recordLODSelection`, `recentLODTransitions`, `frameOrdinal`, `currentVisibleLODLevels`, `seamDebugger`, and small math helpers (`chunkDistance`, `clampColumn`, `chunkFaceRange`, `clampedVoxelIndex`) |
| Seam-patch debug probe | `VoxelMesher.swift` | `SeamPatchDebugSnapshot`, `seamPatchDebugSnapshot(...)`, and its private-only helpers `clampToStride`, `seamSubfaceIsSolid`, `seamNeighborIsSolid`, `anySolid` |
| Screenshot + dump wiring | `MetalView.swift` | `lodDiagnosticsRecorder` property, the per-frame `record(...)` call, `dumpLODDiagnostics`, `captureDiagnosticsImage`, `writeDiagnosticsImage`, `onscreenContentRect`, `captureCenterCrop` |
| Exit trigger | `AppDelegate.swift` | `applicationWillTerminate` → `gameView?.dumpLODDiagnostics(...)` |

**Kept — these are product/developer features, not scaffolding:**

- On-screen **Debug HUD** (`DebugHUDView`, `DebugHUDSnapshot`) — FPS, position, target,
  vertex/chunk/LOD counts.
- **Debug Control Panel** inspector (`DebugControlPanelView`).
- **Material debug modes** and **LOD tint overlay** (shader uniforms in
  `VoxelShaders.metal`, driven from `RenderDebugSettings`).
- The render counters `currentVertexCount`, `currentVisibleChunkCount`,
  `currentLODCounts` on `Renderer` (the HUD reads them).

## Load-bearing subtlety preserved during removal

`recordLODSelection` was interleaved with the **live** LOD-selection path in
`Renderer.selectedLODLevel(...)`. Only the diagnostic recording calls were deleted; the
three `lastChunkLODLevels[chunkIndex] = …` assignments that drive **LOD hysteresis**
were kept. Hysteresis behavior is therefore unchanged. If you re-add the recorder, hook
`recordLODSelection` back in *next to* those assignments, not in place of them.

## What each mechanism did

### 1. The snapshot recorder (the JSON trail)
`LODSeamDiagnosticsRecorder` held a bounded ring buffer of `Snapshot` structs (Codable
mirrors of `Renderer.LODDiagnosticsSnapshot`). `record(frameTimeSeconds:camera:snapshot:)`
was called **every frame** from `MetalView.advanceFrame`. On exit,
`dumpIfNeeded(reason:screenshotPath:sceneScreenshotPath:sceneCenterCropPath:)` wrote a
single pretty-printed JSON session file plus the screenshots to
`<cwd>/.build/diagnostics/`. Persisting under the project (not the OS temp dir) was
deliberate — temp files were being cleaned before analysis.

### 2. The CPU raymarch oracle (`makeCenterRayMarch`)
The most valuable tool. It marched the exact camera center ray through the voxel grid at
a fine step (0.25 vx, up to 128 vx) and reported the first solid cell, its containing
chunk, that chunk's LOD level, visibility, and cached vertex count. This answered, with
no rendering involved, **"should the center pixel be terrain or sky?"** — cleanly
separating render holes (ray hits solid, pixel shows sky) from real sky.

### 3. Ray/seam intersection + seam-patch evaluation
`makeRayBoundaryIntersections` walked chunk-boundary planes the camera ray crossed and
recorded the LOD level on each side and the terrain top-Y on each side.
`makeSeamPatchEvaluations` then asked `VoxelMesher.seamPatchDebugSnapshot(...)` what seam
subface would be emitted at that exact boundary (coarse cell, finer stride, local U/V,
vertical bounds, whether the subface/neighbor is solid, whether a top-skirt is emitted).

### 4. Screenshots with a trustworthy crop
`captureDiagnosticsImage` captured the composited window content at the MetalView's
content bounds via `CGWindowListCreateImage`, converting AppKit bottom-left screen coords
to CG top-left coords (`cgY = screenHeight - appkitY - height`). `captureCenterCrop`
derived a 96 px crop centered on the crosshair. (An overlay-hidden "scene-only" capture
was tried and abandoned — it desynced the `CAMetalLayer` drawable; see the research
paper.)

## Cost that removal reclaimed

The recorder ran `makeLODDiagnosticsSnapshot` **once per frame**, which included the CPU
raymarch (hundreds of `world.isSolid` samples), boundary scans, occupancy slices, and
allocation of the snapshot structs — pure overhead in a shipping build. Removing it takes
that off the frame's critical path entirely.

## How to reintroduce it (future revival guide)

Do this only when actively debugging a seam/LOD regression; keep it out of normal builds.

1. **Recreate the value types.** Add back a `RendererDiagnostics.swift` with the snapshot
   structs listed in the table above. Minimum viable set for most bugs:
   `LODDiagnosticsSnapshot` + `CenterRayMarchSnapshot`.
2. **Re-add the builder on `Renderer`.** A public
   `makeLODDiagnosticsSnapshot(world:camera:selectedHit:)`. Start with just the CPU
   raymarch (`makeCenterRayMarch`) — it alone resolves most "is this a render hole or real
   sky?" questions. Reintroduce `currentVisibleLODLevels` (assigned at the end of the
   visibility walk in `render(...)`) if the raymarch needs hit-chunk LOD/visibility.
3. **(Optional) Re-add the seam probe** in `VoxelMesher`
   (`seamPatchDebugSnapshot` + `clampToStride`/`seamSubfaceIsSolid`/`seamNeighborIsSolid`/
   `anySolid`) only if you need per-subface seam emission detail. These are pure,
   world-reading helpers with no side effects.
4. **Recreate the recorder** (`LODSeamDiagnosticsRecorder`) as a `@MainActor` class that
   buffers snapshots and writes JSON to `.build/diagnostics/`. Prefer gating it behind an
   env var or debug flag so it never allocates in release.
5. **Wire it in `MetalView`**: call `record(...)` after `renderer.render(...)` in
   `advanceFrame`, and call the dump from `AppDelegate.applicationWillTerminate` (or a
   menu item / keyboard shortcut for on-demand dumps).
6. **Screenshots**: reuse the composited-content-capture + center-crop approach in §4;
   do **not** revive overlay-hiding.

## References

- [Hunting Sky-Holes: Debugging Mixed-Resolution Voxel LOD Seams on Metal](mixed-lod-seam-debugging.md)
  — the full methodology, the ten root causes, and the false diagnoses this tooling
  helped rule out.
