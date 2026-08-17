import FlowtoneCore
import Foundation
import Testing

@Suite("TrackTitleGenerator")
struct TrackTitleGeneratorTests {
  @Test("Title is deterministic, short, and does not copy a raw vibe fragment")
  func deterministicVibeTitle() {
    let configuration = StationConfiguration(
      genres: ["Light Rave"],
      energy: .driving,
      tempoBPM: 132,
      mood: .uplifting,
      vibe: "ночной город, дождь за окном"
    )

    let first = TrackTitleGenerator().title(for: configuration, seed: 42)
    let second = TrackTitleGenerator().title(for: configuration, seed: 42)

    #expect(first == second)
    #expect(first.contains("ночной город") == false)
    #expect(first.contains("·"))
    #expect(first.count <= 44)
  }

  @Test("Track library assigns a generated title during import")
  func titleAssignedDuringImport() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("flowtone-title-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let source = root.appendingPathComponent("source.wav")
    try Data(repeating: 1, count: 16).write(to: source)
    let library = TrackLibrary(rootDirectory: root)
    try await library.load()
    let track = try await library.importGeneratedAudio(
      GeneratedAudio(
        fileURL: source,
        durationSeconds: 8,
        byteSize: 16,
        engineID: "test",
        elapsedSeconds: 0.01,
        seed: 9
      ),
      configuration: StationConfiguration(
        genres: ["Fantasy"],
        energy: .calm,
        tempoBPM: 70,
        mood: .dreamy,
        vibe: "зачарованный лес"
      )
    )

    #expect(track.title.contains("зачарованный лес") == false)
    #expect(track.title.isEmpty == false)
    #expect(track.title.count <= 44)
  }

  @Test("Old title ending with a cut-off preposition is repaired")
  func repairsOldCutOffTitle() {
    let title = TrackTitleGenerator.normalizedExistingTitle(
      "Мягкий строб · Величавое темное фэнтези по",
      genres: ["Light Rave"],
      seed: 9
    )

    #expect(title.count <= 44)
    #expect(title.hasSuffix(" по") == false)
  }
}
