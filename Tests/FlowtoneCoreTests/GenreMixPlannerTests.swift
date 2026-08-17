import Testing

@testable import FlowtoneCore

@Suite("GenreMixPlanner")
struct GenreMixPlannerTests {
  @Test("Mix contains two to five distinct allowed genres")
  func validMix() {
    let allowed = Array(GenrePromptCatalog.supportedGenres.prefix(8))
    let planner = GenreMixPlanner()

    for seed in UInt64(1)...100 {
      let result = planner.mix(from: allowed, seed: seed)
      #expect((2...5).contains(result.count))
      #expect(Set(result).count == result.count)
      #expect(result.allSatisfy(allowed.contains))
    }
  }

  @Test("Mix is deterministic and tolerates a single genre")
  func deterministic() {
    let planner = GenreMixPlanner()
    let genres = ["Fantasy", "Pirate", "Cinematic", "Rock"]

    #expect(planner.mix(from: genres, seed: 42) == planner.mix(from: genres, seed: 42))
    #expect(planner.mix(from: ["Fantasy"], seed: 42) == ["Fantasy"])
  }
}
