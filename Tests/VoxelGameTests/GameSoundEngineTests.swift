import AVFoundation
import Testing

@testable import VoxelGame

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
