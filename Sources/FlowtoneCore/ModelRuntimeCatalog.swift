import Foundation

public struct ModelRuntimeCatalog: Sendable {
  public enum Availability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case unsupported(reason: String)
  }

  public static let stableAudioExecutableName = "stable-audio-mlx"
  public static let aceStepExecutableName = "ace-step-flowtone"

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

  public var aceStepExecutableURL: URL {
    applicationSupportRoot.appendingPathComponent(Self.aceStepExecutableName)
  }

  public var modelRuntimePaths: String {
    "Stable Audio: \(stableAudioExecutableURL.path)\nACE-Step: \(aceStepExecutableURL.path)"
  }

  public var hasStableAudioExecutable: Bool {
    var isDirectory: ObjCBool = false
    let path = stableAudioExecutableURL.path
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

    return exists && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
  }

  public var installedModelTiers: Set<ModelTier> {
    let manifest = StableAudioInstallationManifest(applicationSupportRoot: applicationSupportRoot)
    return Set(ModelTier.allCases.filter { manifest.isModelInstalled($0) })
  }

  public var installedModelIDs: Set<MusicModelID> {
    let stable = installedModelTiers.map { tier in
      tier == .light ? MusicModelID.stableSmall : .stableMedium
    }
    let aceManifest = ACEStepInstallationManifest(applicationSupportRoot: applicationSupportRoot)
    let ace = [MusicModelID.aceTurbo, .aceLite, .acePro, .aceMax].filter {
      aceManifest.isModelInstalled($0)
    }
    return Set(stable + ace)
  }

  public func availability(for tier: ModelTier) -> Availability {
    let profile = StableAudioModelProfile.profile(for: tier)
    return installedModelTiers.contains(tier)
      ? .available
      : .unavailable(
        reason:
          "\(profile.title) не установлена. Откройте «Модели», чтобы скачать её на этот Mac."
      )
  }

  public func availability(for modelID: MusicModelID) -> Availability {
    let profile = MusicModelProfile.profile(for: modelID)
    return installedModelIDs.contains(modelID)
      ? .available
      : .unavailable(
        reason: "\(profile.title) не установлена. Откройте «Модели», чтобы скачать её на этот Mac."
      )
  }

  public func stableAudioEngine(for tier: ModelTier = .light) -> StableAudioMLXEngine? {
    guard availability(for: tier) == .available else {
      return nil
    }

    return StableAudioMLXEngine(executableURL: stableAudioExecutableURL, tier: tier)
  }

  public func engine(for modelID: MusicModelID) -> (any GenerationEngine)? {
    guard availability(for: modelID) == .available else { return nil }
    if let tier = modelID.stableAudioTier {
      return StableAudioMLXEngine(executableURL: stableAudioExecutableURL, tier: tier)
    }
    return ACEStepEngine(executableURL: aceStepExecutableURL, modelID: modelID)
  }
}
