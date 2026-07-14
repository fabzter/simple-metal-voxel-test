import AVFoundation
import Foundation

// MARK: - Pure sample synthesis
//
// The project ships zero external assets — the texture atlas is procedural, and the
// sounds are too. Every effect below is a tiny signal-processing recipe over a seeded
// noise source, so the same variant always produces the same samples (testable) and
// novices can see exactly how a "thock" or a gust of wind is made.

enum SoundSynthesis {
 /// Duration constants shared with the tests.
 static let breakDuration = 0.09
 static let placeDuration = 0.07
 /// Wind is generated at 4 s, then the last quarter second is crossfaded into the
 /// first, and the tail trimmed — so the loop has no click at the seam.
 static let windRawDuration = 4.0
 static let windLoopCrossfade = 0.25
 static var windLoopDuration: Double { windRawDuration - windLoopCrossfade }
 static let footstepDuration = 0.06
 static let landingDuration = 0.13

 /// Deterministic pseudo-random stream (linear congruential) so tests can assert
 /// exact behavior and variants stay stable across launches.
 private struct SeededNoise {
  var state: UInt64
  mutating func next() -> Float {
   state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
   // Top 24 bits → [-1, 1)
   let bits = Float(state >> 40)
   return bits / Float(1 << 23) - 1.0
  }
 }

 /// Block-break "crack": a noise burst with a fast exponential decay and a lowpass
 /// filter whose cutoff sweeps downward, which reads as debris losing energy.
 static func breakSamples(sampleRate: Double, variant: Int) -> [Float] {
  let count = Int(breakDuration * sampleRate)
  var noise = SeededNoise(state: UInt64(0xB10C_B4EA + variant * 7919))
  var output = [Float](repeating: 0, count: count)
  var filtered: Float = 0

  for i in 0..<count {
   let t = Double(i) / sampleRate
   let envelope = Float(exp(-t / 0.030))
   // One-pole lowpass; cutoff sweeps ~6 kHz → ~1.2 kHz over the burst.
   let progress = Float(i) / Float(max(count - 1, 1))
   let cutoff = 6000 - (6000 - 1200) * progress
   let k = Float(1 - exp(-2.0 * .pi * Double(cutoff) / sampleRate))
   filtered += k * (noise.next() - filtered)
   output[i] = filtered * envelope * 0.9
  }
  return output
 }

 /// Block-place "thock": a short sine whose pitch drops slightly, plus a whisper of
 /// noise at the attack. Variants shift the base pitch so rapid building doesn't
 /// sound machine-gun identical.
 static func placeSamples(sampleRate: Double, variant: Int) -> [Float] {
  let count = Int(placeDuration * sampleRate)
  let baseFrequency = [165.0, 180.0, 196.0][variant % 3]
  var noise = SeededNoise(state: UInt64(0x9_1ACE + variant * 104_729))
  var output = [Float](repeating: 0, count: count)
  var phase = 0.0

  for i in 0..<count {
   let t = Double(i) / sampleRate
   let envelope = Float(exp(-t / 0.045))
   let frequency = baseFrequency - 50.0 * (t / placeDuration)
   phase += 2.0 * .pi * frequency / sampleRate
   let tone = Float(sin(phase))
   let attackNoise = noise.next() * Float(exp(-t / 0.012)) * 0.25
   output[i] = (tone * 0.7 + attackNoise) * envelope
  }
  return output
 }

 /// Ambient wind: heavily lowpassed noise, loopable. Two cascaded one-pole filters
 /// (~350 Hz) turn white noise into a soft rumble; the equal-power crossfade folds
 /// the tail into the head so `.loops` playback is seamless.
 static func windSamples(sampleRate: Double) -> [Float] {
  let rawCount = Int(windRawDuration * sampleRate)
  let fadeCount = Int(windLoopCrossfade * sampleRate)
  let loopCount = rawCount - fadeCount

  var noise = SeededNoise(state: 0x57D1_D001)
  var raw = [Float](repeating: 0, count: rawCount)
  var stage1: Float = 0
  var stage2: Float = 0
  let k = Float(1 - exp(-2.0 * .pi * 350.0 / sampleRate))

  for i in 0..<rawCount {
   stage1 += k * (noise.next() - stage1)
   stage2 += k * (stage1 - stage2)
   raw[i] = stage2
  }

  // Equal-power crossfade: tail fades out while the head fades in.
  var looped = [Float](repeating: 0, count: loopCount)
  for i in 0..<loopCount {
   if i < fadeCount {
    let fade = Float(i) / Float(fadeCount)
    let fadeIn = sqrt(fade)
    let fadeOut = sqrt(1 - fade)
    looped[i] = raw[i] * fadeIn + raw[loopCount + i] * fadeOut
   } else {
    looped[i] = raw[i]
   }
  }

  // Normalize to a gentle ceiling — wind is a bed, not a foreground sound.
  let peak = looped.map(abs).max() ?? 1
  if peak > 0 {
   let gain = 0.35 / peak
   for i in 0..<loopCount { looped[i] *= gain }
  }
  return looped
 }

 /// Footstep: a soft muffled crunch — a lowpassed noise burst with a fast decay plus a
 /// faint low thump, so walking feels grounded without becoming distracting. Variants
 /// nudge the timbre so repeated steps don't sound identical.
 static func footstepSamples(sampleRate: Double, variant: Int) -> [Float] {
  let count = Int(footstepDuration * sampleRate)
  var noise = SeededNoise(state: UInt64(0x0F00_75E9 + variant * 6151))
  var output = [Float](repeating: 0, count: count)
  var filtered: Float = 0
  let cutoff = 700.0 + Double(variant % 3) * 120.0
  let k = Float(1 - exp(-2.0 * .pi * cutoff / sampleRate))
  let thumpFrequency = 95.0 - Double(variant % 3) * 8.0
  var phase = 0.0

  for i in 0..<count {
   let t = Double(i) / sampleRate
   let envelope = Float(exp(-t / 0.018))
   filtered += k * (noise.next() - filtered)
   phase += 2.0 * .pi * thumpFrequency / sampleRate
   let thump = Float(sin(phase)) * Float(exp(-t / 0.028)) * 0.4
   output[i] = (filtered * 0.7 + thump) * envelope * 0.6
  }
  return output
 }

 /// Landing: a heavier thud when the player hits the ground after a fall — a low sine
 /// that dips in pitch, with a noisy attack and a longer body than a footstep.
 static func landingSamples(sampleRate: Double) -> [Float] {
  let count = Int(landingDuration * sampleRate)
  var noise = SeededNoise(state: 0x1A2D_3B4C)
  var output = [Float](repeating: 0, count: count)
  var filtered: Float = 0
  let k = Float(1 - exp(-2.0 * .pi * 500.0 / sampleRate))
  var phase = 0.0

  for i in 0..<count {
   let t = Double(i) / sampleRate
   let envelope = Float(exp(-t / 0.045))
   filtered += k * (noise.next() - filtered)
   let frequency = 70.0 - 20.0 * (t / landingDuration)
   phase += 2.0 * .pi * frequency / sampleRate
   let thump = Float(sin(phase)) * Float(exp(-t / 0.06))
   output[i] = (thump * 0.8 + filtered * 0.35) * envelope * 0.85
  }
  return output
 }
}

// MARK: - Engine

/// Plays the synthesized effects through AVAudioEngine.
///
/// Four round-robin player nodes let rapid block edits overlap instead of queueing;
/// a fifth node loops the wind bed. If the engine fails to start (headless test runs,
/// no audio hardware) every call degrades to a silent no-op — sound must never take
/// the game down.
@MainActor
final class GameSoundEngine {
 private let engine = AVAudioEngine()
 private let effectPlayers = (0..<4).map { _ in AVAudioPlayerNode() }
 private let windPlayer = AVAudioPlayerNode()
 private let footstepPlayer = AVAudioPlayerNode()

 private var placeBuffers: [AVAudioPCMBuffer] = []
 private var breakBuffers: [AVAudioPCMBuffer] = []
 private var footstepBuffers: [AVAudioPCMBuffer] = []
 private var landingBuffers: [AVAudioPCMBuffer] = []
 private var nextEffectIndex = 0
 private var isRunning = false

 private(set) var isEnabled = true
 private(set) var masterVolume: Float = 1

 /// Node graph wiring happens in `start()` where the hardware format is known;
 /// constructing the engine never touches CoreAudio, so building a MetalView in
 /// tests stays inert.
 init() {}

 func setEnabled(_ enabled: Bool) {
  isEnabled = enabled
  engine.mainMixerNode.outputVolume = enabled ? masterVolume : 0
 }

 /// Master volume lives on the mixer so the relative per-effect voice levels stay intact.
 func setMasterVolume(_ volume: Float) {
  masterVolume = min(max(volume, 0), 1)
  engine.mainMixerNode.outputVolume = isEnabled ? masterVolume : 0
 }

 /// Starts the engine, synthesizes the effect buffers at the output sample rate,
 /// and begins the wind loop. Safe to call more than once.
 func start() {
  guard !isRunning else { return }
  // One format for connections AND buffers: mono Float32 at the hardware rate.
  // Sharing the exact instance guarantees AVAudioPlayerNode's channel-count
  // precondition can never fire (the crash this replaces).
  let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
  guard hardwareRate > 0,
   let monoFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: hardwareRate,
    channels: 1, interleaved: false)
  else { return }

  for player in effectPlayers {
   engine.attach(player)
   engine.connect(player, to: engine.mainMixerNode, format: monoFormat)
   player.volume = 0.55
  }
  engine.attach(windPlayer)
  engine.connect(windPlayer, to: engine.mainMixerNode, format: monoFormat)
  windPlayer.volume = 0.12
  engine.attach(footstepPlayer)
  engine.connect(footstepPlayer, to: engine.mainMixerNode, format: monoFormat)
  footstepPlayer.volume = 0.5
  engine.mainMixerNode.outputVolume = isEnabled ? masterVolume : 0

  do {
   try engine.start()
  } catch {
   return  // isRunning stays false; all play calls no-op.
  }
  isRunning = true

  placeBuffers = (0..<3).compactMap {
   Self.makeBuffer(
    SoundSynthesis.placeSamples(sampleRate: hardwareRate, variant: $0),
    format: monoFormat)
  }
  breakBuffers = (0..<3).compactMap {
   Self.makeBuffer(
    SoundSynthesis.breakSamples(sampleRate: hardwareRate, variant: $0),
    format: monoFormat)
  }
  footstepBuffers = (0..<4).compactMap {
   Self.makeBuffer(
    SoundSynthesis.footstepSamples(sampleRate: hardwareRate, variant: $0),
    format: monoFormat)
  }
  landingBuffers = [
   Self.makeBuffer(
    SoundSynthesis.landingSamples(sampleRate: hardwareRate), format: monoFormat)
  ].compactMap { $0 }

  if let windBuffer = Self.makeBuffer(
   SoundSynthesis.windSamples(sampleRate: hardwareRate), format: monoFormat)
  {
   windPlayer.scheduleBuffer(windBuffer, at: nil, options: .loops)
   windPlayer.play()
  }
 }

 func playBlockPlaced() {
  playRandomVariant(from: placeBuffers)
 }

 func playBlockRemoved() {
  playRandomVariant(from: breakBuffers)
 }

 /// Plays a single footstep. Footsteps and landings share one dedicated node so walking
 /// never steals a block-edit voice; steps are spaced further apart than their duration,
 /// so scheduled buffers play back-to-back at a natural cadence.
 func playFootstep() {
  guard isRunning, isEnabled, let buffer = footstepBuffers.randomElement() else { return }
  footstepPlayer.scheduleBuffer(buffer, at: nil)
  footstepPlayer.play()
 }

 func playLanding() {
  guard isRunning, isEnabled, let buffer = landingBuffers.randomElement() else { return }
  footstepPlayer.scheduleBuffer(buffer, at: nil)
  footstepPlayer.play()
 }

 private func playRandomVariant(from buffers: [AVAudioPCMBuffer]) {
  guard isRunning, isEnabled, let buffer = buffers.randomElement() else { return }
  let player = effectPlayers[nextEffectIndex]
  nextEffectIndex = (nextEffectIndex + 1) % effectPlayers.count
  player.scheduleBuffer(buffer, at: nil)
  player.play()
 }

 private static func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
  guard
   let buffer = AVAudioPCMBuffer(
    pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
  else { return nil }

  buffer.frameLength = AVAudioFrameCount(samples.count)
  samples.withUnsafeBufferPointer { source in
   buffer.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
  }
  return buffer
 }
}
