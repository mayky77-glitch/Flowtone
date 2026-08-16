import Testing

@testable import FlowtoneCore

@Suite struct StationConfigurationTests {
  @Test func validationCleansGenresAndVibe() throws {
    let input = StationConfiguration(
      genres: [" Ambient ", "Lo-fi", "Ambient"],
      energy: .calm,
      tempoBPM: 82,
      mood: .focused,
      vibe: " rain\n outside "
    )

    let validated = try input.validated()

    #expect(validated.genres == ["Ambient", "Lo-fi"])
    #expect(validated.vibe == "rain outside")
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
}
