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
  private var activeGenerationTask: Task<GeneratedAudio, Error>?
  private var activeGenerationID: UUID?
  private var activeCancellationReason: String?

  public init(
    engine: any GenerationEngine,
    resourcePolicy: ResourcePolicy = ResourcePolicy()
  ) {
    self.engine = engine
    self.resourcePolicy = resourcePolicy
  }

  public var engineDescriptor: EngineDescriptor { engine.descriptor }

  public func replaceEngine(_ engine: any GenerationEngine) {
    activeGenerationTask?.cancel()
    activeGenerationTask = nil
    activeGenerationID = nil
    activeCancellationReason = nil
    self.engine = engine
    consecutiveFailures = 0
    state = generationEnabled ? .idle : .deferred(reason: "Генерация выключена.")
  }

  public func setGenerationEnabled(_ enabled: Bool) {
    generationEnabled = enabled
    if !enabled {
      activeGenerationTask?.cancel()
      state = .deferred(reason: "Генерация выключена.")
    } else if case .deferred = state {
      state = .idle
    }
  }

  public func cancelActiveGeneration(reason: String) async {
    guard let activeGenerationTask else {
      state = .deferred(reason: reason)
      return
    }

    let generationID = activeGenerationID
    activeCancellationReason = reason
    activeGenerationTask.cancel()
    _ = try? await activeGenerationTask.value
    if activeGenerationID == generationID {
      self.activeGenerationTask = nil
      activeGenerationID = nil
    }
    state = .deferred(reason: reason)
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

    guard activeGenerationTask == nil else {
      state = .deferred(reason: "Предыдущее задание генерации ещё выполняется.")
      return nil
    }

    let engine = engine
    let generationID = UUID()
    let generationTask = Task(priority: .utility) {
      try await engine.generate(request)
    }
    activeGenerationID = generationID
    activeGenerationTask = generationTask
    state = .generating
    defer {
      if activeGenerationID == generationID {
        activeGenerationTask = nil
        activeGenerationID = nil
      }
    }
    do {
      let audio = try await generationTask.value
      consecutiveFailures = 0
      state = generationEnabled ? .idle : .deferred(reason: "Генерация выключена.")
      return audio
    } catch is CancellationError {
      if let activeCancellationReason {
        state = .deferred(reason: activeCancellationReason)
        self.activeCancellationReason = nil
      } else {
        state = generationEnabled ? .idle : .deferred(reason: "Генерация выключена.")
      }
      return nil
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
