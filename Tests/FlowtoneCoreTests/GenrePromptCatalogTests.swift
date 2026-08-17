import Testing

@testable import FlowtoneCore

@Suite("GenrePromptCatalog")
struct GenrePromptCatalogTests {
  @Test("Fantasy includes broad historical, magical and northern reference-backed worlds")
  func fantasyVariety() {
    let catalog = GenrePromptCatalog()
    let presets = catalog.presets(for: "Fantasy")

    #expect(presets.count >= 18)
    #expect(presets.contains(where: { $0.title.contains("Skyrim") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("celesta") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("war drums") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("stone echoes") }))
  }

  @Test("Dark Empire is a separate varied genre without franchise names in prompts")
  func darkEmpireVariety() {
    let presets = GenrePromptCatalog().presets(for: "Dark Empire")

    #expect(presets.count >= 12)
    #expect(presets.contains(where: { $0.productionPrompt.contains("pipe organ") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("swing pulse") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("industrial electronic") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("somber piano") }))
    #expect(
      presets.allSatisfy { !$0.productionPrompt.localizedCaseInsensitiveContains("Overlord") })
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
        .reduce(0, +) == 314)
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

  @Test("Automatic profile keeps the archetype random but follows station energy")
  func automaticArrangementFollowsEnergy() {
    let catalog = GenrePromptCatalog()
    let calm = catalog.profile(for: "Dark Empire", seed: 77, energy: .calm)
    let driving = catalog.profile(for: "Dark Empire", seed: 77, energy: .driving)

    #expect(calm.contains("controlled radio arrangement"))
    #expect(driving.contains("active arrangement"))
    #expect(calm != driving)
  }
}
