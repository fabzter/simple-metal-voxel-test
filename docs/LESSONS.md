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
