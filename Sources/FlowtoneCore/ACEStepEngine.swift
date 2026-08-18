import Foundation

public struct ACEStepModelConfiguration: Equatable, Sendable {
  public let modelID: MusicModelID
  public let ditModel: String
  public let languageModel: String?
  public let diffusionSteps: Int

  public static func configuration(for modelID: MusicModelID) -> Self? {
    switch modelID {
    case .aceTurbo:
      Self(modelID: modelID, ditModel: "acestep-v15-turbo", languageModel: nil, diffusionSteps: 8)
    case .aceLite:
      Self(
        modelID: modelID,
        ditModel: "acestep-v15-turbo",
        languageModel: "acestep-5Hz-lm-0.6B",
        diffusionSteps: 8
      )
    case .acePro:
      Self(
        modelID: modelID,
        ditModel: "acestep-v15-turbo",
        languageModel: "acestep-5Hz-lm-1.7B",
        diffusionSteps: 8
      )
    case .aceMax:
      Self(
        modelID: modelID,
        ditModel: "acestep-v15-xl-turbo",
        languageModel: "acestep-5Hz-lm-4B",
        diffusionSteps: 8
      )
    case .stableSmall, .stableMedium:
      nil
    }
  }
}

public struct ACEStepCommand: Sendable {
  public let modelID: MusicModelID

  public init(modelID: MusicModelID) {
    self.modelID = modelID
  }

  public func environment(inheriting base: [String: String] = ProcessInfo.processInfo.environment)
    -> [String: String]
  {
    var environment = base
    environment["HF_HUB_OFFLINE"] = "1"
    environment["TRANSFORMERS_OFFLINE"] = "1"
    environment["TOKENIZERS_PARALLELISM"] = "false"
    environment["ACESTEP_DOWNLOAD_SOURCE"] = "huggingface"
    environment.removeValue(forKey: "HF_TOKEN")
    environment.removeValue(forKey: "HUGGING_FACE_HUB_TOKEN")
    return environment
  }

  public func arguments(for request: GenerationRequest, outputURL: URL) throws -> [String] {
    guard (10...120).contains(request.durationSeconds) else {
      throw GenerationEngineError.invalidDuration(request.durationSeconds)
    }
    guard let configuration = ACEStepModelConfiguration.configuration(for: modelID) else {
      throw GenerationEngineError.processFailed(
        exitCode: -1, message: "Неизвестная модель ACE-Step.")
    }
    return [
      "--prompt", request.prompt,
      "--negative-prompt", request.negativePrompt,
      "--model", configuration.ditModel,
      "--lm", configuration.languageModel ?? "none",
      "--seconds", String(request.durationSeconds),
      "--steps", String(configuration.diffusionSteps),
      "--seed", String(request.seed),
      "--out", outputURL.path,
    ]
  }
}

public struct ACEStepEngine: GenerationEngine {
  public let descriptor: EngineDescriptor
  public let executableURL: URL
  public let modelID: MusicModelID

  public init(executableURL: URL, modelID: MusicModelID) {
    self.executableURL = executableURL
    self.modelID = modelID
    let profile = MusicModelProfile.profile(for: modelID)
    descriptor = EngineDescriptor(
      id: "ace-step-1.5-\(modelID.rawValue)",
      displayName: profile.title,
      tier: profile.minimumMemoryGiB >= 24 ? .quality : .light,
      isDevelopmentOnly: false
    )
  }

  public func generate(_ request: GenerationRequest) async throws -> GeneratedAudio {
    let processBox = ACEStepProcessBox()
    return try await withTaskCancellationHandler {
      try await Task.detached(priority: .utility) {
        try Self.run(
          executableURL: executableURL,
          modelID: modelID,
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
    modelID: MusicModelID,
    request: GenerationRequest,
    processBox: ACEStepProcessBox
  ) throws -> GeneratedAudio {
    let fileManager = FileManager.default
    guard fileManager.isExecutableFile(atPath: executableURL.path) else {
      throw GenerationEngineError.missingExecutable(executableURL.path)
    }
    try fileManager.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
    let outputURL = request.outputDirectory.appendingPathComponent(
      "flowtone-ace-\(modelID.rawValue)-\(request.seed).wav")

    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = executableURL
    process.arguments = try ACEStepCommand(modelID: modelID).arguments(
      for: request,
      outputURL: outputURL
    )
    process.environment = ACEStepCommand(modelID: modelID).environment()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    let startedAt = Date()
    let cancellationWasRequested = processBox.register(process)
    defer { processBox.clear(process) }
    try process.run()
    if cancellationWasRequested { process.terminate() }
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
      engineID: "ace-step-1.5-\(modelID.rawValue)",
      elapsedSeconds: Date().timeIntervalSince(startedAt),
      seed: request.seed
    )
  }
}

private final class ACEStepProcessBox: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?
  private var cancellationRequested = false

  var isCancellationRequested: Bool { lock.withLock { cancellationRequested } }

  func register(_ process: Process) -> Bool {
    lock.withLock {
      self.process = process
      return cancellationRequested
    }
  }

  func clear(_ process: Process) {
    lock.withLock {
      if self.process === process { self.process = nil }
    }
  }

  func cancel() {
    let activeProcess = lock.withLock { () -> Process? in
      cancellationRequested = true
      return process
    }
    if activeProcess?.isRunning == true { activeProcess?.terminate() }
  }
}
