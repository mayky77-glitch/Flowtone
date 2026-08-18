import Testing

@testable import FlowtoneCore

@Suite struct ModelRecommendationTests {
  private let gibibyte = UInt64(1 << 30)

  @Test func rejectsIntel() {
    let hardware = HardwareProfile(
      isAppleSilicon: false,
      physicalMemoryBytes: 32 * gibibyte
    )

    guard case .unsupported = ModelRecommender().recommendation(for: hardware) else {
      Issue.record("Intel must be unsupported")
      return
    }
  }

  @Test func recommendsLightForSixteenGigabytes() {
    let hardware = HardwareProfile(
      isAppleSilicon: true,
      physicalMemoryBytes: 16 * gibibyte
    )

    #expect(
      ModelRecommender().recommendation(for: hardware)
        == .supported(
          recommended: .light,
          warning: nil
        ))
  }

  @Test func recommendsQualityAtTwentyFourGigabytes() {
    let hardware = HardwareProfile(
      isAppleSilicon: true,
      physicalMemoryBytes: 24 * gibibyte
    )

    #expect(
      ModelRecommender().recommendation(for: hardware)
        == .supported(
          recommended: .quality,
          warning: nil
        ))
  }

  @Test func everyHardwareGroupHasBaselineAndTwoComparedAlternatives() {
    for group in HardwareModelGroup.allCases {
      #expect(group.modelIDs.count >= 3)
      #expect(group.modelIDs.contains(group.baselineID))
      for modelID in group.modelIDs {
        let profile = MusicModelProfile.profile(for: modelID)
        #expect(!profile.betterThanBaseline.isEmpty)
        #expect(!profile.worseThanBaseline.isEmpty)
      }
    }
  }

  @Test func preferencesRoundTripEveryModel() {
    for modelID in MusicModelID.allCases {
      #expect(ModelPreference(modelID: modelID).requestedModelID == modelID)
    }
  }
}
