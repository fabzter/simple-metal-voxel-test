import Testing

@testable import VoxelGame

struct SoundSynthesisTests {
    private let sampleRate = 48_000.0

    @Test
    func breakSamplesHaveExpectedLengthAndBounds() {
        let samples = SoundSynthesis.breakSamples(sampleRate: sampleRate, variant: 0)
        #expect(samples.count == Int(SoundSynthesis.breakDuration * sampleRate))

        let peak = samples.map(abs).max() ?? 0
        #expect(peak <= 1.0)
        #expect(peak > 0.05)  // Actually audible, not near-silence.
    }

    @Test
    func placeSamplesHaveExpectedLengthAndBounds() {
        let samples = SoundSynthesis.placeSamples(sampleRate: sampleRate, variant: 0)
        #expect(samples.count == Int(SoundSynthesis.placeDuration * sampleRate))

        let peak = samples.map(abs).max() ?? 0
        #expect(peak <= 1.0)
        #expect(peak > 0.05)
    }

    @Test
    func variantsProduceDifferentSamples() {
        let a = SoundSynthesis.breakSamples(sampleRate: sampleRate, variant: 0)
        let b = SoundSynthesis.breakSamples(sampleRate: sampleRate, variant: 1)
        #expect(a != b)

        let c = SoundSynthesis.placeSamples(sampleRate: sampleRate, variant: 0)
        let d = SoundSynthesis.placeSamples(sampleRate: sampleRate, variant: 2)
        #expect(c != d)
    }

    @Test
    func synthesisIsDeterministic() {
        let first = SoundSynthesis.breakSamples(sampleRate: sampleRate, variant: 1)
        let second = SoundSynthesis.breakSamples(sampleRate: sampleRate, variant: 1)
        #expect(first == second)
    }

    @Test
    func windIsLoopLengthAndGentle() {
        let samples = SoundSynthesis.windSamples(sampleRate: sampleRate)
        #expect(samples.count == Int(SoundSynthesis.windLoopDuration * sampleRate))

        let peak = samples.map(abs).max() ?? 0
        #expect(peak <= 0.4)  // A background bed, never foreground-loud.
        #expect(peak > 0.1)
    }
}
