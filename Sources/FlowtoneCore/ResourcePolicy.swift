import Foundation

public enum FlowtoneThermalState: String, Codable, Sendable {
  case nominal
  case fair
  case serious
  case critical
}

public enum MemoryPressure: String, Codable, Sendable {
  case normal
  case warning
  case critical
}

public struct ResourceSnapshot: Equatable, Sendable {
  public let thermalState: FlowtoneThermalState
  public let memoryPressure: MemoryPressure
  public let lowPowerModeEnabled: Bool

  public init(
    thermalState: FlowtoneThermalState,
    memoryPressure: MemoryPressure,
    lowPowerModeEnabled: Bool
  ) {
    self.thermalState = thermalState
    self.memoryPressure = memoryPressure
    self.lowPowerModeEnabled = lowPowerModeEnabled
  }

  public static var current: ResourceSnapshot {
    let thermalState: FlowtoneThermalState =
      switch ProcessInfo.processInfo.thermalState {
      case .nominal: .nominal
      case .fair: .fair
      case .serious: .serious
      case .critical: .critical
      @unknown default: .serious
      }

    return ResourceSnapshot(
      thermalState: thermalState,
      memoryPressure: SystemMemoryPressureMonitor.shared.current,
      lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
    )
  }
}

public enum GenerationPermission: Equatable, Sendable {
  case allowed
  case deferred(reason: String)
}

public struct ResourcePolicy: Sendable {
  public init() {}

  public func permission(for snapshot: ResourceSnapshot) -> GenerationPermission {
    if snapshot.memoryPressure != .normal {
      return .deferred(reason: "Генерация приостановлена из-за нехватки памяти.")
    }

    switch snapshot.thermalState {
    case .serious, .critical:
      return .deferred(reason: "Генерация приостановлена, пока Mac не остынет.")
    case .nominal, .fair:
      break
    }

    if snapshot.lowPowerModeEnabled {
      return .deferred(reason: "Генерация приостановлена в режиме энергосбережения.")
    }

    return .allowed
  }
}
