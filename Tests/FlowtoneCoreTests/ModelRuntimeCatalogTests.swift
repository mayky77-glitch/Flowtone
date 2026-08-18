import Foundation
import Testing

@testable import FlowtoneCore

@Suite struct ModelRuntimeCatalogTests {
  @Test func tiersAreUnavailableWhenRuntimeIsMissing() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = ModelRuntimeCatalog(applicationSupportRoot: root)

    for tier in ModelTier.allCases {
      let title = StableAudioModelProfile.profile(for: tier).title
      #expect(
        catalog.availability(for: tier)
          == .unavailable(
            reason: "\(title) не установлена. Откройте «Модели», чтобы скачать её на этот Mac."
          ))
      #expect(catalog.stableAudioEngine(for: tier) == nil)
    }
    #expect(catalog.installedModelTiers.isEmpty)
    #expect(!catalog.hasStableAudioExecutable)
  }

  @Test func catalogDetectsAndBuildsEachInstalledEngine() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = StableAudioInstallationManifest(applicationSupportRoot: root)
    try makeExecutable(manifest.launcherURL)
    try makeExecutable(manifest.mlxRoot.appendingPathComponent("sa3"))
    try makeExecutable(manifest.mlxRoot.appendingPathComponent(".venv/bin/python"))
    try writeWeights(manifest.modelWeightURLs(for: .quality))

    let catalog = ModelRuntimeCatalog(applicationSupportRoot: root)

    #expect(catalog.availability(for: .quality) == .available)
    #expect(catalog.availability(for: .light) != .available)
    #expect(catalog.stableAudioEngine(for: .quality)?.descriptor.tier == .quality)
    #expect(catalog.stableAudioEngine(for: .quality)?.executableURL == manifest.launcherURL)
    #expect(catalog.installedModelTiers == [.quality])
  }

  @Test func nonExecutableLauncherKeepsModelsUnavailable() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = StableAudioInstallationManifest(applicationSupportRoot: root)
    try FileManager.default.createDirectory(
      at: manifest.launcherURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data().write(to: manifest.launcherURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: manifest.launcherURL.path
    )
    try makeExecutable(manifest.mlxRoot.appendingPathComponent("sa3"))
    try makeExecutable(manifest.mlxRoot.appendingPathComponent(".venv/bin/python"))
    try writeWeights(manifest.modelWeightURLs(for: .light))

    let catalog = ModelRuntimeCatalog(applicationSupportRoot: root)

    #expect(catalog.availability(for: .light) != .available)
    #expect(catalog.stableAudioEngine() == nil)
    #expect(!catalog.hasStableAudioExecutable)
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
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }

  private func writeWeights(_ urls: [URL]) throws {
    for url in urls {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data([1]).write(to: url)
    }
  }
}
