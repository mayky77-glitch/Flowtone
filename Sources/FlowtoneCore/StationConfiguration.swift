import Foundation

public enum EnergyLevel: String, CaseIterable, Codable, Sendable {
  case calm
  case balanced
  case driving

  public var promptValue: String {
    switch self {
    case .calm: "low energy, restrained dynamics"
    case .balanced: "balanced energy, steady dynamics"
    case .driving: "high energy, driving dynamics"
    }
  }
}

public enum StationMood: String, CaseIterable, Codable, Sendable {
  case focused
  case warm
  case dreamy
  case dark
  case uplifting

  public var promptValue: String {
    switch self {
    case .focused: "focused and unobtrusive"
    case .warm: "warm and reassuring"
    case .dreamy: "dreamy and spacious"
    case .dark: "dark and introspective"
    case .uplifting: "uplifting and optimistic"
    }
  }
}

public struct StationConfiguration: Codable, Equatable, Sendable {
  public var genres: [String]
  public var energy: EnergyLevel
  public var tempoBPM: Int
  public var mood: StationMood
  public var vibe: String?

  public init(
    genres: [String],
    energy: EnergyLevel,
    tempoBPM: Int,
    mood: StationMood,
    vibe: String? = nil
  ) {
    self.genres = genres
    self.energy = energy
    self.tempoBPM = tempoBPM
    self.mood = mood
    self.vibe = vibe
  }

  public func validated() throws -> StationConfiguration {
    let cleanGenres = Array(
      Set(genres.map(Self.cleanText).filter { !$0.isEmpty })
    ).sorted()

    guard !cleanGenres.isEmpty else {
      throw StationConfigurationError.missingGenre
    }

    guard (40...220).contains(tempoBPM) else {
      throw StationConfigurationError.invalidTempo(tempoBPM)
    }

    let cleanVibe = vibe.map(Self.cleanText).flatMap { $0.isEmpty ? nil : $0 }

    return StationConfiguration(
      genres: cleanGenres,
      energy: energy,
      tempoBPM: tempoBPM,
      mood: mood,
      vibe: cleanVibe
    )
  }

  private static func cleanText(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .split(whereSeparator: \Character.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public enum StationConfigurationError: Error, Equatable, LocalizedError {
  case missingGenre
  case invalidTempo(Int)

  public var errorDescription: String? {
    switch self {
    case .missingGenre:
      "Выберите хотя бы один жанр."
    case .invalidTempo(let value):
      "Темп должен быть от 40 до 220 уд/мин, сейчас: \(value)."
    }
  }
}
