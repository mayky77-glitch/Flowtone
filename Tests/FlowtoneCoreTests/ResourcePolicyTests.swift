import Testing

@testable import FlowtoneCore

@Suite struct ResourcePolicyTests {
  @Test func allowsNominalResources() {
    let snapshot = ResourceSnapshot(
      thermalState: .nominal,
      memoryPressure: .normal,
      lowPowerModeEnabled: false
    )

    #expect(ResourcePolicy().permission(for: snapshot) == .allowed)
  }

  @Test func defersAtSeriousThermalState() {
    let snapshot = ResourceSnapshot(
      thermalState: .serious,
      memoryPressure: .normal,
      lowPowerModeEnabled: false
    )

    guard case .deferred = ResourcePolicy().permission(for: snapshot) else {
      Issue.record("Serious thermal state must defer generation")
      return
    }
  }

  @Test func memoryPressureWinsOverOtherwiseHealthyState() {
    let snapshot = ResourceSnapshot(
      thermalState: .nominal,
      memoryPressure: .warning,
      lowPowerModeEnabled: false
    )

    guard case .deferred(let reason) = ResourcePolicy().permission(for: snapshot) else {
      Issue.record("Memory pressure must defer generation")
      return
    }
    #expect(reason.contains("памят"))
  }
}
