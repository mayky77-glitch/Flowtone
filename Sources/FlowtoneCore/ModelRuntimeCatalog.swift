import Foundation

public struct ModelRuntimeCatalog: Sendable {
  public enum Availability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case unsupported(reason: String)
  }

  public static let stableAudioExecutableName = "stable-audio-mlx"

  public static let stableAudioRuntimeRelativePath =
    "Library/Application Support/Flowtone/\(stableAudioExecutableName)"

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

  public var stableAudioRuntimePath: String {
    stableAudioExecutableURL.path
  }

  public var hasStableAudioExecutable: Bool {
    var isDirectory: ObjCBool = false
    let path = stableAudioExecutableURL.path
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

    return exists && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
  }

  public func availability(for tier: ModelTier) -> Availability {
    switch tier {
    case .light:
      return hasStableAudioExecutable
        ? .available
        : .unavailable(
          reason: "Исполняемый модуль Stable Audio 3 не найден по пути \(stableAudioRuntimePath).")
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
}
