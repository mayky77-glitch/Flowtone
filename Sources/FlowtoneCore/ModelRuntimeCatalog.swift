import Foundation

public struct ModelRuntimeCatalog: Sendable {
  public enum Availability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case unsupported(reason: String)
  }

  public static let stableAudioExecutableName = "stable-audio-mlx"

  public static var defaultApplicationSupportRoot: URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0].appendingPathComponent("Flowtone", isDirectory: true)
  }

  public let applicationSupportRoot: URL

  public init(applicationSupportRoot: URL = Self.defaultApplicationSupportRoot) {
    self.applicationSupportRoot = applicationSupportRoot
  }

  public var stableAudioExecutableURL: URL {
    applicationSupportRoot.appendingPathComponent(Self.stableAudioExecutableName)
  }

  public func availability(for tier: ModelTier) -> Availability {
    switch tier {
    case .light:
      return hasStableAudioExecutable
        ? .available
        : .unavailable(reason: "Stable Audio 3 не установлен в приложении.")
    case .quality:
      return .unsupported(
        reason: "Качественный tier недоступен: адаптер ACE-Step ещё не поддерживается.")
    }
  }

  public func stableAudioEngine() -> StableAudioMLXEngine? {
    guard availability(for: .light) == .available else {
      return nil
    }

    return StableAudioMLXEngine(executableURL: stableAudioExecutableURL)
  }

  private var hasStableAudioExecutable: Bool {
    var isDirectory: ObjCBool = false
    let path = stableAudioExecutableURL.path
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

    return exists && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
  }
}
