import AVFoundation
import Foundation

/// A local audio file that can be scheduled by ``AudioPlaybackController``.
public struct AudioPlaybackItem: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let fileURL: URL

  public init(id: UUID, fileURL: URL) {
    self.id = id
    self.fileURL = fileURL
  }
}

/// The two player nodes owned by an audio playback backend.
public enum AudioPlaybackNode: CaseIterable, Sendable {
  case primary
  case secondary

  var other: AudioPlaybackNode {
    switch self {
    case .primary: .secondary
    case .secondary: .primary
    }
  }
}

/// The time source used when an audio backend cannot report its render time.
public protocol AudioPlaybackClock: AnyObject {
  var now: TimeInterval { get }
}

public final class SystemAudioPlaybackClock: AudioPlaybackClock {
  public init() {}

  public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// The hardware seam for ``AudioPlaybackController``.
///
/// A backend must report an item's duration while scheduling it. Its render time is
/// preferred over the injected clock whenever it is available, which keeps an
/// actual transition aligned with the audio render clock instead of a UI timer.
public protocol AudioPlaybackBackend: AnyObject {
  func schedule(_ item: AudioPlaybackItem, on node: AudioPlaybackNode) throws -> TimeInterval
  func startEngine() throws
  func play(_ node: AudioPlaybackNode)
  func pause(_ node: AudioPlaybackNode)
  func stop(_ node: AudioPlaybackNode)
  func setVolume(_ volume: Float, on node: AudioPlaybackNode)
  func renderedSeconds(for node: AudioPlaybackNode) -> TimeInterval?
}

/// Errors raised for invalid controller input or lifecycle order.
public enum AudioPlaybackControllerError: Error, Equatable {
  case missingCurrentItem
  case invalidCrossfadeDuration
  case invalidScheduledDuration
}

/// Controls a current file and one pre-scheduled next file over two audio nodes.
///
/// The controller owns no track selection or library state. Call ``update()`` from
/// the render-observation path to begin and complete crossfades using the
/// backend's render time. `clock` is only a deterministic fallback for backends
/// that cannot expose a render time (including test doubles).
public final class AudioPlaybackController {
  public typealias GainProvider = (Double) -> (outgoing: Float, incoming: Float)
  public typealias TransitionHandler = (UUID, UUID) -> Void
  public typealias NextNeededHandler = (UUID) -> Void

  public private(set) var currentItem: AudioPlaybackItem?
  public private(set) var queuedItem: AudioPlaybackItem?
  public private(set) var isPlaying = false

  public var currentID: UUID? { currentItem?.id }
  public var queuedID: UUID? { queuedItem?.id }
  public var crossfadeDuration: TimeInterval { requestedCrossfadeDuration }

  private let backend: any AudioPlaybackBackend
  private let clock: any AudioPlaybackClock
  private let gainProvider: GainProvider
  private let onTransition: TransitionHandler?
  private let onNextNeeded: NextNeededHandler?

  private var activeNode: AudioPlaybackNode = .primary
  private var currentDuration: TimeInterval = 0
  private var queuedDuration: TimeInterval?
  private var requestedCrossfadeDuration: TimeInterval = 0
  private var lastObservedPosition: TimeInterval = 0
  private var startedAt: TimeInterval?
  private var transitionHasStarted = false
  private var hasRequestedNext = false
  private var volume: Float = 1

  public init(
    backend: any AudioPlaybackBackend,
    clock: any AudioPlaybackClock = SystemAudioPlaybackClock(),
    gainProvider: @escaping GainProvider,
    onTransition: TransitionHandler? = nil,
    onNextNeeded: NextNeededHandler? = nil
  ) {
    self.backend = backend
    self.clock = clock
    self.gainProvider = gainProvider
    self.onTransition = onTransition
    self.onNextNeeded = onNextNeeded
  }

  /// Replaces the complete playback state with a current item and an optional next item.
  public func load(
    current: AudioPlaybackItem,
    next: AudioPlaybackItem? = nil,
    crossfadeDuration: TimeInterval
  ) throws {
    guard crossfadeDuration.isFinite, crossfadeDuration >= 0 else {
      throw AudioPlaybackControllerError.invalidCrossfadeDuration
    }

    backend.stop(.primary)
    backend.stop(.secondary)
    activeNode = .primary
    currentDuration = try schedule(current, on: activeNode)
    queuedDuration = nil
    currentItem = current
    queuedItem = nil
    requestedCrossfadeDuration = crossfadeDuration
    lastObservedPosition = 0
    startedAt = nil
    transitionHasStarted = false
    hasRequestedNext = false
    isPlaying = false
    applyGains(progress: 0)

    if let next {
      try replaceNext(with: next)
    }
  }

  public func play() throws {
    guard currentItem != nil else { throw AudioPlaybackControllerError.missingCurrentItem }
    if !isPlaying {
      try backend.startEngine()
      backend.play(activeNode)
      if transitionHasStarted, queuedItem != nil { backend.play(activeNode.other) }
      startedAt = clock.now
      isPlaying = true
    }
  }

  public func pause() {
    guard isPlaying else { return }
    lastObservedPosition = playbackPosition()
    backend.pause(activeNode)
    if transitionHasStarted, queuedItem != nil { backend.pause(activeNode.other) }
    startedAt = nil
    isPlaying = false
  }

  /// Immediately promotes the queued item, if present, and asks for a replacement.
  public func skip() throws {
    guard currentItem != nil else { throw AudioPlaybackControllerError.missingCurrentItem }
    guard queuedItem != nil else {
      requestNextIfNeeded()
      return
    }
    if isPlaying { backend.play(activeNode.other) }
    completeTransition()
  }

  /// Sets the master output volume. Values outside `0...1` are safely clamped.
  public func setVolume(_ volume: Float) {
    self.volume = min(max(volume, 0), 1)
    let progress = transitionHasStarted ? transitionProgress(at: playbackPosition()) : 0
    applyGains(progress: progress)
  }

  /// Replaces the pre-scheduled next item without changing the current item.
  public func replaceNext(with item: AudioPlaybackItem?) throws {
    guard currentItem != nil else { throw AudioPlaybackControllerError.missingCurrentItem }
    guard !transitionHasStarted else { return }

    let standbyNode = activeNode.other
    backend.stop(standbyNode)
    queuedItem = nil

    guard let item else {
      requestNextIfNeeded()
      return
    }

    queuedDuration = try schedule(item, on: standbyNode)
    backend.setVolume(0, on: standbyNode)
    queuedItem = item
    hasRequestedNext = false
  }

  /// Observes render progress and performs any due crossfade state changes.
  public func update() {
    guard isPlaying, currentItem != nil else { return }

    let position = playbackPosition()
    lastObservedPosition = position

    guard queuedItem != nil else {
      if position >= max(0, currentDuration - effectiveCrossfadeDuration) {
        requestNextIfNeeded()
      }
      return
    }

    if !transitionHasStarted,
      position >= currentDuration - effectiveCrossfadeDuration
    {
      transitionHasStarted = true
      backend.play(activeNode.other)
    }

    guard transitionHasStarted else { return }
    applyGains(progress: transitionProgress(at: position))

    if position >= currentDuration {
      let incomingPosition = max(0, position - (currentDuration - effectiveCrossfadeDuration))
      completeTransition(incomingPosition: incomingPosition)
    }
  }

  private var effectiveCrossfadeDuration: TimeInterval {
    min(requestedCrossfadeDuration, currentDuration)
  }

  private func schedule(_ item: AudioPlaybackItem, on node: AudioPlaybackNode) throws -> TimeInterval {
    let duration = try backend.schedule(item, on: node)
    guard duration.isFinite, duration > 0 else {
      throw AudioPlaybackControllerError.invalidScheduledDuration
    }
    return duration
  }

  private func playbackPosition() -> TimeInterval {
    if let renderedSeconds = backend.renderedSeconds(for: activeNode), renderedSeconds.isFinite {
      return max(0, renderedSeconds)
    }
    guard isPlaying, let startedAt else { return lastObservedPosition }
    return max(0, lastObservedPosition + clock.now - startedAt)
  }

  private func transitionProgress(at position: TimeInterval) -> Double {
    guard effectiveCrossfadeDuration > 0 else { return 1 }
    let start = currentDuration - effectiveCrossfadeDuration
    return min(1, max(0, (position - start) / effectiveCrossfadeDuration))
  }

  private func applyGains(progress: Double) {
    let gains = gainProvider(min(1, max(0, progress)))
    backend.setVolume(volume * gains.outgoing, on: activeNode)
    backend.setVolume(volume * (queuedItem == nil ? 0 : gains.incoming), on: activeNode.other)
  }

  private func completeTransition(incomingPosition: TimeInterval = 0) {
    guard let outgoing = currentItem, let incoming = queuedItem else { return }
    let outgoingNode = activeNode
    let incomingNode = outgoingNode.other
    backend.stop(outgoingNode)
    activeNode = incomingNode
    currentItem = incoming
    queuedItem = nil
    currentDuration = queuedDuration ?? 0
    queuedDuration = nil
    lastObservedPosition = incomingPosition
    startedAt = isPlaying ? clock.now : nil
    transitionHasStarted = false
    backend.setVolume(volume, on: activeNode)
    backend.setVolume(0, on: activeNode.other)
    onTransition?(outgoing.id, incoming.id)
    requestNextIfNeeded()
  }

  private func requestNextIfNeeded() {
    guard let currentItem, !hasRequestedNext else { return }
    hasRequestedNext = true
    onNextNeeded?(currentItem.id)
  }
}

/// The production backend backed by one `AVAudioEngine` and two `AVAudioPlayerNode`s.
public final class AVAudioEnginePlaybackBackend: AudioPlaybackBackend {
  private let engine: AVAudioEngine
  private let primary = AVAudioPlayerNode()
  private let secondary = AVAudioPlayerNode()

  public init(engine: AVAudioEngine = AVAudioEngine()) {
    self.engine = engine
    engine.attach(primary)
    engine.attach(secondary)
    engine.connect(primary, to: engine.mainMixerNode, format: nil)
    engine.connect(secondary, to: engine.mainMixerNode, format: nil)
  }

  public func schedule(_ item: AudioPlaybackItem, on node: AudioPlaybackNode) throws -> TimeInterval {
    let file = try AVAudioFile(forReading: item.fileURL)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    player(for: node).scheduleFile(file, at: nil)
    return duration
  }

  public func startEngine() throws {
    guard !engine.isRunning else { return }
    try engine.start()
  }

  public func play(_ node: AudioPlaybackNode) { player(for: node).play() }
  public func pause(_ node: AudioPlaybackNode) { player(for: node).pause() }
  public func stop(_ node: AudioPlaybackNode) { player(for: node).stop() }
  public func setVolume(_ volume: Float, on node: AudioPlaybackNode) { player(for: node).volume = volume }

  public func renderedSeconds(for node: AudioPlaybackNode) -> TimeInterval? {
    let player = player(for: node)
    guard let renderTime = player.lastRenderTime,
      let playerTime = player.playerTime(forNodeTime: renderTime)
    else { return nil }
    return Double(playerTime.sampleTime) / playerTime.sampleRate
  }

  private func player(for node: AudioPlaybackNode) -> AVAudioPlayerNode {
    switch node {
    case .primary: primary
    case .secondary: secondary
    }
  }
}
