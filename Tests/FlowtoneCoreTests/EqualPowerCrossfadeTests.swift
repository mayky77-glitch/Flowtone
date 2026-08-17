import Foundation
import Testing

@testable import FlowtoneCore

@Suite struct EqualPowerCrossfadeTests {
  private let crossfade = EqualPowerCrossfade()

  @Test func gainsUseEqualPowerCurve() {
    let gains = crossfade.gains(for: 0.5)

    #expect(abs(gains.outgoing - sqrt(0.5)) < 0.000_001)
    #expect(abs(gains.incoming - sqrt(0.5)) < 0.000_001)
    #expect(abs(gains.outgoing * gains.outgoing + gains.incoming * gains.incoming - 1) < 0.000_001)
  }

  @Test func gainsClampProgressToUnitInterval() {
    let beforeStart = crossfade.gains(for: -0.5)
    let afterEnd = crossfade.gains(for: 1.5)

    #expect(beforeStart.outgoing == 1)
    #expect(beforeStart.incoming == 0)
    #expect(abs(afterEnd.outgoing) < 0.000_001)
    #expect(afterEnd.incoming == 1)
  }

  @Test func effectiveDurationUsesShortestRequestedLimit() {
    #expect(
      crossfade.effectiveDuration(
        requested: 12,
        currentDuration: 24,
        nextDuration: 40
      ) == 6
    )
    #expect(
      crossfade.effectiveDuration(
        requested: 4,
        currentDuration: 40,
        nextDuration: 36
      ) == 4
    )
  }

  @Test func effectiveDurationRejectsInvalidOrNonPositiveValues() {
    #expect(
      crossfade.effectiveDuration(requested: 0, currentDuration: 20, nextDuration: 20) == 0
    )
    #expect(
      crossfade.effectiveDuration(requested: 2, currentDuration: -20, nextDuration: 20) == 0
    )
    #expect(
      crossfade.effectiveDuration(requested: 2, currentDuration: .infinity, nextDuration: 20) == 0
    )
  }
}
