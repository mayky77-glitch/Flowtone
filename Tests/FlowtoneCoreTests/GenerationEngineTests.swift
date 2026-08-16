import Foundation
import Testing

@testable import FlowtoneCore

@Suite struct GenerationEngineTests {
  @Test func syntheticEngineWritesValidWaveFile() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let request = GenerationRequest(
      prompt: "ambient",
      negativePrompt: "vocals",
      durationSeconds: 1,
      seed: 7,
      outputDirectory: directory
    )
    let audio = try await SyntheticAudioEngine().generate(request)
    let data = try Data(contentsOf: audio.fileURL)
    let expectedByteCount = 44 + 44_100 * 2 * 2

    #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
    #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
    #expect(data.count == expectedByteCount)
    #expect(audio.byteSize == Int64(data.count))
  }

  @Test func stableAudioArgumentsDoNotUseShellInterpolation() throws {
    let request = GenerationRequest(
      prompt: "ambient $(touch /tmp/should-not-run)",
      negativePrompt: "vocals; rm -rf ignored",
      durationSeconds: 30,
      seed: 99,
      outputDirectory: URL(fileURLWithPath: "/tmp")
    )
    let output = URL(fileURLWithPath: "/tmp/out file.wav")

    let arguments = try StableAudioMLXCommand().arguments(for: request, outputURL: output)

    #expect(arguments[1] == request.prompt)
    #expect(arguments[3] == request.negativePrompt)
    #expect(arguments.last == "/tmp/out file.wav")
    #expect(!arguments.contains("/bin/sh"))
    #expect(!arguments.contains("-c"))
  }

  @Test func schedulerDefersWhenGenerationIsDisabled() async throws {
    let scheduler = GenerationScheduler(engine: SyntheticAudioEngine())
    await scheduler.setGenerationEnabled(false)

    let result = try await scheduler.generateNext(
      configuration: StationConfiguration(
        genres: ["ambient"],
        energy: .calm,
        tempoBPM: 80,
        mood: .focused
      ),
      durationSeconds: 1,
      seed: 1,
      outputDirectory: FileManager.default.temporaryDirectory,
      resources: ResourceSnapshot(
        thermalState: .nominal,
        memoryPressure: .normal,
        lowPowerModeEnabled: false
      )
    )

    #expect(result == nil)
    guard case .deferred = await scheduler.state else {
      Issue.record("Disabled generation must be deferred")
      return
    }
  }
}
