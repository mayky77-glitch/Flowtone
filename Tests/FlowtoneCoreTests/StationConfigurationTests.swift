import Foundation
import Testing

@testable import FlowtoneCore

@Suite struct StationConfigurationTests {
  @Test func validationCleansGenresAndVibe() throws {
    let input = StationConfiguration(
      genres: [" Ambient ", "Lo-fi", "Ambient"],
      energy: .calm,
      tempoBPM: 82,
      mood: .focused,
      vibe: " rain\n outside ",
      genrePresetIDs: [" Ambient ": " warm-pads-steady ", "Rock": "classic-steady"]
    )

    let validated = try input.validated()

    #expect(validated.genres == ["Ambient", "Lo-fi"])
    #expect(validated.vibe == "rain outside")
    #expect(validated.genrePresetIDs == ["Ambient": "warm-pads-steady"])
  }

  @Test func validationRejectsMissingGenre() {
    let input = StationConfiguration(
      genres: ["  "],
      energy: .calm,
      tempoBPM: 82,
      mood: .focused
    )

    do {
      _ = try input.validated()
      Issue.record("Expected missingGenre error")
    } catch {
      #expect(error as? StationConfigurationError == .missingGenre)
    }
  }

  @Test func promptComposerIncludesControlsAndInstrumentalConstraint() throws {
    let input = StationConfiguration(
      genres: ["ambient", "lo-fi"],
      energy: .balanced,
      tempoBPM: 90,
      mood: .dreamy,
      vibe: "late-night rain"
    )

    let composer = PromptComposer()
    let prompt = try composer.compose(from: input)

    #expect(prompt.contains("ambient blended with lo-fi"))
    #expect(prompt.contains("90 BPM"))
    #expect(prompt.contains("instrumental background music for deep work"))
    #expect(prompt.contains("late-night rain"))
    #expect(composer.negativePrompt.contains("vocals"))
  }

  @Test func promptComposerUsesPresetAndDescribesIntentionalFusion() throws {
    let catalog = GenrePromptCatalog()
    let preset = try #require(catalog.presets(for: "Pirate").first)
    let input = StationConfiguration(
      genres: ["Pirate", "Fantasy"],
      energy: .driving,
      tempoBPM: 120,
      mood: .uplifting,
      genrePresetIDs: ["Pirate": preset.id]
    )

    let prompt = try PromptComposer().compose(from: input, seed: 17)

    #expect(prompt.contains(preset.productionPrompt))
    #expect(prompt.contains("intentional fusion"))
  }

  @Test func drivingIntentRequiresEnergyWithoutSacrificingForm() throws {
    let input = StationConfiguration(
      genres: ["Space Rock"],
      energy: .driving,
      tempoBPM: 136,
      mood: .uplifting
    )

    let prompt = try PromptComposer().compose(from: input, seed: 19)

    #expect(prompt.contains("very high energy"))
    #expect(prompt.contains("punchy transient attack"))
    #expect(prompt.contains("active bass movement"))
    #expect(prompt.contains("coherent form"))
    #expect(prompt.contains("decisive full-band return"))
  }

  @Test func decoderAcceptsOlderConfigurationWithoutPresetMap() throws {
    let json =
      #"{"genres":["Ambient"],"energy":"calm","tempoBPM":70,"mood":"focused"}"#
    let decoded = try JSONDecoder().decode(
      StationConfiguration.self,
      from: try #require(json.data(using: .utf8))
    )

    #expect(decoded.genrePresetIDs.isEmpty)
  }
}
