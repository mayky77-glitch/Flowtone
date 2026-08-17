import Foundation

public struct EqualPowerCrossfade: Sendable {
  public init() {}

  public func gains(for progress: Double) -> (outgoing: Double, incoming: Double) {
    let normalizedProgress = Self.normalized(progress)
    let angle = .pi * normalizedProgress / 2

    return (outgoing: cos(angle), incoming: sin(angle))
  }

  public func effectiveDuration(
    requested: TimeInterval,
    currentDuration: TimeInterval,
    nextDuration: TimeInterval
  ) -> TimeInterval {
    guard
      requested.isFinite,
      currentDuration.isFinite,
      nextDuration.isFinite,
      requested > 0,
      currentDuration > 0,
      nextDuration > 0
    else {
      return 0
    }

    return min(requested, currentDuration / 4, nextDuration / 4)
  }

  private static func normalized(_ progress: Double) -> Double {
    guard progress.isFinite else {
      return progress.sign == .minus ? 0 : 1
    }

    return min(max(progress, 0), 1)
  }
}
