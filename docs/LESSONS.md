# Hard-Earned Lessons

This ledger is append-only. New lessons get the next number. When a lesson is
superseded, annotate it `Superseded by #N (date)` and keep the original text —
in this project, knowledge may be superseded, never forgotten.

## 1. Mixed-LOD seam cracks

All-or-nothing neighbor face culling leaves holes when a coarse chunk borders a
finer one. The durable fix is to emit seam boundary faces per
fine-resolution subquad instead of assuming one exposure decision fits the
entire coarse face. The war story and dead ends live in
`docs/mixed-lod-seam-debugging.md`, and the regression coverage lives in the
`VoxelMesher` seam tests.

## 2. Diagnostics are temporary

The per-frame LOD-seam diagnostics scaffolding was deliberately removed after
the seam fix and archived in `docs/diagnostics-instrumentation.md`. Ship clean
runtime code by default; if a future LOD regression needs deep tracing, bring
the tooling back on a throwaway branch instead of letting diagnostic recorders
become permanent baggage.

## 3. AVAudioEngine graph wiring

`GameSoundEngine` must wire its node graph in `start()` using one shared mono
`AVAudioFormat` for both connections and scheduled buffers. Wiring in `init()`
or mixing channel counts can trip an Objective-C exception that Swift cannot
catch, so the startup sequence and format consistency are part of the contract.

## 4. Sky pass

The sky is the first draw inside the existing encoder, using a depth state of
`.always` with depth writes disabled. It is not a second render pass. That
preserves the single late-acquired drawable flow and keeps the frame structure
simple for a Metal beginner reading `Renderer.swift`.

## 5. Fog vs LOD dither

Fog belongs after the Bayer `discard_fragment()` in `fragment_main`. Applying
fog before the LOD dither discard breaks the intended crossfade and creates
visual artifacts during LOD transitions. Preserve that ordering when touching
`VoxelShaders.metal`.

## 6. Tiny atlas needs mipmaps

The procedural material atlas is tiny and high contrast, which makes it shimmer
without mipmaps. Coarse mips do introduce some color bleed, but that tradeoff
is preferable to temporal sparkle. `MaterialAtlas` therefore optimizes for
stable motion over perfectly pure distant texels.

## 7. Save codes are append-only

`WorldSaveCodec` material codes are part of the on-disk compatibility contract.
Never renumber existing material codes. When adding a new material, append a
new code so older saves remain decodable and newer saves do not silently change
meaning.

## 8. Sky-look framerate

Occlusion rays through empty air cost work without ever hitting anything. The
fix was twofold: skip all-air chunks via `VoxelWorld.chunkHasSolidVoxels(_:)`
before visibility work, and cap occlusion tests at 96 world units in the
renderer. Empty worlds must still keep `meshBufferCacheCount == 0`, so tests
that expect cached geometry need to seed at least one solid voxel first.

## 9. Menu keys race the event monitor

Menu key equivalents that mirror live gameplay keys need modifiers, or the
local `NSEvent` monitor can see the same keystroke and double-toggle behavior.
That is why the fly-mode menu command uses `⌥⌘F` instead of plain `F` in
`AppDelegate.configureMenus()`.

## 10. Save folder name is history

The Application Support folder stays named `VoxelGame` even after the engine /
demo split. That historical name preserves compatibility with existing local
saves, so a cleanup rename would cost user data continuity for almost no gain.


## 11. Centered voxel convention in collision

Voxel index `i` occupies world-space `[i-0.5, i+0.5)` on every axis (proven
by `ChunkBounds.bounds` offsets and `VoxelMesher.faceQuad` at `cell ± 0.5`).
`PlayerController.collides()` must round the horizontal body AABB to cell
centers (`floor(v + 0.5)`), not plain `floor()`. Plain `floor()` treats
voxel `i` as `[i, i+1)`, letting the body and eye push ~0.5 into a rendered
wall in +x/+z; the near face then falls behind the eye, gets back-face-culled,
and the block looks see-through. The y bounds keep the legacy `[i, i+1)`
behavior because the vertical landing/head-bump resolution and the
`isStandingOnGround` probe are tuned to it and to the `y<0` phantom floor.

## 12. Near chunks are exempt from occlusion culling

`ChunkOcclusionCuller.isVisible` samples only a chunk AABB's 8 corners +
center. At close range the solid surface the player faces is in the chunk
interior, not at a sampled corner, so every corner ray can read as occluded and
wrongly hide the chunk — the block in front of the player turns see-through.
The fix is a near-exemption at the top of `isVisible`: always return true when
the camera lies within one chunk (the 3×3×3 neighborhood) of the chunk's AABB.
This lives in the culler (not the render loop) so it stays unit-testable without
Metal.

## 13. Metal [0,1] frustum near plane

`float4x4.perspective` builds a Metal `[0,1]` clip-space projection (NDC z=0
at near, 1 at far). Gribb-Hartmann near-plane extraction for `[0,1]` clip is
row `r2`, not the OpenGL `[-1,1]` form `r3 + r2`. `FrustumCuller` used
`r3 + r2`, making the near plane over-permissive (keeping geometry closer than
the near clip). It did not cause see-through but is a real correctness bug; the
far plane stays `r3 - r2`.

## 14. Cancel gameplay input on window focus loss

`MetalView.windowKeyStateChanged` fires on `didBecomeKey`/`didResignKey`.
A movement key held while the user cmd-tabs away never gets its key-up event, so
without calling `inputController.cancelGameplayInput()` on resign the player
keeps walking while backgrounded. The `didResignKey` observer was already
registered; the fix only adds the cancel call before the existing
`updateInteractiveState()`.
