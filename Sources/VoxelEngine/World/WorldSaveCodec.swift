import Foundation
import simd

/// The complete state of a world that can be saved to and restored from disk.
public struct WorldSaveState: Equatable, Sendable {
  public let gridSize: Int
  public let chunkSize: Int
  public let seed: UInt64
  public let playerPosition: SIMD3<Float>
  public let cameraYaw: Float
  public let cameraPitch: Float
  public let isFlying: Bool
  public let selectedMaterial: BlockMaterialType
  public let solidWords: [UInt64]
  public let materials: [Int: BlockMaterialType]

  public init(
    gridSize: Int, chunkSize: Int, seed: UInt64,
    playerPosition: SIMD3<Float>, cameraYaw: Float, cameraPitch: Float,
    isFlying: Bool, selectedMaterial: BlockMaterialType,
    solidWords: [UInt64], materials: [Int: BlockMaterialType]
  ) {
    self.gridSize = gridSize
    self.chunkSize = chunkSize
    self.seed = seed
    self.playerPosition = playerPosition
    self.cameraYaw = cameraYaw
    self.cameraPitch = cameraPitch
    self.isFlying = isFlying
    self.selectedMaterial = selectedMaterial
    self.solidWords = solidWords
    self.materials = materials
  }
}

// MARK: - Binary codec (v1, little-endian)

public enum WorldSaveCodec {

  private static let magic: [UInt8] = [0x56, 0x58, 0x53, 0x31]  // "VXS1"

  private static func materialCode(_ material: BlockMaterialType) -> UInt8 {
    switch material {
    case .grass: 0
    case .dirt: 1
    case .stone: 2
    case .moss: 3
    case .snow: 4
    case .sand: 5
    case .wood: 6
    case .leaves: 7
    }
  }

  private static func material(from code: UInt8) -> BlockMaterialType? {
    switch code {
    case 0: .grass
    case 1: .dirt
    case 2: .stone
    case 3: .moss
    case 4: .snow
    case 5: .sand
    case 6: .wood
    case 7: .leaves
    default: nil
    }
  }

  /// Reads `count` bytes from `data` at `cursor`, advancing the cursor.
  /// Returns nil if there aren't enough bytes remaining.
  private static func read(_ count: Int, from data: Data, cursor: inout Int) -> [UInt8]? {
    guard cursor + count <= data.count else { return nil }
    let bytes = Array(data[cursor..<cursor + count])
    cursor += count
    return bytes
  }

  /// Reads a little-endian UInt32 from the next 4 bytes, avoiding unaligned loads.
  private static func readUInt32(_ bytes: [UInt8]) -> UInt32 {
    UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
  }

  /// Reads a little-endian UInt64 from the next 8 bytes, avoiding unaligned loads.
  private static func readUInt64(_ bytes: [UInt8]) -> UInt64 {
    UInt64(readUInt32(Array(bytes[0..<4]))) | (UInt64(readUInt32(Array(bytes[4..<8]))) << 32)
  }

  // MARK: — Encode

  public static func encode(_ state: WorldSaveState) -> Data {
    var data = Data()
    data.reserveCapacity(
      4 + 4 + 4 + 8 + 12 + 4 + 4 + 1 + 1 + 4 + state.solidWords.count * 8 + 4 + state.materials
        .count * 5)

    data.append(contentsOf: magic)
    data.append(value: UInt32(state.gridSize).littleEndian)
    data.append(value: UInt32(state.chunkSize).littleEndian)
    data.append(value: state.seed.littleEndian)
    data.append(value: state.playerPosition.x.bitPattern.littleEndian)
    data.append(value: state.playerPosition.y.bitPattern.littleEndian)
    data.append(value: state.playerPosition.z.bitPattern.littleEndian)
    data.append(value: state.cameraYaw.bitPattern.littleEndian)
    data.append(value: state.cameraPitch.bitPattern.littleEndian)
    data.append(state.isFlying ? 1 : 0)
    data.append(materialCode(state.selectedMaterial))

    data.append(value: UInt32(state.solidWords.count).littleEndian)
    for word in state.solidWords {
      data.append(value: word.littleEndian)
    }

    data.append(value: UInt32(state.materials.count).littleEndian)
    for (cellIndex, material) in state.materials {
      data.append(value: UInt32(cellIndex).littleEndian)
      data.append(materialCode(material))
    }

    return data
  }

  // MARK: — Decode

  public static func decode(_ data: Data) -> WorldSaveState? {
    var cursor = 0

    guard let magicBytes = read(4, from: data, cursor: &cursor), magicBytes == Self.magic else {
      return nil
    }

    guard let gb = read(4, from: data, cursor: &cursor) else { return nil }
    let gridSize = Int(readUInt32(gb))
    guard let cb = read(4, from: data, cursor: &cursor) else { return nil }
    let chunkSize = Int(readUInt32(cb))
    guard gridSize > 0, chunkSize > 0 else { return nil }

    guard let sb = read(8, from: data, cursor: &cursor) else { return nil }
    let seed = readUInt64(sb)

    guard let pxb = read(4, from: data, cursor: &cursor),
      let pyb = read(4, from: data, cursor: &cursor),
      let pzb = read(4, from: data, cursor: &cursor)
    else { return nil }
    let playerPosition = SIMD3<Float>(
      Float(bitPattern: readUInt32(pxb)),
      Float(bitPattern: readUInt32(pyb)),
      Float(bitPattern: readUInt32(pzb)))

    guard let yb = read(4, from: data, cursor: &cursor),
      let pb = read(4, from: data, cursor: &cursor)
    else { return nil }
    let cameraYaw = Float(bitPattern: readUInt32(yb))
    let cameraPitch = Float(bitPattern: readUInt32(pb))

    guard let fb = read(1, from: data, cursor: &cursor) else { return nil }
    let isFlying = fb[0] != 0

    guard let mb = read(1, from: data, cursor: &cursor),
      let selectedMaterial = material(from: mb[0])
    else { return nil }

    guard let wc = read(4, from: data, cursor: &cursor) else { return nil }
    let wordCount = Int(readUInt32(wc))
    let expectedWords = (gridSize * gridSize * gridSize + 63) / 64
    guard wordCount == expectedWords else { return nil }

    var solidWords: [UInt64] = []
    solidWords.reserveCapacity(wordCount)
    for _ in 0..<wordCount {
      guard let w = read(8, from: data, cursor: &cursor) else { return nil }
      solidWords.append(readUInt64(w))
    }

    guard let mc = read(4, from: data, cursor: &cursor) else { return nil }
    let materialCount = Int(readUInt32(mc))
    var materials: [Int: BlockMaterialType] = [:]
    for _ in 0..<materialCount {
      guard let cellBytes = read(4, from: data, cursor: &cursor) else { return nil }
      let cellIndex = Int(readUInt32(cellBytes))
      guard cellIndex >= 0, cellIndex < gridSize * gridSize * gridSize else { return nil }
      guard let matBytes = read(1, from: data, cursor: &cursor),
        let material = material(from: matBytes[0])
      else { return nil }
      materials[cellIndex] = material
    }

    guard cursor == data.count else { return nil }

    return WorldSaveState(
      gridSize: gridSize, chunkSize: chunkSize, seed: seed,
      playerPosition: playerPosition, cameraYaw: cameraYaw, cameraPitch: cameraPitch,
      isFlying: isFlying, selectedMaterial: selectedMaterial,
      solidWords: solidWords, materials: materials)
  }
}

// MARK: — Little-endian append helpers

extension Data {
  fileprivate mutating func append<T>(value: T) {
    var v = value
    Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
  }
}
