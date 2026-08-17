import Foundation

public struct StableAudioMLXCommand: Sendable {
  public init() {}

  public func environment(inheriting base: [String: String] = ProcessInfo.processInfo.environment)
    -> [String: String]
  {
    var environment = base
    environment["HF_HUB_OFFLINE"] = "1"
    environment["TRANSFORMERS_OFFLINE"] = "1"
    environment["HF_DATASETS_OFFLINE"] = "1"
    environment["TOKENIZERS_PARALLELISM"] = "false"
    return environment
  }

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
    let processBox = StableAudioProcessBox()
    return try await withTaskCancellationHandler {
      try await Task.detached(priority: .utility) {
        try Self.run(
          executableURL: executableURL,
          request: request,
          processBox: processBox
        )
      }.value
    } onCancel: {
      processBox.cancel()
    }
  }

  private static func run(
    executableURL: URL,
    request: GenerationRequest,
    processBox: StableAudioProcessBox
  ) throws -> GeneratedAudio {
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
    process.environment = StableAudioMLXCommand().environment()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    let startedAt = Date()
    let cancellationWasRequested = processBox.register(process)
    defer { processBox.clear(process) }
    try process.run()
    if cancellationWasRequested {
      process.terminate()
    }
    process.waitUntilExit()

    let stderr = String(
      decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    if processBox.isCancellationRequested {
      try? fileManager.removeItem(at: outputURL)
      throw CancellationError()
    }

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

private final class StableAudioProcessBox: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?
  private var cancellationRequested = false

  var isCancellationRequested: Bool {
    lock.withLock { cancellationRequested }
  }

  func register(_ process: Process) -> Bool {
    lock.withLock {
      self.process = process
      return cancellationRequested
    }
  }

  func clear(_ process: Process) {
    lock.withLock {
      if self.process === process {
        self.process = nil
      }
    }
  }

  func cancel() {
    let activeProcess = lock.withLock { () -> Process? in
      cancellationRequested = true
      return process
    }
    if activeProcess?.isRunning == true {
      activeProcess?.terminate()
    }
  }
}
