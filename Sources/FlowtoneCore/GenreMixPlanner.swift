import Foundation

/// Selects a deterministic random fusion of two to five distinct genres from a generation seed.
public struct GenreMixPlanner: Sendable {
  public init() {}

  public func mix(from genres: [String], seed: UInt64) -> [String] {
    let candidates = genres.reduce(into: [String]()) { result, genre in
      guard !result.contains(genre) else { return }
      result.append(genre)
    }
    guard candidates.count > 1 else { return candidates }

    let maximum = min(5, candidates.count)
    let count = 2 + Int(Self.mix(seed) % UInt64(maximum - 1))
    return
      candidates
      .map { genre in
        (genre, Self.mix(seed ^ Self.stableTextHash(genre)))
      }
      .sorted { lhs, rhs in
        if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
        return lhs.0 < rhs.0
      }
      .prefix(count)
      .map(\.0)
  }

  private static func stableTextHash(_ text: String) -> UInt64 {
    text.utf8.reduce(1_469_598_103_934_665_603) { value, byte in
      (value ^ UInt64(byte)) &* 1_099_511_628_211
    }
  }

  private static func mix(_ input: UInt64) -> UInt64 {
    var value = input &+ 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
