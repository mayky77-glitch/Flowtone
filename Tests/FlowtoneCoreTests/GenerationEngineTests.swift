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

  @Test func cancellingStableAudioStopsItsProcessPromptly() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("slow-sa3")
    try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )
    let request = GenerationRequest(
      prompt: "instrumental test",
      negativePrompt: "vocals",
      durationSeconds: 30,
      seed: 17,
      outputDirectory: directory
    )
    let task = Task {
      try await StableAudioMLXEngine(executableURL: executable).generate(request)
    }

    try await Task.sleep(for: .milliseconds(100))
    let startedAt = ContinuousClock.now
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(ContinuousClock.now - startedAt < .seconds(2))
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("flowtone-sa3-17.wav").path))
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

  @Test func schedulerCanReplaceItsGenerationEngine() async {
    let scheduler = GenerationScheduler(engine: SyntheticAudioEngine())
    let stableAudio = StableAudioMLXEngine(
      executableURL: URL(fileURLWithPath: "/tmp/stable-audio-mlx"))

    await scheduler.replaceEngine(stableAudio)

    #expect(await scheduler.engineDescriptor == stableAudio.descriptor)
    #expect(await scheduler.state == .idle)
  }

  @Test func disablingGenerationCancelsActiveWorkWithoutOpeningCircuit() async throws {
    let state = CancellationProbe()
    let scheduler = GenerationScheduler(engine: CancellableGenerationEngine(state: state))
    let task = Task {
      try await scheduler.generateNext(
        configuration: StationConfiguration(
          genres: ["Ambient"],
          energy: .calm,
          tempoBPM: 70,
          mood: .focused
        ),
        durationSeconds: 30,
        seed: 5,
        outputDirectory: FileManager.default.temporaryDirectory,
        resources: ResourceSnapshot(
          thermalState: .nominal,
          memoryPressure: .normal,
          lowPowerModeEnabled: false
        )
      )
    }

    while await !state.hasStarted {
      await Task.yield()
    }
    await scheduler.setGenerationEnabled(false)

    #expect(try await task.value == nil)
    #expect(await state.wasCancelled)
    guard case .deferred = await scheduler.state else {
      Issue.record("Disabled generation must stay deferred after cancellation")
      return
    }
  }
}

private actor CancellationProbe {
  private(set) var hasStarted = false
  private(set) var wasCancelled = false

  func start() { hasStarted = true }
  func cancel() { wasCancelled = true }
}

private struct CancellableGenerationEngine: GenerationEngine {
  let descriptor = EngineDescriptor(
    id: "cancellation-probe",
    displayName: "Cancellation probe",
    tier: .light,
    isDevelopmentOnly: true
  )
  let state: CancellationProbe

  func generate(_ request: GenerationRequest) async throws -> GeneratedAudio {
    await state.start()
    do {
      try await Task.sleep(for: .seconds(30))
    } catch is CancellationError {
      await state.cancel()
      throw CancellationError()
    }
    throw CancellationError()
  }
}
