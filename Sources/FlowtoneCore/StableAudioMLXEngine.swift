import Foundation

public struct StableAudioMLXCommand: Sendable {
  public init() {}

  public func arguments(for request: GenerationRequest, outputURL: URL) throws -> [String] {
    guard (1...120).contains(request.durationSeconds) else {
      throw GenerationEngineError.invalidDuration(request.durationSeconds)
    }

    return [
      "--prompt", request.prompt,
      "--negative-prompt", request.negativePrompt,
      "--dit", "sm-music",
      "--decoder", "same-s",
      "--seconds", String(request.durationSeconds),
      "--steps", "8",
      "--seed", String(request.seed),
      "--out", outputURL.path,
    ]
  }
}

public struct StableAudioMLXEngine: GenerationEngine {
  public let descriptor = EngineDescriptor(
    id: "stable-audio-3-small-mlx",
    displayName: "Stable Audio 3 Small (MLX)",
    tier: .light,
    isDevelopmentOnly: false
  )

  public let executableURL: URL

  public init(executableURL: URL) {
    self.executableURL = executableURL
  }

  public func generate(_ request: GenerationRequest) async throws -> GeneratedAudio {
    let executableURL = executableURL
    return try await Task.detached(priority: .utility) {
      try Self.run(executableURL: executableURL, request: request)
    }.value
  }

  private static func run(executableURL: URL, request: GenerationRequest) throws -> GeneratedAudio {
    let fileManager = FileManager.default
    guard fileManager.isExecutableFile(atPath: executableURL.path) else {
      throw GenerationEngineError.missingExecutable(executableURL.path)
    }

    try fileManager.createDirectory(
      at: request.outputDirectory,
      withIntermediateDirectories: true
    )

    let outputURL = request.outputDirectory
      .appendingPathComponent("flowtone-sa3-\(request.seed).wav")
    let arguments = try StableAudioMLXCommand().arguments(
      for: request,
      outputURL: outputURL
    )

    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    let startedAt = Date()
    try process.run()
    process.waitUntilExit()

    let stderr = String(
      decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    guard process.terminationStatus == 0 else {
      throw GenerationEngineError.processFailed(
        exitCode: process.terminationStatus,
        message: String(stderr.prefix(2_000))
      )
    }

    guard fileManager.fileExists(atPath: outputURL.path) else {
      throw GenerationEngineError.outputMissing(outputURL.path)
    }

    let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
    let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

    return GeneratedAudio(
      fileURL: outputURL,
      durationSeconds: request.durationSeconds,
      byteSize: byteSize,
      engineID: "stable-audio-3-small-mlx",
      elapsedSeconds: Date().timeIntervalSince(startedAt),
      seed: request.seed
    )
  }
}
