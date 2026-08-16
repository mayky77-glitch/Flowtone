import Foundation

public enum ModelTier: String, CaseIterable, Codable, Sendable {
  case light
  case quality
}

public struct HardwareProfile: Equatable, Sendable {
  public let isAppleSilicon: Bool
  public let physicalMemoryBytes: UInt64

  public init(isAppleSilicon: Bool, physicalMemoryBytes: UInt64) {
    self.isAppleSilicon = isAppleSilicon
    self.physicalMemoryBytes = physicalMemoryBytes
  }

  public static var current: HardwareProfile {
    #if arch(arm64)
      let appleSilicon = true
    #else
      let appleSilicon = false
    #endif

    return HardwareProfile(
      isAppleSilicon: appleSilicon,
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
    )
  }

  public var memoryGiB: Int {
    Int((physicalMemoryBytes + (1 << 30) - 1) / (1 << 30))
  }
}

public enum HardwareSupport: Equatable, Sendable {
  case unsupported(reason: String)
  case supported(recommended: ModelTier, warning: String?)
}

public struct ModelRecommender: Sendable {
  public init() {}

  public func recommendation(for hardware: HardwareProfile) -> HardwareSupport {
    guard hardware.isAppleSilicon else {
      return .unsupported(reason: "Flowtone нужен Mac с Apple Silicon.")
    }

    guard hardware.memoryGiB >= 8 else {
      return .unsupported(reason: "Лёгкой модели нужно не менее 8 ГБ объединённой памяти.")
    }

    if hardware.memoryGiB >= 24 {
      return .supported(recommended: .quality, warning: nil)
    }

    let warning =
      hardware.memoryGiB < 16
      ? "Поддержка 8 ГБ считается тестовой до бенчмарка устройства."
      : nil
    return .supported(recommended: .light, warning: warning)
  }
}
