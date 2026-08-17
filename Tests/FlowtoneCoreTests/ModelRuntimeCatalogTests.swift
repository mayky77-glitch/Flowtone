import Foundation
import Testing

@testable import FlowtoneCore

@Suite struct ModelRuntimeCatalogTests {
  @Test func lightTierIsUnavailableWhenRuntimeIsMissing() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let catalog = ModelRuntimeCatalog(applicationSupportRoot: root)

    #expect(
      catalog.availability(for: .light)
        == .unavailable(reason: "Stable Audio 3 не установлен в приложении."))
    #expect(catalog.stableAudioEngine() == nil)
  }

  @Test func lightTierUsesInstalledExecutable() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let executableURL = root.appendingPathComponent(ModelRuntimeCatalog.stableAudioExecutableName)
    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executableURL.path
    )

    let catalog = ModelRuntimeCatalog(applicationSupportRoot: root)

    #expect(catalog.availability(for: .light) == .available)
    #expect(catalog.stableAudioEngine()?.executableURL == executableURL)
  }

  @Test func lightTierRejectsNonExecutableRuntime() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let executableURL = root.appendingPathComponent(ModelRuntimeCatalog.stableAudioExecutableName)
    try Data().write(to: executableURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: executableURL.path
    )

    let catalog = ModelRuntimeCatalog(applicationSupportRoot: root)

    #expect(
      catalog.availability(for: .light)
        == .unavailable(reason: "Stable Audio 3 не установлен в приложении."))
    #expect(catalog.stableAudioEngine() == nil)
  }

  @Test func qualityTierIsExplicitlyUnsupported() throws {
    let root = try makeTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let catalog = ModelRuntimeCatalog(applicationSupportRoot: root)

    #expect(
      catalog.availability(for: .quality)
        == .unsupported(
          reason: "Качественный tier недоступен: адаптер ACE-Step ещё не поддерживается."
        ))
  }

  private func makeTemporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}
