import CryptoKit
import Foundation

public struct ACEStepInstallationManifest: Sendable {
  public static let sourceRevision = "14c0211d5a0653b0f63e27686f4c3f151b4d8629"
  public static let sourceArchiveSHA256 =
    "cdf69c060ed3a6bfddebbf21dd0c548ea7ddfdf0f3cebc20d2a572085970586e"
  public static let uvVersion = "0.12.5"
  public static let uvArchiveSHA256 =
    "5bb0e5fe008a773c3dbcb97ff79cd89e1241464fe9d2f986d52ad8f1b037bd62"

  public let applicationSupportRoot: URL

  public init(applicationSupportRoot: URL = ModelRuntimeCatalog.defaultApplicationSupportRoot) {
    self.applicationSupportRoot = applicationSupportRoot
  }

  public var runtimeRoot: URL {
    applicationSupportRoot
      .appendingPathComponent("Runtime", isDirectory: true)
      .appendingPathComponent("ACE-Step-1.5", isDirectory: true)
  }

  public var modelRoot: URL {
    applicationSupportRoot
      .appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent("ACE-Step-1.5", isDirectory: true)
  }

  public var checkpointsRoot: URL {
    modelRoot.appendingPathComponent("checkpoints", isDirectory: true)
  }

  public var markerRoot: URL {
    modelRoot.appendingPathComponent("installed", isDirectory: true)
  }

  public func markerURL(for modelID: MusicModelID) -> URL {
    markerRoot.appendingPathComponent("\(modelID.rawValue).json")
  }

  public var installerRoot: URL {
    applicationSupportRoot
      .appendingPathComponent("Installer", isDirectory: true)
      .appendingPathComponent("ACE-Step-1.5", isDirectory: true)
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
    downloadsRoot.appendingPathComponent("ACE-Step-1.5-\(Self.sourceRevision).zip")
  }

  public var uvArchiveURL: URL {
    downloadsRoot.appendingPathComponent("uv-\(Self.uvVersion)-arm64.tar.gz")
  }

  public var sourceArchiveRemoteURL: URL {
    URL(
      string:
        "https://github.com/ace-step/ACE-Step-1.5/archive/\(Self.sourceRevision).zip"
    )!
  }

  public var uvArchiveRemoteURL: URL {
    URL(
      string:
        "https://github.com/astral-sh/uv/releases/download/\(Self.uvVersion)/uv-aarch64-apple-darwin.tar.gz"
    )!
  }

  public var pythonInstallRoot: URL {
    applicationSupportRoot
      .appendingPathComponent("Runtime", isDirectory: true)
      .appendingPathComponent("ACE-Python", isDirectory: true)
  }

  public var pythonURL: URL {
    runtimeRoot.appendingPathComponent(".venv/bin/python")
  }

  public var bridgeURL: URL {
    runtimeRoot.appendingPathComponent("flowtone_bridge.py")
  }

  public var launcherURL: URL {
    applicationSupportRoot.appendingPathComponent(ModelRuntimeCatalog.aceStepExecutableName)
  }

  public var installLogURL: URL {
    installerRoot.appendingPathComponent("ace-step-install.log")
  }

  public var uvCacheRoot: URL {
    applicationSupportRoot
      .appendingPathComponent("Cache", isDirectory: true)
      .appendingPathComponent("uv-ace-step", isDirectory: true)
  }

  public var huggingFaceRoot: URL {
    modelRoot.appendingPathComponent("HuggingFace", isDirectory: true)
  }

  public func isRuntimeComplete(fileManager: FileManager = .default) -> Bool {
    fileManager.isExecutableFile(atPath: pythonURL.path)
      && fileManager.isExecutableFile(atPath: launcherURL.path)
      && fileManager.fileExists(atPath: bridgeURL.path)
      && fileManager.fileExists(
        atPath: runtimeRoot.appendingPathComponent("acestep/api_server.py").path)
  }

  public func isModelInstalled(
    _ modelID: MusicModelID,
    fileManager: FileManager = .default
  ) -> Bool {
    guard ACEStepModelConfiguration.configuration(for: modelID) != nil else { return false }
    guard isRuntimeComplete(fileManager: fileManager) else { return false }
    guard
      populatedDirectory(checkpointsRoot.appendingPathComponent("acestep-v15-turbo"), fileManager)
        && populatedDirectory(checkpointsRoot.appendingPathComponent("vae"), fileManager)
        && populatedDirectory(
          checkpointsRoot.appendingPathComponent("Qwen3-Embedding-0.6B"), fileManager)
    else { return false }

    switch modelID {
    case .aceLite:
      guard
        populatedDirectory(
          checkpointsRoot.appendingPathComponent("acestep-5Hz-lm-0.6B"), fileManager)
      else { return false }
    case .acePro:
      guard
        populatedDirectory(
          checkpointsRoot.appendingPathComponent("acestep-5Hz-lm-1.7B"), fileManager)
      else { return false }
    case .aceMax:
      guard
        populatedDirectory(
          checkpointsRoot.appendingPathComponent("acestep-v15-xl-turbo"), fileManager),
        populatedDirectory(
          checkpointsRoot.appendingPathComponent("acestep-5Hz-lm-4B"), fileManager)
      else { return false }
    case .aceTurbo:
      break
    case .stableSmall, .stableMedium:
      return false
    }
    return fileManager.fileExists(atPath: markerURL(for: modelID).path)
  }

  public func launcherScript() -> String {
    let python = Self.shellQuote(pythonURL.path)
    let bridge = Self.shellQuote(bridgeURL.path)
    let workingDirectory = Self.shellQuote(runtimeRoot.path)
    let checkpoints = Self.shellQuote(checkpointsRoot.path)
    let modelCache = Self.shellQuote(huggingFaceRoot.path)
    return """
      #!/usr/bin/env bash
      set -euo pipefail

      export ACESTEP_CHECKPOINTS_DIR=\(checkpoints)
      export HF_HOME=\(modelCache)
      export HF_HUB_DISABLE_IMPLICIT_TOKEN=1
      export TOKENIZERS_PARALLELISM=false
      export ACESTEP_LM_BACKEND=mlx

      cd \(workingDirectory)
      exec \(python) \(bridge) "$@"
      """
  }

  public static let bridgeScript = #"""
    import argparse
    import json
    import os
    import shutil
    import signal
    import socket
    import subprocess
    import sys
    import time
    import urllib.parse
    import urllib.request

    def request_json(url, payload=None, timeout=30):
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = {} if body is None else {"Content-Type": "application/json"}
        with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers), timeout=timeout) as response:
            value = json.loads(response.read().decode("utf-8"))
        if value.get("code") not in (None, 200):
            raise RuntimeError(value.get("error") or "ACE-Step API error")
        return value

    parser = argparse.ArgumentParser(description="Flowtone ACE-Step bridge")
    parser.add_argument("--prompt")
    parser.add_argument("--negative-prompt", default="")
    parser.add_argument("--model", default="acestep-v15-turbo")
    parser.add_argument("--lm", default="none")
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--out")
    args = parser.parse_args()
    if not args.prompt or not args.out:
        parser.error("--prompt and --out are required")

    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    base = f"http://127.0.0.1:{port}"
    env = os.environ.copy()
    env["ACESTEP_CONFIG_PATH"] = args.model
    env["ACESTEP_INIT_LLM"] = "false" if args.lm == "none" else "true"
    if args.lm != "none":
        env["ACESTEP_LM_MODEL_PATH"] = args.lm
    env["ACESTEP_API_HOST"] = "127.0.0.1"
    env["ACESTEP_API_PORT"] = str(port)
    env["TOKENIZERS_PARALLELISM"] = "false"
    log_path = os.path.join(os.getcwd(), "flowtone-api.log")
    log = open(log_path, "ab", buffering=0)
    server = subprocess.Popen(
        [sys.executable, "-m", "acestep.api_server", "--host", "127.0.0.1", "--port", str(port)],
        cwd=os.getcwd(), env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
        start_new_session=True,
    )

    def stop_server(*_):
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=15)
            except subprocess.TimeoutExpired:
                server.kill()
        log.close()

    signal.signal(signal.SIGTERM, lambda *_: (stop_server(), sys.exit(143)))
    signal.signal(signal.SIGINT, lambda *_: (stop_server(), sys.exit(130)))
    try:
        deadline = time.monotonic() + 900
        while True:
            if server.poll() is not None:
                raise RuntimeError(f"ACE-Step API stopped during startup; see {log_path}")
            try:
                request_json(base + "/health", timeout=5)
                break
            except Exception:
                if time.monotonic() >= deadline:
                    raise RuntimeError(f"ACE-Step API startup timeout; see {log_path}")
                time.sleep(2)

        payload = {
            "prompt": args.prompt,
            "negative_prompt": args.negative_prompt,
            "lyrics": "[Instrumental]",
            "thinking": args.lm != "none",
            "model": args.model,
            "audio_duration": max(10, min(args.seconds, 120)),
            "audio_format": "wav",
            "inference_steps": max(1, args.steps),
            "seed": args.seed,
        }
        created = request_json(base + "/release_task", payload, timeout=60)
        task_id = created["data"]["task_id"]
        deadline = time.monotonic() + 10800
        while True:
            state = request_json(base + "/query_result", {"task_id_list": [task_id]}, timeout=30)
            item = state["data"][0]
            if int(item.get("status", 0)) == 2:
                raise RuntimeError(item.get("error") or "ACE-Step generation failed")
            if int(item.get("status", 0)) == 1:
                results = json.loads(item["result"])
                audio_path = results[0]["file"]
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("ACE-Step generation timeout")
            time.sleep(2)

        part = args.out + ".part"
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with urllib.request.urlopen(urllib.parse.urljoin(base, audio_path), timeout=600) as response, open(part, "wb") as output:
            shutil.copyfileobj(response, output)
        if os.path.getsize(part) < 44:
            raise RuntimeError("ACE-Step returned an empty audio file")
        os.replace(part, args.out)
        print(args.out)
    finally:
        stop_server()
    """#

  private func populatedDirectory(_ url: URL, _ fileManager: FileManager) -> Bool {
    guard
      let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
    else { return false }
    for case let candidate as URL in enumerator {
      if (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 1_024 {
        return true
      }
    }
    return false
  }

  private static func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }
}

public final class ACEStepInstaller: @unchecked Sendable {
  public typealias ProgressHandler = @Sendable (StableAudioInstallationProgress) async -> Void

  public let manifest: ACEStepInstallationManifest
  private let fileManager: FileManager
  private let session: URLSession

  public init(
    manifest: ACEStepInstallationManifest = ACEStepInstallationManifest(),
    fileManager: FileManager = .default,
    session: URLSession = .shared
  ) {
    self.manifest = manifest
    self.fileManager = fileManager
    self.session = session
  }

  public func install(
    modelID: MusicModelID,
    progress: @escaping ProgressHandler
  ) async throws {
    guard ACEStepModelConfiguration.configuration(for: modelID) != nil else {
      throw StableAudioInstallerError.incompleteInstallation
    }
    let profile = MusicModelProfile.profile(for: modelID)
    if manifest.isModelInstalled(modelID, fileManager: fileManager) {
      await progress(Self.completedProgress(for: profile))
      return
    }
    try Task.checkCancellation()
    await progress(
      .init(
        phase: .preparing,
        title: "Проверяю Mac и свободное место",
        detail: "Для \(profile.shortTitle) нужно до \(profile.requiredFreeDiskGiB) ГБ.",
        completedFraction: 0.04
      ))
    try prepareDirectoriesAndCheckDisk(profile: profile)

    if !manifest.isRuntimeComplete(fileManager: fileManager) {
      await progress(
        .init(
          phase: .downloadingTools,
          title: "Загружаю системный помощник",
          detail: "Flowtone проверит SHA-256 перед запуском.",
          completedFraction: 0.1
        ))
      try await obtainArtifact(
        remoteURL: manifest.uvArchiveRemoteURL,
        destinationURL: manifest.uvArchiveURL,
        expectedSHA256: ACEStepInstallationManifest.uvArchiveSHA256,
        displayName: "uv"
      )
      try extractUV()
      await progress(
        .init(
          phase: .downloadingRuntime,
          title: "Загружаю официальный ACE-Step 1.5",
          detail: "Используется зафиксированная версия официального репозитория.",
          completedFraction: 0.18
        ))
      try await obtainArtifact(
        remoteURL: manifest.sourceArchiveRemoteURL,
        destinationURL: manifest.sourceArchiveURL,
        expectedSHA256: ACEStepInstallationManifest.sourceArchiveSHA256,
        displayName: "ACE-Step 1.5"
      )
      try extractRuntimeSource()
      await progress(
        .init(
          phase: .installingRuntime,
          title: "Настраиваю ACE-Step",
          detail: "Python, PyTorch и MLX ставятся только в папку Flowtone.",
          completedFraction: 0.28
        ))
      try await installRuntime()
      try installBridgeAndLauncher()
    }

    await progress(
      .init(
        phase: .downloadingModel,
        title: "Загружаю \(profile.title)",
        detail:
          "Около \(String(format: "%.1f", profile.estimatedDownloadGiB)) ГБ; загрузку можно продолжить позже.",
        completedFraction: 0.45
      ))
    try await downloadModels(for: modelID)
    try fileManager.createDirectory(at: manifest.markerRoot, withIntermediateDirectories: true)
    let marker = "{\"model\":\"\(modelID.rawValue)\",\"installedAt\":\"\(Self.timestamp)\"}"
    try Data(marker.utf8).write(to: manifest.markerURL(for: modelID), options: .atomic)

    await progress(
      .init(
        phase: .validating,
        title: "Проверяю и подключаю модель",
        detail: "После проверки генерация работает локально.",
        completedFraction: 0.94
      ))
    guard manifest.isModelInstalled(modelID, fileManager: fileManager) else {
      try? fileManager.removeItem(at: manifest.markerURL(for: modelID))
      throw StableAudioInstallerError.incompleteInstallation
    }
    cleanupInstallerArtifacts()
    await progress(Self.completedProgress(for: profile))
  }

  public func remove(modelID: MusicModelID) throws {
    guard ACEStepModelConfiguration.configuration(for: modelID) != nil else { return }
    try removeManagedItemIfPresent(manifest.markerURL(for: modelID))
    let remaining = [MusicModelID.aceTurbo, .aceLite, .acePro, .aceMax].filter {
      manifest.isModelInstalled($0, fileManager: fileManager)
    }
    if remaining.isEmpty {
      for url in [
        manifest.launcherURL, manifest.runtimeRoot, manifest.pythonInstallRoot,
        manifest.modelRoot,
      ] {
        try removeManagedItemIfPresent(url)
      }
      return
    }
    if modelID == .aceLite {
      try removeManagedItemIfPresent(
        manifest.checkpointsRoot.appendingPathComponent("acestep-5Hz-lm-0.6B"))
    }
    if modelID == .aceMax {
      try removeManagedItemIfPresent(
        manifest.checkpointsRoot.appendingPathComponent("acestep-v15-xl-turbo"))
      try removeManagedItemIfPresent(
        manifest.checkpointsRoot.appendingPathComponent("acestep-5Hz-lm-4B"))
    }
  }

  private static func completedProgress(for profile: MusicModelProfile)
    -> StableAudioInstallationProgress
  {
    .init(
      phase: .completed,
      title: "Модель установлена и подключена",
      detail: "\(profile.title) готова к локальной генерации.",
      completedFraction: 1
    )
  }

  private static var timestamp: String { ISO8601DateFormatter().string(from: Date()) }

  private func prepareDirectoriesAndCheckDisk(profile: MusicModelProfile) throws {
    #if arch(arm64)
      guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 else {
        throw StableAudioInstallerError.unsupportedMac
      }
    #else
      throw StableAudioInstallerError.unsupportedMac
    #endif
    try fileManager.createDirectory(
      at: manifest.applicationSupportRoot, withIntermediateDirectories: true)
    let values = try manifest.applicationSupportRoot.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
    ])
    let available =
      values.volumeAvailableCapacityForImportantUsage
      ?? values.volumeAvailableCapacity.map(Int64.init) ?? Int64.max
    let required = Int64(profile.requiredFreeDiskGiB) * 1_024 * 1_024 * 1_024
    guard available >= required else {
      throw StableAudioInstallerError.insufficientDiskSpace(
        required: required, available: available)
    }
    for directory in [
      manifest.installerRoot, manifest.downloadsRoot, manifest.modelRoot,
      manifest.checkpointsRoot, manifest.huggingFaceRoot,
    ] {
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
      try StableAudioInstaller.sha256(of: destinationURL) == expectedSHA256
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
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw StableAudioInstallerError.invalidHTTPResponse
    }
    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    guard try StableAudioInstaller.sha256(of: destinationURL) == expectedSHA256 else {
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
      stage: "распаковка uv"
    )
    guard fileManager.isExecutableFile(atPath: manifest.uvExecutableURL.path) else {
      throw StableAudioInstallerError.invalidArchive(name: "uv")
    }
  }

  private func extractRuntimeSource() throws {
    try? fileManager.removeItem(at: manifest.extractedSourceRoot)
    try fileManager.createDirectory(
      at: manifest.extractedSourceRoot, withIntermediateDirectories: true)
    try runProcessSynchronously(
      executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
      arguments: ["-x", "-k", manifest.sourceArchiveURL.path, manifest.extractedSourceRoot.path],
      stage: "распаковка ACE-Step"
    )
    let extracted = manifest.extractedSourceRoot.appendingPathComponent(
      "ACE-Step-1.5-\(ACEStepInstallationManifest.sourceRevision)")
    guard fileManager.fileExists(atPath: extracted.appendingPathComponent("uv.lock").path) else {
      throw StableAudioInstallerError.invalidArchive(name: "ACE-Step 1.5")
    }
    try? fileManager.removeItem(at: manifest.runtimeRoot)
    try fileManager.createDirectory(
      at: manifest.runtimeRoot.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.moveItem(at: extracted, to: manifest.runtimeRoot)
  }

  private func installRuntime() async throws {
    var environment = baseEnvironment
    environment["UV_PROJECT_ENVIRONMENT"] =
      manifest.runtimeRoot.appendingPathComponent(".venv").path
    environment["UV_PYTHON_INSTALL_DIR"] = manifest.pythonInstallRoot.path
    environment["UV_CACHE_DIR"] = manifest.uvCacheRoot.path
    environment["UV_NO_PROGRESS"] = "1"
    environment["UV_NO_MODIFY_PATH"] = "1"
    environment["UV_LINK_MODE"] = "copy"
    try await runProcess(
      executableURL: manifest.uvExecutableURL,
      arguments: ["sync", "--project", manifest.runtimeRoot.path, "--frozen", "--no-dev"],
      environment: environment,
      stage: "установка ACE-Step"
    )
    guard fileManager.isExecutableFile(atPath: manifest.pythonURL.path) else {
      throw StableAudioInstallerError.incompleteInstallation
    }
  }

  private func installBridgeAndLauncher() throws {
    try Data(ACEStepInstallationManifest.bridgeScript.utf8).write(
      to: manifest.bridgeURL,
      options: .atomic
    )
    try Data(manifest.launcherScript().utf8).write(to: manifest.launcherURL, options: .atomic)
    try fileManager.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: manifest.launcherURL.path)
    try runProcessSynchronously(
      executableURL: manifest.launcherURL,
      arguments: ["--help"],
      stage: "проверка ACE-Step bridge"
    )
  }

  private func downloadModels(for modelID: MusicModelID) async throws {
    var environment = baseEnvironment
    environment["ACESTEP_CHECKPOINTS_DIR"] = manifest.checkpointsRoot.path
    environment["HF_HOME"] = manifest.huggingFaceRoot.path
    environment["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
    environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
    environment["TOKENIZERS_PARALLELISM"] = "false"
    environment.removeValue(forKey: "HF_TOKEN")
    environment.removeValue(forKey: "HUGGING_FACE_HUB_TOKEN")
    let common = ["-m", "acestep.model_downloader", "--dir", manifest.checkpointsRoot.path]
    try await runProcess(
      executableURL: manifest.pythonURL,
      arguments: common + ["--model", "main"],
      environment: environment,
      stage: "загрузка основных весов ACE-Step"
    )
    let extras: [String]
    switch modelID {
    case .aceLite: extras = ["acestep-5Hz-lm-0.6B"]
    case .aceMax: extras = ["acestep-v15-xl-turbo", "acestep-5Hz-lm-4B"]
    case .aceTurbo, .acePro: extras = []
    case .stableSmall, .stableMedium: extras = []
    }
    for extra in extras {
      try await runProcess(
        executableURL: manifest.pythonURL,
        arguments: common + ["--model", extra, "--skip-main"],
        environment: environment,
        stage: "загрузка \(extra)"
      )
    }
  }

  private func runProcess(
    executableURL: URL,
    arguments: [String],
    environment: [String: String],
    stage: String
  ) async throws {
    let box = ACEStepInstallerProcessBox()
    try await withTaskCancellationHandler {
      try await Task.detached(priority: .utility) { [self] in
        try self.runProcessSynchronously(
          executableURL: executableURL,
          arguments: arguments,
          environment: environment,
          stage: stage,
          processBox: box
        )
      }.value
    } onCancel: {
      box.cancel()
    }
  }

  private func runProcessSynchronously(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]? = nil,
    stage: String,
    processBox: ACEStepInstallerProcessBox? = nil
  ) throws {
    try fileManager.createDirectory(at: manifest.installerRoot, withIntermediateDirectories: true)
    if !fileManager.fileExists(atPath: manifest.installLogURL.path) {
      fileManager.createFile(atPath: manifest.installLogURL.path, contents: nil)
    }
    let log = try FileHandle(forWritingTo: manifest.installLogURL)
    defer { try? log.close() }
    try log.seekToEnd()
    try log.write(contentsOf: Data("\n[\(Self.timestamp)] \(stage)\n".utf8))
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment ?? baseEnvironment
    process.currentDirectoryURL = manifest.runtimeRoot
    process.standardOutput = log
    process.standardError = log
    let cancellationRequested = processBox?.register(process) ?? false
    defer { processBox?.clear(process) }
    try process.run()
    if cancellationRequested { process.terminate() }
    process.waitUntilExit()
    if processBox?.isCancellationRequested == true { throw CancellationError() }
    guard process.terminationStatus == 0 else {
      throw StableAudioInstallerError.processFailed(
        stage: stage, exitCode: process.terminationStatus)
    }
  }

  private var baseEnvironment: [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] =
      "\(manifest.uvExecutableURL.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
    environment["HOME"] = NSHomeDirectory()
    environment["LANG"] = "en_US.UTF-8"
    return environment
  }

  private func cleanupInstallerArtifacts() {
    for url in [
      manifest.sourceArchiveURL, manifest.uvArchiveURL, manifest.extractedSourceRoot,
      manifest.toolsRoot, manifest.uvCacheRoot,
    ] {
      try? fileManager.removeItem(at: url)
    }
  }

  private func removeManagedItemIfPresent(_ url: URL) throws {
    let target = url.standardizedFileURL.path
    let root = manifest.applicationSupportRoot.standardizedFileURL.path
    guard target != root, target.hasPrefix(root + "/") else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    if fileManager.fileExists(atPath: target)
      || (try? fileManager.destinationOfSymbolicLink(atPath: target)) != nil
    {
      try fileManager.removeItem(at: url)
    }
  }
}

private final class ACEStepInstallerProcessBox: @unchecked Sendable {
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
    lock.withLock { if self.process === process { self.process = nil } }
  }

  func cancel() {
    let active = lock.withLock { () -> Process? in
      cancellationRequested = true
      return process
    }
    if active?.isRunning == true { active?.terminate() }
  }
}
