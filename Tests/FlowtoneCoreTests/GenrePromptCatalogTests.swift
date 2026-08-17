import Testing

@testable import FlowtoneCore

@Suite("GenrePromptCatalog")
struct GenrePromptCatalogTests {
  @Test("Fantasy includes broad historical, magical and requested worlds")
  func fantasyVariety() {
    let catalog = GenrePromptCatalog()
    let presets = catalog.presets(for: "Fantasy")

    #expect(presets.count >= 16)
    #expect(presets.contains(where: { $0.title.contains("Overlord") }))
    #expect(presets.contains(where: { $0.title.contains("Skyrim") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("celesta") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("war drums") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("stone echoes") }))
  }

  @Test("Every station genre has at least ten unique presets")
  func allGenresAreProfiled() {
    let catalog = GenrePromptCatalog()
    for genre in GenrePromptCatalog.supportedGenres {
      let presets = catalog.presets(for: genre)
      #expect(presets.count >= 10, "\(genre) has too few presets")
      #expect(Set(presets.map(\.id)).count == presets.count)
      #expect(presets.allSatisfy { !$0.productionPrompt.isEmpty })
    }
    #expect(
      GenrePromptCatalog.supportedGenres
        .map { catalog.profileCount(for: $0) }
        .reduce(0, +) == 292)
  }

  @Test("Explicit preset wins over random seed without putting franchise names in the prompt")
  func explicitPreset() throws {
    let catalog = GenrePromptCatalog()
    let preset = try #require(
      catalog.presets(for: "Fantasy").first(where: { $0.title.contains("Skyrim") }))

    let prompt = catalog.profile(for: "Fantasy", seed: 99, presetID: preset.id)

    #expect(prompt == preset.productionPrompt)
    #expect(!prompt.localizedCaseInsensitiveContains("Skyrim"))
  }
}
