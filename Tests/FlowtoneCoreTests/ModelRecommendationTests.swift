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
}
