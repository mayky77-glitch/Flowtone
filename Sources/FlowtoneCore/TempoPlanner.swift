import Foundation

/// Chooses a deterministic, genre-aware tempo without exposing a manual BPM control.
public struct TempoPlanner: Sendable {
  public init() {}

  public func tempo(for genre: String, energy: EnergyLevel, seed: UInt64) -> Int {
    let profile = Self.profiles[genre] ?? Self.profiles["Ambient"]!
    let energyOffset: Int =
      switch energy {
      case .calm: -1
      case .balanced: 0
      case .driving: 2
      }

    let randomIndex = Int(Self.mix(seed) % UInt64(profile.common.count))
    let biasedIndex = min(max(randomIndex + energyOffset, 0), profile.common.count - 1)
    var result = profile.common[biasedIndex]

    // An occasional related tempo keeps a long radio session alive without leaving the genre.
    if Self.mix(seed &+ 0x9E37_79B9_7F4A_7C15) % 11 == 0 {
      let surprise = Int(Self.mix(seed &+ 0xD1B5_4A32_D192_ED03) % 3) - 1
      result += surprise * profile.surpriseStep
    }

    return min(max(result, profile.range.lowerBound), profile.range.upperBound)
  }

  private struct Profile: Sendable {
    let common: [Int]
    let range: ClosedRange<Int>
    let surpriseStep: Int
  }

  private static let profiles: [String: Profile] = [
    "Ambient": Profile(common: [58, 64, 70, 76, 84], range: 50...96, surpriseStep: 6),
    "Lo-fi": Profile(common: [68, 74, 80, 86, 92], range: 62...100, surpriseStep: 6),
    "Light Rave": Profile(common: [112, 120, 128, 136, 144], range: 108...150, surpriseStep: 4),
    "Fantasy": Profile(common: [58, 68, 80, 96, 120], range: 50...132, surpriseStep: 8),
    "Dark Empire": Profile(common: [100, 112, 128, 144, 160], range: 92...168, surpriseStep: 8),
    "Pirate": Profile(common: [104, 112, 120, 128, 136], range: 96...144, surpriseStep: 8),
    "Rock": Profile(common: [96, 112, 124, 136, 148], range: 84...160, surpriseStep: 8),
    "Space Rock": Profile(common: [72, 88, 104, 120, 136], range: 64...148, surpriseStep: 8),
    "Metal": Profile(common: [104, 120, 136, 152, 168], range: 88...184, surpriseStep: 8),
    "Thrash Metal": Profile(common: [150, 162, 174, 186, 198], range: 142...210, surpriseStep: 8),
    "Cute": Profile(common: [88, 100, 112, 124, 136], range: 80...144, surpriseStep: 6),
    "Chaos": Profile(common: [71, 97, 127, 157, 191], range: 55...210, surpriseStep: 10),
    "Electronic": Profile(common: [96, 108, 118, 124, 130], range: 84...140, surpriseStep: 6),
    "Synthwave": Profile(common: [86, 94, 102, 110, 118], range: 78...126, surpriseStep: 6),
    "House": Profile(common: [116, 120, 124, 126, 130], range: 115...130, surpriseStep: 2),
    "Techno": Profile(common: [120, 126, 130, 134, 140], range: 120...140, surpriseStep: 2),
    "Hard Techno": Profile(common: [138, 142, 146, 150, 154], range: 136...158, surpriseStep: 2),
    "Industrial Techno": Profile(
      common: [136, 144, 150, 156, 160], range: 132...164, surpriseStep: 4),
    "Hardcore": Profile(common: [160, 168, 174, 182, 190], range: 156...196, surpriseStep: 4),
    "Psytrance": Profile(common: [138, 142, 145, 148, 150], range: 136...152, surpriseStep: 2),
    "Breakbeat": Profile(common: [118, 126, 132, 138, 146], range: 112...152, surpriseStep: 4),
    "Drum and Bass": Profile(common: [160, 166, 172, 176, 180], range: 160...180, surpriseStep: 2),
    "Cyberpunk": Profile(common: [96, 112, 124, 136, 160], range: 84...176, surpriseStep: 6),
    "Hip-hop": Profile(common: [62, 72, 82, 92, 100], range: 60...100, surpriseStep: 4),
    "Funk": Profile(common: [92, 100, 106, 112, 120], range: 84...126, surpriseStep: 4),
    "Jazz": Profile(common: [72, 88, 104, 120, 144], range: 60...168, surpriseStep: 8),
    "Classical": Profile(common: [56, 66, 76, 92, 116], range: 48...144, surpriseStep: 8),
    "Post-rock": Profile(common: [64, 76, 88, 100, 112], range: 58...124, surpriseStep: 6),
    "Cinematic": Profile(common: [56, 68, 80, 96, 116], range: 48...132, surpriseStep: 8),
  ]

  private static func mix(_ input: UInt64) -> UInt64 {
    var value = input &+ 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
