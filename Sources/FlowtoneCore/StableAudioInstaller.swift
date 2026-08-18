import CryptoKit
import Foundation

public enum StableAudioInstallationPhase: String, Sendable {
  case preparing
  case downloadingTools
  case downloadingRuntime
  case installingRuntime
  case downloadingModel
  case validating
  case completed
}

public struct StableAudioInstallationProgress: Equatable, Sendable {
  public let phase: StableAudioInstallationPhase
  public let title: String
  public let detail: String
  public let completedFraction: Double

  public init(
    phase: StableAudioInstallationPhase,
    title: String,
    detail: String,
    completedFraction: Double
  ) {
    self.phase = phase
    self.title = title
    self.detail = detail
    self.completedFraction = min(max(completedFraction, 0), 1)
  }
}

public struct StableAudioInstallationManifest: Sendable {
  public static let sourceRevision = "a0b57f5483c4588f827f3552b7d5c6ca2a9687be"
  public static let sourceArchiveSHA256 =
    "57c5f639e4e55ec2357cd193cc40ebf7749e4478dc01ef26ce2c541ed1ece380"
  public static let uvVersion = "0.12.5"
  public static let uvArchiveSHA256 =
    "5bb0e5fe008a773c3dbcb97ff79cd89e1241464fe9d2f986d52ad8f1b037bd62"
  public static let requiredFreeDiskBytes: Int64 = 4 * 1_024 * 1_024 * 1_024

  public static let requiredWeightNames = [
    "dit_sm-music_f16.npz",
    "same_s_decoder_f32.npz",
    "same_s_encoder_f32.npz",
    "t5gemma_f16.npz",
  ]

  public static let runtimePackages = [
    "mlx==0.32.0",
    "numpy==2.4.6",
    "sentencepiece==0.2.2",
    "huggingface_hub==1.27.0",
    "soundfile==0.14.0",
  ]

  public let applicationSupportRoot: URL

  public init(applicationSupportRoot: URL = ModelRuntimeCatalog.defaultApplicationSupportRoot) {
    self.applicationSupportRoot = applicationSupportRoot
  }

  public var sourceArchiveRemoteURL: URL {
    URL(
      string:
        "https://github.com/Stability-AI/stable-audio-3/archive/\(Self.sourceRevision).zip"
    )!
  }

  public var uvArchiveRemoteURL: URL {
    URL(
      string:
        "https://github.com/astral-sh/uv/releases/download/\(Self.uvVersion)/uv-aarch64-apple-darwin.tar.gz"
    )!
  }

  public var runtimeRoot: URL {
    applicationSupportRoot
      .appendingPathComponent("Runtime", isDirectory: true)
      .appendingPathComponent("stable-audio-3", isDirectory: true)
  }

  public var mlxRoot: URL {
    runtimeRoot
      .appendingPathComponent("optimized", isDirectory: true)
      .appendingPathComponent("mlx", isDirectory: true)
  }

  public var installerRoot: URL {
    applicationSupportRoot.appendingPathComponent("Installer", isDirectory: true)
  }

  public var downloadsRoot: URL {
    installerRoot.appendingPathComponent("Downloads", isDirectory: true)
  }

  public var extractedSourceRoot: URL {
    installerRoot.appendingPathComponent("ExtractedSource", isDirectory: true)
  }

  public var toolsRoot: URL {
    installerRoot.appendingPathComponent("Tools", isDirectory: true)
  }

  public var uvExecutableURL: URL {
    toolsRoot
      .appendingPathComponent("uv-aarch64-apple-darwin", isDirectory: true)
      .appendingPathComponent("uv")
  }

  public var sourceArchiveURL: URL {
    downloadsRoot.appendingPathComponent("stable-audio-3-\(Self.sourceRevision).zip")
  }

  public var uvArchiveURL: URL {
    downloadsRoot.appendingPathComponent("uv-\(Self.uvVersion)-arm64.tar.gz")
  }

  public var pythonInstallRoot: URL {
    runtimeRoot.deletingLastPathComponent().appendingPathComponent("Python", isDirectory: true)
  }

  public var uvCacheRoot: URL {
    applicationSupportRoot
      .appendingPathComponent("Cache", isDirectory: true)
      .appendingPathComponent("uv", isDirectory: true)
  }

  public var huggingFaceRoot: URL {
    applicationSupportRoot
      .appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent("HuggingFace", isDirectory: true)
  }

  public var launcherURL: URL {
    applicationSupportRoot.appendingPathComponent(
      ModelRuntimeCatalog.stableAudioExecutableName)
  }

  public var installLogURL: URL {
    installerRoot.appendingPathComponent("stable-audio-install.log")
  }

  public var markerURL: URL {
    installerRoot.appendingPathComponent("installation-in-progress")
  }

  public var requiredWeightURLs: [URL] {
    Self.requiredWeightNames.map {
      mlxRoot
        .appendingPathComponent("models", isDirectory: true)
        .appendingPathComponent("mlx", isDirectory: true)
        .appendingPathComponent($0)
    }
  }

  public func launcherScript() -> String {
    let python = Self.shellQuote(
      mlxRoot.appendingPathComponent(".venv/bin/python").path)
    let script = Self.shellQuote(
      mlxRoot.appendingPathComponent("scripts/sa3_mlx.py").path)
    let workingDirectory = Self.shellQuote(mlxRoot.path)
    let modelCache = Self.shellQuote(huggingFaceRoot.path)
    return """
      #!/usr/bin/env bash
      set -euo pipefail

      export HF_HOME=\(modelCache)
      export HF_HUB_OFFLINE=1
      export TRANSFORMERS_OFFLINE=1
      export HF_DATASETS_OFFLINE=1
      export HF_HUB_DISABLE_IMPLICIT_TOKEN=1
      export TOKENIZERS_PARALLELISM=false

      cd \(workingDirectory)
      exec \(python) \(script) "$@"
      """
  }

  public func isComplete(fileManager: FileManager = .default) -> Bool {
    guard fileManager.isExecutableFile(atPath: launcherURL.path) else { return false }
    guard fileManager.isExecutableFile(atPath: mlxRoot.appendingPathComponent("sa3").path)
    else { return false }
    guard
      fileManager.isExecutableFile(
        atPath:
          mlxRoot
          .appendingPathComponent(".venv", isDirectory: true)
          .appendingPathComponent("bin", isDirectory: true)
          .appendingPathComponent("python").path)
    else { return false }

    return requiredWeightURLs.allSatisfy { url in
      guard fileManager.fileExists(atPath: url.path) else { return false }
      let attributes = try? fileManager.attributesOfItem(atPath: url.path)
      return (attributes?[.size] as? NSNumber)?.int64Value ?? 0 > 0
    }
  }

  public static func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }
}

public enum StableAudioInstallerError: LocalizedError, Sendable {
  case unsupportedMac
  case insufficientDiskSpace(required: Int64, available: Int64)
  case invalidHTTPResponse
  case downloadFailed(name: String)
  case checksumMismatch(name: String)
  case invalidArchive(name: String)
  case processFailed(stage: String, exitCode: Int32)
  case incompleteInstallation

  public var errorDescription: String? {
    switch self {
    case .unsupportedMac:
      "Автоматическая установка Stable Audio MLX доступна только на Mac с Apple Silicon."
    case .insufficientDiskSpace(let required, let available):
      "Для установки нужно не менее \(Self.gib(required)) ГБ свободного места. Сейчас доступно около \(Self.gib(available)) ГБ."
    case .invalidHTTPResponse:
      "Сервер вернул неожиданный ответ. Проверьте интернет и повторите установку."
    case .downloadFailed(let name):
      "Не удалось скачать \(name). Проверьте интернет и повторите попытку."
    case .checksumMismatch(let name):
      "Проверка файла «\(name)» не пройдена. Flowtone не будет запускать этот файл."
    case .invalidArchive(let name):
      "Архив «\(name)» повреждён или имеет неожиданную структуру."
    case .processFailed(let stage, let exitCode):
      "Не удалось завершить этап «\(stage)» (код \(exitCode)). Повторите установку."
    case .incompleteInstallation:
      "Установка завершилась не полностью: часть файлов модели отсутствует."
    }
  }

  private static func gib(_ bytes: Int64) -> String {
    String(format: "%.1f", Double(max(bytes, 0)) / 1_073_741_824)
  }
}

public final class StableAudioInstaller: @unchecked Sendable {
  public typealias ProgressHandler = @Sendable (StableAudioInstallationProgress) async -> Void

  public let manifest: StableAudioInstallationManifest
  private let fileManager: FileManager
  private let session: URLSession

  public init(
    manifest: StableAudioInstallationManifest = StableAudioInstallationManifest(),
    fileManager: FileManager = .default,
    session: URLSession = .shared
  ) {
    self.manifest = manifest
    self.fileManager = fileManager
    self.session = session
  }

  public func install(progress: @escaping ProgressHandler) async throws {
    if manifest.isComplete(fileManager: fileManager) {
      await progress(Self.completedProgress)
      return
    }

    try Task.checkCancellation()
    await progress(
      .init(
        phase: .preparing,
        title: "Проверяю Mac и свободное место",
        detail: "Нужно около 2 ГБ для модели и до 4 ГБ свободного места на установку.",
        completedFraction: 0.04
      ))
    try prepareDirectoriesAndCheckDisk()
    try Data(Self.timestamp.utf8).write(to: manifest.markerURL, options: .atomic)

    do {
      try Task.checkCancellation()
      await progress(
        .init(
          phase: .downloadingTools,
          title: "Загружаю системный помощник",
          detail: "Flowtone проверит контрольную сумму SHA-256 перед запуском.",
          completedFraction: 0.1
        ))
      try await obtainArtifact(
        remoteURL: manifest.uvArchiveRemoteURL,
        destinationURL: manifest.uvArchiveURL,
        expectedSHA256: StableAudioInstallationManifest.uvArchiveSHA256,
        displayName: "uv"
      )
      try extractUV()

      try Task.checkCancellation()
      await progress(
        .init(
          phase: .downloadingRuntime,
          title: "Загружаю официальный MLX runtime",
          detail: "Используется зафиксированная версия Stability AI.",
          completedFraction: 0.2
        ))
      try await obtainArtifact(
        remoteURL: manifest.sourceArchiveRemoteURL,
        destinationURL: manifest.sourceArchiveURL,
        expectedSHA256: StableAudioInstallationManifest.sourceArchiveSHA256,
        displayName: "Stable Audio 3"
      )
      try extractRuntimeSource()

      try Task.checkCancellation()
      await progress(
        .init(
          phase: .installingRuntime,
          title: "Настраиваю локальный движок",
          detail: "Flowtone устанавливает Python и MLX только в свою папку.",
          completedFraction: 0.32
        ))
      try await runOfficialInstaller(progress: progress)

      try Task.checkCancellation()
      await progress(
        .init(
          phase: .validating,
          title: "Проверяю и подключаю модель",
          detail: "После этого генерация будет работать без интернета.",
          completedFraction: 0.92
        ))
      try installLauncherAndValidate()
      try? fileManager.removeItem(at: manifest.markerURL)
      cleanupDependencyCache()
      cleanupInstallerArtifacts()
      await progress(Self.completedProgress)
    } catch {
      cleanupIncompleteRuntime()
      throw error
    }
  }

  public static func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1_048_576) ?? Data()
      if data.isEmpty { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static let completedProgress = StableAudioInstallationProgress(
    phase: .completed,
    title: "Модель установлена и подключена",
    detail: "Stable Audio 3 Small готова к локальной генерации.",
    completedFraction: 1
  )

  private static var timestamp: String { ISO8601DateFormatter().string(from: Date()) }

  private func prepareDirectoriesAndCheckDisk() throws {
    #if arch(arm64)
      guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 else {
        throw StableAudioInstallerError.unsupportedMac
      }
    #else
      throw StableAudioInstallerError.unsupportedMac
    #endif

    try fileManager.createDirectory(
      at: manifest.applicationSupportRoot,
      withIntermediateDirectories: true
    )
    let values = try manifest.applicationSupportRoot.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey,
      .volumeAvailableCapacityKey,
    ])
    let available =
      values.volumeAvailableCapacityForImportantUsage
      ?? values.volumeAvailableCapacity.map(Int64.init)
      ?? Int64.max
    guard available >= StableAudioInstallationManifest.requiredFreeDiskBytes else {
      throw StableAudioInstallerError.insufficientDiskSpace(
        required: StableAudioInstallationManifest.requiredFreeDiskBytes,
        available: available
      )
    }

    for directory in [manifest.installerRoot, manifest.downloadsRoot, manifest.huggingFaceRoot] {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }

  private func obtainArtifact(
    remoteURL: URL,
    destinationURL: URL,
    expectedSHA256: String,
    displayName: String
  ) async throws {
    if fileManager.fileExists(atPath: destinationURL.path),
      try Self.sha256(of: destinationURL) == expectedSHA256
    {
      return
    }
    try? fileManager.removeItem(at: destinationURL)

    var request = URLRequest(url: remoteURL)
    request.timeoutInterval = 600
    let temporaryURL: URL
    let response: URLResponse
    do {
      (temporaryURL, response) = try await session.download(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw StableAudioInstallerError.downloadFailed(name: displayName)
    }
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      throw StableAudioInstallerError.invalidHTTPResponse
    }

    do {
      try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    } catch {
      throw StableAudioInstallerError.downloadFailed(name: displayName)
    }
    guard try Self.sha256(of: destinationURL) == expectedSHA256 else {
      try? fileManager.removeItem(at: destinationURL)
      throw StableAudioInstallerError.checksumMismatch(name: displayName)
    }
  }

  private func extractUV() throws {
    try? fileManager.removeItem(at: manifest.toolsRoot)
    try fileManager.createDirectory(at: manifest.toolsRoot, withIntermediateDirectories: true)
    try runProcessSynchronously(
      executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
      arguments: ["-xzf", manifest.uvArchiveURL.path, "-C", manifest.toolsRoot.path],
      environment: Self.baseEnvironment,
      stage: "распаковка системного помощника"
    )
    guard fileManager.isExecutableFile(atPath: manifest.uvExecutableURL.path) else {
      throw StableAudioInstallerError.invalidArchive(name: "uv")
    }
  }

  private func extractRuntimeSource() throws {
    try? fileManager.removeItem(at: manifest.extractedSourceRoot)
    try fileManager.createDirectory(
      at: manifest.extractedSourceRoot,
      withIntermediateDirectories: true
    )
    try runProcessSynchronously(
      executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
      arguments: [
        "-x", "-k", manifest.sourceArchiveURL.path, manifest.extractedSourceRoot.path,
      ],
      environment: Self.baseEnvironment,
      stage: "распаковка Stable Audio 3"
    )

    let extracted = manifest.extractedSourceRoot.appendingPathComponent(
      "stable-audio-3-\(StableAudioInstallationManifest.sourceRevision)",
      isDirectory: true
    )
    let expectedInstaller =
      extracted
      .appendingPathComponent("optimized/mlx/install.sh")
    guard fileManager.isExecutableFile(atPath: expectedInstaller.path) else {
      throw StableAudioInstallerError.invalidArchive(name: "Stable Audio 3")
    }

    if fileManager.fileExists(atPath: manifest.runtimeRoot.path) {
      try fileManager.removeItem(at: manifest.runtimeRoot)
    }
    try fileManager.createDirectory(
      at: manifest.runtimeRoot.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.moveItem(at: extracted, to: manifest.runtimeRoot)
  }

  private func runOfficialInstaller(progress: @escaping ProgressHandler) async throws {
    var environment = Self.baseEnvironment
    environment["PATH"] =
      "\(manifest.uvExecutableURL.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
    environment["UV_PYTHON_INSTALL_DIR"] = manifest.pythonInstallRoot.path
    environment["UV_CACHE_DIR"] = manifest.uvCacheRoot.path
    environment["UV_NO_PROGRESS"] = "1"
    environment["UV_NO_MODIFY_PATH"] = "1"
    environment["UV_LINK_MODE"] = "copy"
    environment["HF_HOME"] = manifest.huggingFaceRoot.path
    environment["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
    environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
    environment["HF_HUB_OFFLINE"] = "0"
    environment["TRANSFORMERS_OFFLINE"] = "0"
    environment["HF_DATASETS_OFFLINE"] = "0"
    environment["TOKENIZERS_PARALLELISM"] = "false"
    environment.removeValue(forKey: "HF_TOKEN")
    environment.removeValue(forKey: "HUGGING_FACE_HUB_TOKEN")

    let virtualEnvironment = manifest.mlxRoot.appendingPathComponent(".venv", isDirectory: true)
    let python = virtualEnvironment.appendingPathComponent("bin/python")
    try await runProcess(
      executableURL: manifest.uvExecutableURL,
      arguments: ["venv", "--seed", "--python", "3.11", virtualEnvironment.path],
      environment: environment,
      stage: "подготовка Python"
    )
    try await runProcess(
      executableURL: manifest.uvExecutableURL,
      arguments: ["pip", "install", "--python", python.path]
        + StableAudioInstallationManifest.runtimePackages,
      environment: environment,
      stage: "установка MLX"
    )

    await progress(
      .init(
        phase: .downloadingModel,
        title: "Загружаю Stable Audio 3 Small",
        detail: "Около 1,8 ГБ. Скорость зависит от соединения; уже загруженные файлы сохранятся.",
        completedFraction: 0.45
      ))
    environment["INSTALL_SKIP_PIP"] = "1"
    try await runProcess(
      executableURL: python,
      arguments: [
        manifest.mlxRoot.appendingPathComponent("scripts/install.py").path,
        "--download", "sm-music",
      ],
      environment: environment,
      stage: "загрузка Stable Audio 3 Small"
    )
  }

  private func installLauncherAndValidate() throws {
    let temporaryLauncher = manifest.installerRoot.appendingPathComponent("stable-audio-mlx.new")
    try Data(manifest.launcherScript().utf8).write(to: temporaryLauncher, options: .atomic)
    try fileManager.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: temporaryLauncher.path
    )
    try? fileManager.removeItem(at: manifest.launcherURL)
    try fileManager.moveItem(at: temporaryLauncher, to: manifest.launcherURL)

    guard manifest.isComplete(fileManager: fileManager) else {
      throw StableAudioInstallerError.incompleteInstallation
    }
    var environment = Self.baseEnvironment
    environment["HF_HUB_OFFLINE"] = "1"
    environment["TRANSFORMERS_OFFLINE"] = "1"
    environment["HF_DATASETS_OFFLINE"] = "1"
    try runProcessSynchronously(
      executableURL: manifest.launcherURL,
      arguments: ["--help"],
      environment: environment,
      stage: "проверка локального движка"
    )
  }

  private func runProcess(
    executableURL: URL,
    arguments: [String],
    environment: [String: String],
    stage: String
  ) async throws {
    let processBox = StableAudioInstallerProcessBox()
    try await withTaskCancellationHandler {
      try await Task.detached(priority: .utility) { [self] in
        try runProcessSynchronously(
          executableURL: executableURL,
          arguments: arguments,
          environment: environment,
          stage: stage,
          processBox: processBox
        )
      }.value
    } onCancel: {
      processBox.cancel()
    }
  }

  private func runProcessSynchronously(
    executableURL: URL,
    arguments: [String],
    environment: [String: String],
    stage: String,
    processBox: StableAudioInstallerProcessBox? = nil
  ) throws {
    if !fileManager.fileExists(atPath: manifest.installLogURL.path) {
      fileManager.createFile(atPath: manifest.installLogURL.path, contents: nil)
    }
    let logHandle = try FileHandle(forWritingTo: manifest.installLogURL)
    defer { try? logHandle.close() }
    try logHandle.seekToEnd()
    try logHandle.write(contentsOf: Data("\n[\(Self.timestamp)] \(stage)\n".utf8))

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = logHandle
    process.standardError = logHandle
    let cancellationRequested = processBox?.register(process) ?? false
    defer { processBox?.clear(process) }
    try process.run()
    if cancellationRequested { process.terminate() }
    process.waitUntilExit()

    if processBox?.isCancellationRequested == true {
      throw CancellationError()
    }
    guard process.terminationStatus == 0 else {
      throw StableAudioInstallerError.processFailed(
        stage: stage,
        exitCode: process.terminationStatus
      )
    }
  }

  private func cleanupIncompleteRuntime() {
    try? fileManager.removeItem(at: manifest.launcherURL)
    if fileManager.fileExists(atPath: manifest.markerURL.path) {
      try? fileManager.removeItem(at: manifest.runtimeRoot)
      try? fileManager.removeItem(at: manifest.markerURL)
    }
  }

  private func cleanupInstallerArtifacts() {
    try? fileManager.removeItem(at: manifest.sourceArchiveURL)
    try? fileManager.removeItem(at: manifest.uvArchiveURL)
    try? fileManager.removeItem(at: manifest.extractedSourceRoot)
    try? fileManager.removeItem(at: manifest.toolsRoot)
  }

  private func cleanupDependencyCache() {
    var environment = Self.baseEnvironment
    environment["UV_CACHE_DIR"] = manifest.uvCacheRoot.path
    try? runProcessSynchronously(
      executableURL: manifest.uvExecutableURL,
      arguments: ["cache", "clean"],
      environment: environment,
      stage: "очистка установочного кэша"
    )
    try? fileManager.removeItem(at: manifest.uvCacheRoot)
  }

  private static var baseEnvironment: [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    return environment
  }
}

private final class StableAudioInstallerProcessBox: @unchecked Sendable {
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
      if self.process === process { self.process = nil }
    }
  }

  func cancel() {
    let active = lock.withLock { () -> Process? in
      cancellationRequested = true
      return process
    }
    if active?.isRunning == true { active?.terminate() }
  }
}
