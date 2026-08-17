import FlowtoneCore
import Foundation
import Testing

@Suite("TrackLibrary")
struct TrackLibraryTests {
  @Test("Imported tracks and statistics survive a reload")
  func importAndReload() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = TrackLibrary(rootDirectory: root)
    try await library.load()

    let audio = try makeAudio(in: root, name: "source-a.wav", bytes: 128, seed: 11)
    let record = try await library.importGeneratedAudio(
      audio,
      configuration: configuration(genre: "Ambient")
    )

    let reloadedLibrary = TrackLibrary(rootDirectory: root)
    let tracks = try await reloadedLibrary.load()
    let statistics = try await reloadedLibrary.statistics()

    #expect(tracks == [record])
    #expect(statistics.trackCount == 1)
    #expect(statistics.byteSize == 128)
    #expect(
      statistics.genres == [
        GenreStorageStatistics(genre: "Ambient", trackCount: 1, byteSize: 128)
      ])
    let audioURL = try await reloadedLibrary.audioURL(for: record.id)
    #expect(FileManager.default.fileExists(atPath: audioURL.path))
  }

  @Test("Mass cleanup preserves liked tracks")
  func cleanupPreservesLikes() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = TrackLibrary(rootDirectory: root)
    try await library.load()

    let liked = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "liked.wav", bytes: 90, seed: 1),
      configuration: configuration(genre: "Jazz")
    )
    let unliked = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "unliked.wav", bytes: 70, seed: 2),
      configuration: configuration(genre: "Jazz")
    )
    try await library.setLiked(true, trackID: liked.id)

    let report = try await library.removeAllUnliked()
    let remaining = try await library.allTracks()

    #expect(report.removedTrackCount == 1)
    #expect(report.removedByteSize == 70)
    #expect(remaining.map(\.id) == [liked.id])
    #expect(!remaining.contains(where: { $0.id == unliked.id }))
  }

  @Test("Storage limit removes the oldest unliked track first")
  func storageLimitUsesLRUAndPreservesLikes() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = TrackLibrary(rootDirectory: root)
    try await library.load()

    let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    let liked = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "protected.wav", bytes: 100, seed: 1),
      configuration: configuration(genre: "Classical"),
      createdAt: baseDate
    )
    let oldest = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "oldest.wav", bytes: 100, seed: 2),
      configuration: configuration(genre: "Ambient"),
      createdAt: baseDate.addingTimeInterval(10)
    )
    let newest = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "newest.wav", bytes: 100, seed: 3),
      configuration: configuration(genre: "Electronic"),
      createdAt: baseDate.addingTimeInterval(20)
    )
    try await library.setLiked(true, trackID: liked.id)

    let report = try await library.enforceStorageLimit(bytes: 200)
    let remainingIDs = Set(try await library.allTracks().map(\.id))

    #expect(report.removedTrackCount == 1)
    #expect(report.limitStillExceeded == false)
    #expect(remainingIDs == [liked.id, newest.id])
    #expect(!remainingIDs.contains(oldest.id))
  }

  @Test("Least recently played selection prefers a compatible unheard track")
  func leastRecentlyPlayedSelection() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = TrackLibrary(rootDirectory: root)
    try await library.load()

    let heard = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "heard.wav", bytes: 50, seed: 1),
      configuration: configuration(genre: "Lo-fi")
    )
    let unheard = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "unheard.wav", bytes: 50, seed: 2),
      configuration: configuration(genre: "Lo-fi")
    )
    _ = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "other.wav", bytes: 50, seed: 3),
      configuration: configuration(genre: "Jazz")
    )
    try await library.markPlayed(trackID: heard.id)

    let selected = try await library.leastRecentlyPlayedTrack(genres: ["Lo-fi"])
    #expect(selected?.id == unheard.id)
  }

  @Test("Random selection respects active genres and exclusions")
  func randomSelectionRespectsGenresAndExclusions() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = TrackLibrary(rootDirectory: root)
    try await library.load()

    let excluded = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "excluded.wav", bytes: 50, seed: 1),
      configuration: configuration(genre: "Lo-fi")
    )
    let expected = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "expected.wav", bytes: 50, seed: 2),
      configuration: configuration(genre: "Lo-fi")
    )
    _ = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "other.wav", bytes: 50, seed: 3),
      configuration: configuration(genre: "Jazz")
    )

    for _ in 0..<12 {
      let selected = try await library.randomCompatibleTrack(
        genres: ["Lo-fi"],
        excluding: [excluded.id]
      )
      #expect(selected?.id == expected.id)
    }
  }

  @Test("Full radio cleanup keeps the live window and liked temporary tracks")
  func transientCleanupKeepsProtectedAndLikedTracks() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = TrackLibrary(rootDirectory: root)
    try await library.load()

    let persistent = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "persistent.wav", bytes: 60, seed: 1),
      configuration: configuration(genre: "Ambient")
    )
    let removable = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "removable.wav", bytes: 70, seed: 2),
      configuration: configuration(genre: "Ambient"),
      isTransient: true
    )
    let protected = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "protected.wav", bytes: 80, seed: 3),
      configuration: configuration(genre: "Ambient"),
      isTransient: true
    )
    let liked = try await library.importGeneratedAudio(
      makeAudio(in: root, name: "liked.wav", bytes: 90, seed: 4),
      configuration: configuration(genre: "Ambient"),
      isTransient: true
    )
    try await library.setLiked(true, trackID: liked.id)

    let report = try await library.removeUnlikedTransient(protectedTrackIDs: [protected.id])
    let remaining = try await library.allTracks()
    let remainingIDs = Set(remaining.map(\.id))

    #expect(report.removedTrackCount == 1)
    #expect(report.removedByteSize == removable.byteSize)
    #expect(remainingIDs == [persistent.id, protected.id, liked.id])
    #expect(remaining.first(where: { $0.id == liked.id })?.isTransient == true)

    let reloaded = try await TrackLibrary(rootDirectory: root).load()
    #expect(Set(reloaded.map(\.id)) == remainingIDs)
    #expect(reloaded.first(where: { $0.id == persistent.id })?.isTransient == false)
  }

  @Test("Startup cleanup removes orphaned incoming files only")
  func incomingCleanupRemovesOrphans() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = TrackLibrary(rootDirectory: root)
    try await library.load()

    let orphan = await library.incomingDirectory.appendingPathComponent("unfinished.wav")
    let nested = await library.incomingDirectory.appendingPathComponent(
      "working", isDirectory: true)
    try Data(repeating: 1, count: 32).write(to: orphan)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    let removedCount = try await library.removeOrphanedIncomingAudio()

    #expect(removedCount == 1)
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
    #expect(FileManager.default.fileExists(atPath: nested.path))
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("flowtone-library-tests-\(UUID().uuidString)", isDirectory: true)
  }

  private func configuration(genre: String) -> StationConfiguration {
    StationConfiguration(
      genres: [genre],
      energy: .calm,
      tempoBPM: 82,
      mood: .focused
    )
  }

  private func makeAudio(
    in directory: URL,
    name: String,
    bytes: Int,
    seed: UInt64
  ) throws -> GeneratedAudio {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try Data(repeating: UInt8(seed % 255), count: bytes).write(to: url)
    return GeneratedAudio(
      fileURL: url,
      durationSeconds: 8,
      byteSize: Int64(bytes),
      engineID: "test",
      elapsedSeconds: 0.01,
      seed: seed
    )
  }
}
