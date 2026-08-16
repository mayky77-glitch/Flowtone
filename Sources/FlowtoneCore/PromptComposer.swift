import Foundation

public struct PromptComposer: Sendable {
  public init() {}

  public func compose(from configuration: StationConfiguration) throws -> String {
    let configuration = try configuration.validated()
    var parts = [
      configuration.genres.joined(separator: " blended with "),
      "\(configuration.tempoBPM) BPM",
      configuration.energy.promptValue,
      configuration.mood.promptValue,
      "instrumental background music for deep work",
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
