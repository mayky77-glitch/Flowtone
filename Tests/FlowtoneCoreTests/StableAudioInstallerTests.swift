import Foundation
import Testing

@testable import FlowtoneCore

@Suite struct StableAudioInstallerTests {
  @Test func manifestPinsOfficialArtifactsAndLocalPaths() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let manifest = StableAudioInstallationManifest(applicationSupportRoot: root)

    #expect(StableAudioInstallationManifest.sourceRevision.count == 40)
    #expect(StableAudioInstallationManifest.sourceArchiveSHA256.count == 64)
    #expect(StableAudioInstallationManifest.uvArchiveSHA256.count == 64)
    #expect(manifest.sourceArchiveRemoteURL.host == "github.com")
    #expect(manifest.uvArchiveRemoteURL.host == "github.com")
    #expect(manifest.runtimeRoot.path.hasPrefix(root.path))
    #expect(manifest.huggingFaceRoot.path.hasPrefix(root.path))
    #expect(manifest.requiredWeightURLs.count == 4)
  }

  @Test func launcherUsesOfflineModelCacheAndQuotesPaths() throws {
    let root = URL(fileURLWithPath: "/tmp/Flowtone user's files", isDirectory: true)
    let manifest = StableAudioInstallationManifest(applicationSupportRoot: root)
    let script = manifest.launcherScript()

    #expect(script.contains("export HF_HUB_OFFLINE=1"))
    #expect(script.contains("export TRANSFORMERS_OFFLINE=1"))
    #expect(script.contains("export HF_HUB_DISABLE_IMPLICIT_TOKEN=1"))
    #expect(!script.contains("HF_TOKEN="))
    #expect(script.contains("'\\''"))
    #expect(script.contains("exec "))
  }

  @Test func completeInstallationRequiresExecutableRuntimeAndAllWeights() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = StableAudioInstallationManifest(applicationSupportRoot: root)

    try makeExecutable(manifest.launcherURL)
    try makeExecutable(manifest.mlxRoot.appendingPathComponent("sa3"))
    try makeExecutable(
      manifest.mlxRoot
        .appendingPathComponent(".venv/bin/python"))
    for weightURL in manifest.requiredWeightURLs {
      try FileManager.default.createDirectory(
        at: weightURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data([1]).write(to: weightURL)
    }

    #expect(manifest.isComplete())
    try FileManager.default.removeItem(at: manifest.requiredWeightURLs[0])
    #expect(!manifest.isComplete())
  }

  @Test func sha256StreamsKnownFile() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("sample.txt")
    try Data("abc".utf8).write(to: file)

    #expect(
      try StableAudioInstaller.sha256(of: file)
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  @Test func installerReusesCompleteRuntimeWithoutNetwork() async throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = StableAudioInstallationManifest(applicationSupportRoot: root)
    try makeExecutable(manifest.launcherURL)
    try makeExecutable(manifest.mlxRoot.appendingPathComponent("sa3"))
    try makeExecutable(manifest.mlxRoot.appendingPathComponent(".venv/bin/python"))
    for weightURL in manifest.requiredWeightURLs {
      try FileManager.default.createDirectory(
        at: weightURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data([1]).write(to: weightURL)
    }
    let recorder = ProgressRecorder()

    try await StableAudioInstaller(manifest: manifest).install { progress in
      await recorder.append(progress)
    }

    let progress = await recorder.values
    #expect(progress.count == 1)
    #expect(progress.first?.phase == .completed)
    #expect(progress.first?.completedFraction == 1)
  }

  @Test func realInstallerSmokeWhenExplicitlyEnabled() async throws {
    guard
      let rootPath = ProcessInfo.processInfo.environment["FLOWTONE_INSTALLER_SMOKE_ROOT"],
      let existingHFHome = ProcessInfo.processInfo.environment["FLOWTONE_EXISTING_HF_HOME"]
    else { return }

    let root = URL(fileURLWithPath: rootPath, isDirectory: true)
    #expect(!FileManager.default.fileExists(atPath: root.path))
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let manifest = StableAudioInstallationManifest(applicationSupportRoot: root)
    try FileManager.default.createDirectory(
      at: manifest.huggingFaceRoot,
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: manifest.huggingFaceRoot.appendingPathComponent("hub"),
      withDestinationURL: URL(fileURLWithPath: existingHFHome)
        .appendingPathComponent("hub", isDirectory: true)
    )

    let recorder = ProgressRecorder()
    try await StableAudioInstaller(manifest: manifest).install { progress in
      await recorder.append(progress)
    }

    #expect(manifest.isComplete())
    #expect(await recorder.values.last?.phase == .completed)
  }

  private func makeTemporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func makeExecutable(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: url.path
    )
  }
}

private actor ProgressRecorder {
  private(set) var values: [StableAudioInstallationProgress] = []

  func append(_ progress: StableAudioInstallationProgress) {
    values.append(progress)
  }
}
