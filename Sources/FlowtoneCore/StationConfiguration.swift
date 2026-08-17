import Foundation

public enum EnergyLevel: String, CaseIterable, Codable, Sendable {
  case calm
  case balanced
  case driving

  public var promptValue: String {
    switch self {
    case .calm: "low energy, restrained dynamics"
    case .balanced: "balanced energy, steady dynamics"
    case .driving:
      "very high energy, urgent forward momentum, assertive full-range dynamics, punchy transient attack, active bass movement and a clear peak while preserving tonal center and coherent form"
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
  public var genrePresetIDs: [String: String]

  public init(
    genres: [String],
    energy: EnergyLevel,
    tempoBPM: Int,
    mood: StationMood,
    vibe: String? = nil,
    genrePresetIDs: [String: String] = [:]
  ) {
    self.genres = genres
    self.energy = energy
    self.tempoBPM = tempoBPM
    self.mood = mood
    self.vibe = vibe
    self.genrePresetIDs = genrePresetIDs
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
    let cleanPresetIDs: [String: String] = Dictionary(
      uniqueKeysWithValues: genrePresetIDs.compactMap { genre, presetID in
        let cleanGenre = Self.cleanText(genre)
        let cleanPresetID = Self.cleanText(presetID)
        guard cleanGenres.contains(cleanGenre), !cleanPresetID.isEmpty else { return nil }
        return (cleanGenre, cleanPresetID)
      }
    )

    return StationConfiguration(
      genres: cleanGenres,
      energy: energy,
      tempoBPM: tempoBPM,
      mood: mood,
      vibe: cleanVibe,
      genrePresetIDs: cleanPresetIDs
    )
  }

  private enum CodingKeys: String, CodingKey {
    case genres, energy, tempoBPM, mood, vibe, genrePresetIDs
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    genres = try container.decode([String].self, forKey: .genres)
    energy = try container.decode(EnergyLevel.self, forKey: .energy)
    tempoBPM = try container.decode(Int.self, forKey: .tempoBPM)
    mood = try container.decode(StationMood.self, forKey: .mood)
    vibe = try container.decodeIfPresent(String.self, forKey: .vibe)
    genrePresetIDs =
      try container.decodeIfPresent([String: String].self, forKey: .genrePresetIDs) ?? [:]
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(genres, forKey: .genres)
    try container.encode(energy, forKey: .energy)
    try container.encode(tempoBPM, forKey: .tempoBPM)
    try container.encode(mood, forKey: .mood)
    try container.encodeIfPresent(vibe, forKey: .vibe)
    if !genrePresetIDs.isEmpty {
      try container.encode(genrePresetIDs, forKey: .genrePresetIDs)
    }
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
