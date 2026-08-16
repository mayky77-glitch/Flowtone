import FlowtoneCore
import Foundation
import Testing

@Suite("TrackTitleGenerator")
struct TrackTitleGeneratorTests {
  @Test("Title is deterministic and reflects genre, mood, and vibe")
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
    #expect(first.contains("Ночной город"))
    #expect(first.contains("·"))
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

    #expect(track.title.contains("Зачарованный лес"))
    #expect(track.title.isEmpty == false)
  }
}
