import Foundation

public struct TrackRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public var title: String
  public let fileName: String
  public let genres: [String]
  public let createdAt: Date
  public var lastPlayedAt: Date?
  public var playCount: Int
  public var isLiked: Bool
  public let durationSeconds: Int
  public let byteSize: Int64
  public let engineID: String
  public let seed: UInt64

  public init(
    id: UUID,
    title: String,
    fileName: String,
    genres: [String],
    createdAt: Date,
    lastPlayedAt: Date? = nil,
    playCount: Int = 0,
    isLiked: Bool = false,
    durationSeconds: Int,
    byteSize: Int64,
    engineID: String,
    seed: UInt64
  ) {
    self.id = id
    self.title = title
    self.fileName = fileName
    self.genres = genres
    self.createdAt = createdAt
    self.lastPlayedAt = lastPlayedAt
    self.playCount = playCount
    self.isLiked = isLiked
    self.durationSeconds = durationSeconds
    self.byteSize = byteSize
    self.engineID = engineID
    self.seed = seed
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, fileName, genres, createdAt, lastPlayedAt, playCount, isLiked
    case durationSeconds, byteSize, engineID, seed
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    fileName = try container.decode(String.self, forKey: .fileName)
    genres = try container.decode([String].self, forKey: .genres)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
    playCount = try container.decode(Int.self, forKey: .playCount)
    isLiked = try container.decode(Bool.self, forKey: .isLiked)
    durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
    byteSize = try container.decode(Int64.self, forKey: .byteSize)
    engineID = try container.decode(String.self, forKey: .engineID)
    seed = try container.decode(UInt64.self, forKey: .seed)
    let decodedTitle =
      try container.decodeIfPresent(String.self, forKey: .title)
      ?? TrackTitleGenerator.legacyTitle(genres: genres, seed: seed)
    title = TrackTitleGenerator.normalizedExistingTitle(
      decodedTitle,
      genres: genres,
      seed: seed
    )
  }
}

public struct GenreStorageStatistics: Equatable, Sendable {
  public let genre: String
  public let trackCount: Int
  public let byteSize: Int64

  public init(genre: String, trackCount: Int, byteSize: Int64) {
    self.genre = genre
    self.trackCount = trackCount
    self.byteSize = byteSize
  }
}

public struct LibraryStatistics: Equatable, Sendable {
  public let trackCount: Int
  public let likedTrackCount: Int
  public let byteSize: Int64
  public let genres: [GenreStorageStatistics]

  public init(
    trackCount: Int,
    likedTrackCount: Int,
    byteSize: Int64,
    genres: [GenreStorageStatistics]
  ) {
    self.trackCount = trackCount
    self.likedTrackCount = likedTrackCount
    self.byteSize = byteSize
    self.genres = genres
  }

  public static let empty = LibraryStatistics(
    trackCount: 0,
    likedTrackCount: 0,
    byteSize: 0,
    genres: []
  )
}

public struct CleanupReport: Equatable, Sendable {
  public let removedTrackCount: Int
  public let removedByteSize: Int64
  public let remainingByteSize: Int64
  public let limitStillExceeded: Bool

  public init(
    removedTrackCount: Int,
    removedByteSize: Int64,
    remainingByteSize: Int64,
    limitStillExceeded: Bool
  ) {
    self.removedTrackCount = removedTrackCount
    self.removedByteSize = removedByteSize
    self.remainingByteSize = remainingByteSize
    self.limitStillExceeded = limitStillExceeded
  }
}

public enum TrackLibraryError: Error, LocalizedError, Equatable {
  case trackNotFound(UUID)
  case audioFileMissing(String)

  public var errorDescription: String? {
    switch self {
    case .trackNotFound:
      "Запись не найдена в локальной библиотеке."
    case .audioFileMissing(let fileName):
      "Аудиофайл записи не найден: \(fileName)."
    }
  }
}

public actor TrackLibrary {
  public let rootDirectory: URL
  public let audioDirectory: URL
  public let incomingDirectory: URL

  private let indexURL: URL
  private let fileManager: FileManager
  private var tracksByID: [UUID: TrackRecord] = [:]
  private var isLoaded = false

  public init(rootDirectory: URL, fileManager: FileManager = .default) {
    self.rootDirectory = rootDirectory
    audioDirectory = rootDirectory.appendingPathComponent("Audio", isDirectory: true)
    incomingDirectory = rootDirectory.appendingPathComponent("Incoming", isDirectory: true)
    indexURL = rootDirectory.appendingPathComponent("library-v1.json")
    self.fileManager = fileManager
  }

  @discardableResult
  public func load() throws -> [TrackRecord] {
    try prepareDirectories()

    guard fileManager.fileExists(atPath: indexURL.path) else {
      tracksByID = [:]
      isLoaded = true
      return []
    }

    let data = try Data(contentsOf: indexURL)
    let index = try Self.decoder.decode(TrackLibraryIndex.self, from: data)
    let existingTracks = index.tracks.filter {
      fileManager.fileExists(atPath: audioDirectory.appendingPathComponent($0.fileName).path)
    }

    tracksByID = Dictionary(uniqueKeysWithValues: existingTracks.map { ($0.id, $0) })
    isLoaded = true

    if existingTracks.count != index.tracks.count {
      try persist()
    }

    return sortedTracks()
  }

  public func allTracks() throws -> [TrackRecord] {
    try ensureLoaded()
    return sortedTracks()
  }

  public func statistics() throws -> LibraryStatistics {
    try ensureLoaded()
    return Self.statistics(for: Array(tracksByID.values))
  }

  public func audioURL(for trackID: UUID) throws -> URL {
    try ensureLoaded()
    guard let track = tracksByID[trackID] else {
      throw TrackLibraryError.trackNotFound(trackID)
    }

    let url = audioDirectory.appendingPathComponent(track.fileName)
    guard fileManager.fileExists(atPath: url.path) else {
      throw TrackLibraryError.audioFileMissing(track.fileName)
    }
    return url
  }

  @discardableResult
  public func importGeneratedAudio(
    _ audio: GeneratedAudio,
    configuration: StationConfiguration,
    createdAt: Date = Date()
  ) throws -> TrackRecord {
    try ensureLoaded()
    let id = UUID()
    let fileExtension = audio.fileURL.pathExtension.isEmpty ? "wav" : audio.fileURL.pathExtension
    let fileName = "\(id.uuidString.lowercased()).\(fileExtension)"
    let destinationURL = audioDirectory.appendingPathComponent(fileName)

    guard fileManager.fileExists(atPath: audio.fileURL.path) else {
      throw TrackLibraryError.audioFileMissing(audio.fileURL.lastPathComponent)
    }

    try fileManager.moveItem(at: audio.fileURL, to: destinationURL)
    let record = TrackRecord(
      id: id,
      title: TrackTitleGenerator().title(for: configuration, seed: audio.seed),
      fileName: fileName,
      genres: configuration.genres,
      createdAt: createdAt,
      durationSeconds: audio.durationSeconds,
      byteSize: audio.byteSize,
      engineID: audio.engineID,
      seed: audio.seed
    )

    tracksByID[id] = record
    do {
      try persist()
    } catch {
      tracksByID.removeValue(forKey: id)
      try? fileManager.removeItem(at: destinationURL)
      throw error
    }
    return record
  }

  @discardableResult
  public func setLiked(_ liked: Bool, trackID: UUID) throws -> TrackRecord {
    try ensureLoaded()
    guard var track = tracksByID[trackID] else {
      throw TrackLibraryError.trackNotFound(trackID)
    }
    track.isLiked = liked
    tracksByID[trackID] = track
    try persist()
    return track
  }

  @discardableResult
  public func markPlayed(trackID: UUID, at date: Date = Date()) throws -> TrackRecord {
    try ensureLoaded()
    guard var track = tracksByID[trackID] else {
      throw TrackLibraryError.trackNotFound(trackID)
    }
    track.lastPlayedAt = date
    track.playCount += 1
    tracksByID[trackID] = track
    try persist()
    return track
  }

  public func randomCompatibleTrack(genres: Set<String>, excluding: Set<UUID> = []) throws
    -> TrackRecord?
  {
    try ensureLoaded()
    return compatibleTracks(genres: genres, excluding: excluding).randomElement()
  }

  public func leastRecentlyPlayedTrack(genres: Set<String>, excluding: Set<UUID> = []) throws
    -> TrackRecord?
  {
    try ensureLoaded()
    return compatibleTracks(genres: genres, excluding: excluding).min { lhs, rhs in
      let lhsDate = lhs.lastPlayedAt ?? .distantPast
      let rhsDate = rhs.lastPlayedAt ?? .distantPast
      if lhsDate != rhsDate { return lhsDate < rhsDate }
      if lhs.playCount != rhs.playCount { return lhs.playCount < rhs.playCount }
      return lhs.createdAt < rhs.createdAt
    }
  }

  @discardableResult
  public func removeTrack(trackID: UUID) throws -> TrackRecord {
    try ensureLoaded()
    guard let track = tracksByID[trackID] else {
      throw TrackLibraryError.trackNotFound(trackID)
    }

    let url = audioDirectory.appendingPathComponent(track.fileName)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    tracksByID.removeValue(forKey: trackID)
    try persist()
    return track
  }

  public func removeAllUnliked(protectedTrackIDs: Set<UUID> = []) throws -> CleanupReport {
    try ensureLoaded()
    let candidates = tracksByID.values.filter {
      !$0.isLiked && !protectedTrackIDs.contains($0.id)
    }
    return try remove(candidates, byteLimit: nil)
  }

  public func enforceStorageLimit(
    bytes limit: Int64,
    protectedTrackIDs: Set<UUID> = []
  ) throws -> CleanupReport {
    try ensureLoaded()
    let safeLimit = max(0, limit)
    let candidates = tracksByID.values
      .filter { !$0.isLiked && !protectedTrackIDs.contains($0.id) }
      .sorted {
        let lhsDate = $0.lastPlayedAt ?? $0.createdAt
        let rhsDate = $1.lastPlayedAt ?? $1.createdAt
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return $0.createdAt < $1.createdAt
      }
    return try remove(candidates, byteLimit: safeLimit)
  }

  private func compatibleTracks(genres: Set<String>, excluding: Set<UUID>) -> [TrackRecord] {
    tracksByID.values.filter { track in
      !excluding.contains(track.id)
        && (genres.isEmpty || !Set(track.genres).isDisjoint(with: genres))
    }
  }

  private func remove(_ candidates: [TrackRecord], byteLimit: Int64?) throws -> CleanupReport {
    var currentBytes = tracksByID.values.reduce(Int64(0)) { $0 + $1.byteSize }
    var removedBytes: Int64 = 0
    var removedCount = 0

    for track in candidates {
      if let byteLimit, currentBytes <= byteLimit { break }
      let url = audioDirectory.appendingPathComponent(track.fileName)
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
      tracksByID.removeValue(forKey: track.id)
      currentBytes -= track.byteSize
      removedBytes += track.byteSize
      removedCount += 1
    }

    if removedCount > 0 {
      try persist()
    }

    return CleanupReport(
      removedTrackCount: removedCount,
      removedByteSize: removedBytes,
      remainingByteSize: currentBytes,
      limitStillExceeded: byteLimit.map { currentBytes > $0 } ?? false
    )
  }

  private func ensureLoaded() throws {
    if !isLoaded {
      try load()
    }
  }

  private func prepareDirectories() throws {
    try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: incomingDirectory, withIntermediateDirectories: true)
  }

  private func sortedTracks() -> [TrackRecord] {
    tracksByID.values.sorted {
      if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  private func persist() throws {
    try prepareDirectories()
    let data = try Self.encoder.encode(
      TrackLibraryIndex(version: 1, tracks: sortedTracks())
    )
    try data.write(to: indexURL, options: .atomic)
  }

  private static func statistics(for tracks: [TrackRecord]) -> LibraryStatistics {
    var byGenre: [String: (count: Int, bytes: Int64)] = [:]
    for track in tracks {
      for genre in Set(track.genres) {
        let current = byGenre[genre] ?? (0, 0)
        byGenre[genre] = (current.count + 1, current.bytes + track.byteSize)
      }
    }

    let genres = byGenre.map {
      GenreStorageStatistics(genre: $0.key, trackCount: $0.value.count, byteSize: $0.value.bytes)
    }.sorted { $0.genre.localizedCaseInsensitiveCompare($1.genre) == .orderedAscending }

    return LibraryStatistics(
      trackCount: tracks.count,
      likedTrackCount: tracks.filter(\.isLiked).count,
      byteSize: tracks.reduce(Int64(0)) { $0 + $1.byteSize },
      genres: genres
    )
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  private static let decoder = JSONDecoder()
}

private struct TrackLibraryIndex: Codable {
  let version: Int
  let tracks: [TrackRecord]
}
