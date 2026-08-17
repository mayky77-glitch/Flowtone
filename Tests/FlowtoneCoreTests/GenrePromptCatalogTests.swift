import Testing

@testable import FlowtoneCore

@Suite("GenrePromptCatalog")
struct GenrePromptCatalogTests {
  @Test("Fantasy has five distinct historical and magical variants")
  func fantasyVariety() {
    let catalog = GenrePromptCatalog()
    let profiles = Set((0..<100).map { catalog.profile(for: "Fantasy", seed: UInt64($0)) })

    #expect(catalog.profileCount(for: "Fantasy") == 5)
    #expect(profiles.count == 5)
    #expect(profiles.contains(where: { $0.contains("historical fantasy") }))
    #expect(profiles.contains(where: { $0.contains("magical fantasy") }))
    #expect(profiles.contains(where: { $0.contains("heroic fantasy") }))
    #expect(profiles.contains(where: { $0.contains("dark fantasy") }))
    #expect(profiles.contains(where: { $0.contains("cave fantasy") }))
  }

  @Test(
    "Every station genre has multiple production profiles",
    arguments: [
      "Ambient", "Lo-fi", "Light Rave", "Fantasy", "Rock", "Metal", "Thrash Metal",
      "Cute", "Chaos", "Electronic", "Synthwave", "House", "Techno", "Drum and Bass",
      "Hip-hop", "Funk", "Jazz", "Classical", "Post-rock", "Cinematic",
    ])
  func allGenresAreProfiled(genre: String) {
    let catalog = GenrePromptCatalog()
    #expect(catalog.profileCount(for: genre) >= 3)
    #expect(catalog.profile(for: genre, seed: 1).isEmpty == false)
  }
}
