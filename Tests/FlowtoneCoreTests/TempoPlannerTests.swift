import Testing

@testable import FlowtoneCore

@Suite("TempoPlanner")
struct TempoPlannerTests {
  @Test("Genre tempo is deterministic and valid")
  func deterministicAndValid() {
    let planner = TempoPlanner()
    for genre in GenrePromptCatalog.supportedGenres {
      let first = planner.tempo(for: genre, energy: .balanced, seed: 42)
      let second = planner.tempo(for: genre, energy: .balanced, seed: 42)

      #expect(first == second)
      #expect((40...220).contains(first))
    }
  }

  @Test("Dance and beat genres stay inside recognized ranges")
  func recognizedRanges() {
    let planner = TempoPlanner()
    for seed in UInt64(1)...50 {
      #expect((115...130).contains(planner.tempo(for: "House", energy: .balanced, seed: seed)))
      #expect((120...140).contains(planner.tempo(for: "Techno", energy: .balanced, seed: seed)))
      #expect(
        (160...180).contains(
          planner.tempo(for: "Drum and Bass", energy: .balanced, seed: seed)))
      #expect((60...100).contains(planner.tempo(for: "Hip-hop", energy: .balanced, seed: seed)))
    }
  }

  @Test("Different seeds provide controlled variety")
  func variety() {
    let planner = TempoPlanner()
    let values = Set(
      (1...40).map { planner.tempo(for: "Fantasy", energy: .balanced, seed: UInt64($0)) })
    #expect(values.count >= 4)
  }
}
