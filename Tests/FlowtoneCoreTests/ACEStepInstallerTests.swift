import Foundation
import Testing

@testable import FlowtoneCore

@Suite struct ACEStepInstallerTests {
  @Test func manifestPinsOfficialSourceAndUsesLocalBridge() {
    let manifest = ACEStepInstallationManifest(
      applicationSupportRoot: URL(fileURLWithPath: "/tmp/Flowtone ACE Tests"))

    #expect(ACEStepInstallationManifest.sourceRevision.count == 40)
    #expect(ACEStepInstallationManifest.sourceArchiveSHA256.count == 64)
    #expect(manifest.sourceArchiveRemoteURL.host == "github.com")
    #expect(manifest.launcherScript().contains("ACESTEP_CHECKPOINTS_DIR"))
    #expect(manifest.launcherScript().contains("exec "))
    #expect(ACEStepInstallationManifest.bridgeScript.contains("/release_task"))
    #expect(ACEStepInstallationManifest.bridgeScript.contains("/query_result"))
    #expect(ACEStepInstallationManifest.bridgeScript.contains("[Instrumental]"))
  }

  @Test func installedProfilesRequireTheirDistinctWeights() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = ACEStepInstallationManifest(applicationSupportRoot: root)
    try makeRuntime(manifest)

    try populate(manifest.checkpointsRoot.appendingPathComponent("acestep-v15-turbo"))
    try populate(manifest.checkpointsRoot.appendingPathComponent("vae"))
    try populate(manifest.checkpointsRoot.appendingPathComponent("Qwen3-Embedding-0.6B"))
    try populate(manifest.checkpointsRoot.appendingPathComponent("acestep-5Hz-lm-1.7B"))
    try mark(.aceTurbo, manifest)
    try mark(.aceLite, manifest)
    try mark(.acePro, manifest)

    #expect(manifest.isModelInstalled(.aceTurbo))
    #expect(!manifest.isModelInstalled(.aceLite))
    #expect(manifest.isModelInstalled(.acePro))

    try populate(manifest.checkpointsRoot.appendingPathComponent("acestep-5Hz-lm-0.6B"))
    #expect(manifest.isModelInstalled(.aceLite))
    #expect(!manifest.isModelInstalled(.aceMax))
  }

  @Test func removingAlternativePreservesSharedRuntimeAndRemovingLastCleansIt() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = ACEStepInstallationManifest(applicationSupportRoot: root)
    try makeRuntime(manifest)
    for name in [
      "acestep-v15-turbo", "vae", "Qwen3-Embedding-0.6B", "acestep-5Hz-lm-1.7B",
      "acestep-5Hz-lm-0.6B",
    ] {
      try populate(manifest.checkpointsRoot.appendingPathComponent(name))
    }
    try mark(.aceTurbo, manifest)
    try mark(.aceLite, manifest)
    let installer = ACEStepInstaller(manifest: manifest)

    try installer.remove(modelID: .aceLite)
    #expect(manifest.isModelInstalled(.aceTurbo))
    #expect(
      !FileManager.default.fileExists(
        atPath: manifest.checkpointsRoot.appendingPathComponent("acestep-5Hz-lm-0.6B").path))

    try installer.remove(modelID: .aceTurbo)
    #expect(!FileManager.default.fileExists(atPath: manifest.runtimeRoot.path))
    #expect(!FileManager.default.fileExists(atPath: manifest.launcherURL.path))
  }

  private func makeRuntime(_ manifest: ACEStepInstallationManifest) throws {
    for url in [
      manifest.pythonURL, manifest.launcherURL,
      manifest.runtimeRoot.appendingPathComponent("acestep/api_server.py"), manifest.bridgeURL,
    ] {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("ready".utf8).write(to: url)
    }
    for url in [manifest.pythonURL, manifest.launcherURL] {
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
  }

  private func populate(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(repeating: 7, count: 2_048).write(to: directory.appendingPathComponent("weights.bin"))
  }

  private func mark(_ modelID: MusicModelID, _ manifest: ACEStepInstallationManifest) throws {
    try FileManager.default.createDirectory(
      at: manifest.markerRoot, withIntermediateDirectories: true)
    try Data("installed".utf8).write(to: manifest.markerURL(for: modelID))
  }
}
