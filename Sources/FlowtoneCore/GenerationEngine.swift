import Foundation

public enum RadioGenerationPolicy {
  public static let trackDurationSeconds = 120
}

public struct EngineDescriptor: Equatable, Sendable {
  public let id: String
  public let displayName: String
  public let tier: ModelTier
  public let isDevelopmentOnly: Bool

  public init(id: String, displayName: String, tier: ModelTier, isDevelopmentOnly: Bool) {
    self.id = id
    self.displayName = displayName
    self.tier = tier
    self.isDevelopmentOnly = isDevelopmentOnly
  }
}

public struct GenerationRequest: Equatable, Sendable {
  public let prompt: String
  public let negativePrompt: String
  public let durationSeconds: Int
  public let seed: UInt64
  public let outputDirectory: URL

  public init(
    prompt: String,
    negativePrompt: String,
    durationSeconds: Int,
    seed: UInt64,
    outputDirectory: URL
  ) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.durationSeconds = durationSeconds
    self.seed = seed
    self.outputDirectory = outputDirectory
  }
}

public struct GeneratedAudio: Equatable, Sendable {
  public let fileURL: URL
  public let durationSeconds: Int
  public let byteSize: Int64
  public let engineID: String
  public let elapsedSeconds: TimeInterval
  public let seed: UInt64

  public init(
    fileURL: URL,
    durationSeconds: Int,
    byteSize: Int64,
    engineID: String,
    elapsedSeconds: TimeInterval,
    seed: UInt64
  ) {
    self.fileURL = fileURL
    self.durationSeconds = durationSeconds
    self.byteSize = byteSize
    self.engineID = engineID
    self.elapsedSeconds = elapsedSeconds
    self.seed = seed
  }
}

public protocol GenerationEngine: Sendable {
  var descriptor: EngineDescriptor { get }
  func generate(_ request: GenerationRequest) async throws -> GeneratedAudio
}

public enum GenerationEngineError: Error, LocalizedError, Equatable {
  case invalidDuration(Int)
  case missingExecutable(String)
  case processFailed(exitCode: Int32, message: String)
  case outputMissing(String)

  public var errorDescription: String? {
    switch self {
    case .invalidDuration(let value):
      "Длительность должна быть от 1 до 120 секунд, сейчас: \(value)."
    case .missingExecutable(let path):
      "Исполняемый файл Stable Audio не найден: \(path)."
    case .processFailed(let exitCode, let message):
      "Stable Audio завершился с кодом \(exitCode): \(message)"
    case .outputMissing(let path):
      "Генерация завершилась, но файл не найден: \(path)."
    }
  }
}
