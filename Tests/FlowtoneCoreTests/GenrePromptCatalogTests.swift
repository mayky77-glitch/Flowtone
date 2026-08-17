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

  @Test("Pirate stays simple, jaunty and acoustic instead of cinematic")
  func pirateFolkIdentity() {
    let presets = GenrePromptCatalog().presets(for: "Pirate")

    #expect(presets.count == 16)
    #expect(presets.allSatisfy { $0.productionPrompt.contains("short repeated refrain") })
    #expect(presets.allSatisfy { $0.productionPrompt.contains("small dry acoustic ensemble") })
    #expect(presets.contains(where: { $0.productionPrompt.contains("four-chord folk loop") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("capstan rhythm") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("hornpipe rhythm") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("rowing sway") }))
    #expect(presets.allSatisfy { !$0.productionPrompt.contains("naval brass") })
    #expect(presets.allSatisfy { !$0.productionPrompt.contains("war drums") })
    #expect(
      presets.allSatisfy { !$0.productionPrompt.localizedCaseInsensitiveContains("Wellerman") })
  }

  @Test("Synthwave adds twenty analog-noir variations without copying film titles")
  func synthwaveAnalogNoirVariety() {
    let presets = GenrePromptCatalog().presets(for: "Synthwave")

    #expect(presets.count == 30)
    #expect(
      presets.contains(where: { $0.productionPrompt.contains("immense detuned synth-brass") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("industrial escalation") }))
    #expect(
      presets.contains(where: { $0.productionPrompt.contains("abrupt pockets of near-silence") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("monumental final release") }))
    #expect(
      presets.allSatisfy { !$0.productionPrompt.localizedCaseInsensitiveContains("Blade Runner") })
    #expect(
      presets.allSatisfy { !$0.productionPrompt.localizedCaseInsensitiveContains("Vangelis") })
  }

  @Test("Space Rock keeps a live rock core across sixteen psychedelic variants")
  func spaceRockIdentity() {
    let presets = GenrePromptCatalog().presets(for: "Space Rock")

    #expect(presets.count == 16)
    #expect(presets.allSatisfy { $0.productionPrompt.contains("live psychedelic rock trio") })
    #expect(presets.contains(where: { $0.productionPrompt.contains("motorik 4/4") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("volume-pedal guitar") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("fuzzy guitar riff") }))
    #expect(presets.contains(where: { $0.productionPrompt.contains("shifting meter") }))
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
        .reduce(0, +) == 350)
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
    #expect(driving.contains("vivid high-motion arrangement"))
    #expect(driving.contains("motif variation every eight bars"))
    #expect(driving.contains("stable tonal center"))
    #expect(calm != driving)
  }
}
