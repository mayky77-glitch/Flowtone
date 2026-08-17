import Foundation

public enum SchedulerState: Equatable, Sendable {
  case idle
  case generating
  case deferred(reason: String)
  case circuitOpen(failures: Int)
}

public actor GenerationScheduler {
  public private(set) var state: SchedulerState = .idle
  public var generationEnabled = true

  private var engine: any GenerationEngine
  private let resourcePolicy: ResourcePolicy
  private var consecutiveFailures = 0

  public init(
    engine: any GenerationEngine,
    resourcePolicy: ResourcePolicy = ResourcePolicy()
  ) {
    self.engine = engine
    self.resourcePolicy = resourcePolicy
  }

  public var engineDescriptor: EngineDescriptor { engine.descriptor }

  public func replaceEngine(_ engine: any GenerationEngine) {
    self.engine = engine
    consecutiveFailures = 0
    state = generationEnabled ? .idle : .deferred(reason: "Генерация выключена.")
  }

  public func setGenerationEnabled(_ enabled: Bool) {
    generationEnabled = enabled
    if !enabled {
      state = .deferred(reason: "Генерация выключена.")
    } else if case .deferred = state {
      state = .idle
    }
  }

  public func generateNext(
    configuration: StationConfiguration,
    durationSeconds: Int,
    seed: UInt64,
    outputDirectory: URL,
    resources: ResourceSnapshot
  ) async throws -> GeneratedAudio? {
    guard generationEnabled else {
      state = .deferred(reason: "Генерация выключена.")
      return nil
    }

    guard consecutiveFailures < 3 else {
      state = .circuitOpen(failures: consecutiveFailures)
      return nil
    }

    switch resourcePolicy.permission(for: resources) {
    case .allowed:
      break
    case .deferred(let reason):
      state = .deferred(reason: reason)
      return nil
    }

    let composer = PromptComposer()
    let request = GenerationRequest(
      prompt: try composer.compose(from: configuration, seed: seed),
      negativePrompt: composer.negativePrompt,
      durationSeconds: durationSeconds,
      seed: seed,
      outputDirectory: outputDirectory
    )

    state = .generating
    do {
      let audio = try await engine.generate(request)
      consecutiveFailures = 0
      state = .idle
      return audio
    } catch {
      consecutiveFailures += 1
      state =
        consecutiveFailures >= 3
        ? .circuitOpen(failures: consecutiveFailures)
        : .idle
      throw error
    }
  }

  public func resetCircuit() {
    consecutiveFailures = 0
    state = .idle
  }
}
