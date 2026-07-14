import AVFoundation
import Testing

@testable import VoxelDemo

@MainActor
@Test
func startingAndPlayingNeverCrashes() {
    let engine = GameSoundEngine()
    engine.start()
    engine.start()  // idempotent — second call must be a no-op
    engine.playBlockPlaced()  // on audio-capable machines this schedules real
    engine.playBlockRemoved()  // buffers — exactly the path that used to raise
    engine.setEnabled(false)
    #expect(engine.isEnabled == false)
    engine.setEnabled(true)
    #expect(engine.isEnabled == true)
}

@MainActor
@Test
func masterVolumeClampsAndPersistsAcrossToggle() {
    let engine = GameSoundEngine()

    engine.setMasterVolume(1.7)
    #expect(engine.masterVolume == 1)

    engine.setMasterVolume(0.3)
    engine.setEnabled(false)
    engine.setEnabled(true)

    #expect(engine.masterVolume == 0.3)
}
