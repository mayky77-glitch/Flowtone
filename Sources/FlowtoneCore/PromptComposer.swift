import Foundation

public struct PromptComposer: Sendable {
  public init() {}

  public func compose(from configuration: StationConfiguration, seed: UInt64 = 0) throws -> String {
    let configuration = try configuration.validated()
    let catalog = GenrePromptCatalog()
    let genreProfiles = configuration.genres.enumerated().map { index, genre in
      "\(genre): \(catalog.profile(for: genre, seed: seed &+ UInt64(index)))"
    }
    var parts = [
      configuration.genres.joined(separator: " blended with "),
      genreProfiles.joined(separator: "; "),
      "\(configuration.tempoBPM) BPM",
      configuration.energy.promptValue,
      configuration.mood.promptValue,
      "instrumental background music for deep work, strictly no lyrics and no voice",
      "coherent arrangement, smooth development, no abrupt ending",
    ]

    if let vibe = configuration.vibe {
      parts.append(vibe)
    }

    return parts.joined(separator: ", ")
  }

  public var negativePrompt: String {
    "vocals, singing, spoken word, speech, advertisement, audio logo, harsh clipping, long silence"
  }
}
