import FlowtoneCore
import Foundation
import Testing

@Suite("TrackTitleGenerator")
struct TrackTitleGeneratorTests {
  @Test("Title is deterministic, semantic, and limited to ten words")
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
    #expect(
      first.lowercased().contains("зеркалах") || first.lowercased().contains("фонари")
    )
    #expect(first.contains("·") == false)
    #expect(first.split(whereSeparator: \.isWhitespace).count <= 10)
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
    #expect(
      track.title.lowercased().contains("дверью")
        || track.title.lowercased().contains("старые карты")
    )
    #expect(track.title.split(whereSeparator: \.isWhitespace).count <= 10)
  }

  @Test("Old title ending with a cut-off preposition is repaired")
  func repairsOldCutOffTitle() {
    let title = TrackTitleGenerator.normalizedExistingTitle(
      "Мягкий строб · Величавое темное фэнтези по",
      genres: ["Light Rave"],
      seed: 9
    )

    #expect(title.split(whereSeparator: \.isWhitespace).count <= 10)
    #expect(title.hasSuffix(" по") == false)
  }

  @Test("Generated and migrated titles avoid repeated content words")
  func avoidsRepeatedContentWords() {
    let configuration = StationConfiguration(
      genres: ["Ambient"],
      energy: .calm,
      tempoBPM: 72,
      mood: .focused
    )

    for seed in 0..<30 {
      let title = TrackTitleGenerator().title(for: configuration, seed: UInt64(seed))
      #expect(title.components(separatedBy: "горизонт").count <= 2)
    }

    let repaired = TrackTitleGenerator.normalizedExistingTitle(
      "Тихий горизонт в тихом движении к ясному горизонту",
      genres: ["Ambient"],
      seed: 12
    )
    #expect(repaired != "Тихий горизонт в тихом движении к ясному горизонту")
  }

  @Test("Driving titles vary and legacy exact-acceleration wording is repaired")
  func drivingTitleVariety() {
    let configuration = StationConfiguration(
      genres: ["Synthwave"],
      energy: .driving,
      tempoBPM: 118,
      mood: .focused
    )
    let titles = (0..<40).map {
      TrackTitleGenerator().title(for: configuration, seed: UInt64($0))
    }

    #expect(Set(titles).count >= 20)
    let literalTerms = ["ритм", "разгон", "строб", "рейв", "бит", "грув"]
    #expect(
      titles.allSatisfy { title in
        literalTerms.allSatisfy { !title.localizedCaseInsensitiveContains($0) }
      })

    let repaired = TrackTitleGenerator.normalizedExistingTitle(
      "Ночной протокол на точном разгоне",
      genres: ["Synthwave"],
      seed: 4
    )
    #expect(!repaired.localizedCaseInsensitiveContains("на точном разгоне"))
  }
}
