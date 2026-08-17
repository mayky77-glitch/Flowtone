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

/// The direction used for a short audible vinyl-scrub preview.
public enum AudioScrubDirection: Equatable, Sendable {
  case backward
  case forward
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
  func schedule(
    _ item: AudioPlaybackItem,
    on node: AudioPlaybackNode,
    startingAt position: TimeInterval
  ) throws -> TimeInterval
  func preview(
    _ item: AudioPlaybackItem,
    on node: AudioPlaybackNode,
    at position: TimeInterval,
    direction: AudioScrubDirection
  ) throws
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
  public private(set) var isScrubbing = false

  public var currentID: UUID? { currentItem?.id }
  public var queuedID: UUID? { queuedItem?.id }
  public var crossfadeDuration: TimeInterval { requestedCrossfadeDuration }
  public var duration: TimeInterval { currentDuration }
  public var position: TimeInterval {
    min(max(playbackPosition(), 0), max(currentDuration, 0))
  }
  public var progress: Double {
    guard currentDuration > 0 else { return 0 }
    return min(max(position / currentDuration, 0), 1)
  }

  private let backend: any AudioPlaybackBackend
  private let clock: any AudioPlaybackClock
  private let gainProvider: GainProvider
  private let onTransition: TransitionHandler?
  private let onNextNeeded: NextNeededHandler?

  private var activeNode: AudioPlaybackNode = .primary
  private var currentDuration: TimeInterval = 0
  private var currentStartPosition: TimeInterval = 0
  private var queuedDuration: TimeInterval?
  private var requestedCrossfadeDuration: TimeInterval = 0
  private var lastObservedPosition: TimeInterval = 0
  private var startedAt: TimeInterval?
  private var transitionHasStarted = false
  private var hasRequestedNext = false
  private var volume: Float = 1
  private var wasPlayingBeforeScrub = false
  private var lastScrubPreviewAt: TimeInterval?
  private var scrubPreviewNode: AudioPlaybackNode?

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
    currentDuration = try schedule(current, on: activeNode, startingAt: 0)
    currentStartPosition = 0
    queuedDuration = nil
    currentItem = current
    queuedItem = nil
    requestedCrossfadeDuration = crossfadeDuration
    lastObservedPosition = 0
    startedAt = nil
    transitionHasStarted = false
    hasRequestedNext = false
    isPlaying = false
    isScrubbing = false
    applyGains(progress: 0)

    if let next {
      try replaceNext(with: next)
    }
  }

  public func play() throws {
    guard currentItem != nil else { throw AudioPlaybackControllerError.missingCurrentItem }
    if isScrubbing { try endScrubbing() }
    if !isPlaying {
      try backend.startEngine()
      backend.play(activeNode)
      if transitionHasStarted, queuedItem != nil { backend.play(activeNode.other) }
      startedAt = clock.now
      isPlaying = true
    }
  }

  public func pause() {
    guard !isScrubbing else { return }
    guard isPlaying else { return }
    lastObservedPosition = playbackPosition()
    backend.pause(activeNode)
    if transitionHasStarted, queuedItem != nil { backend.pause(activeNode.other) }
    startedAt = nil
    isPlaying = false
  }

  /// Stops both nodes and releases the current and queued file references.
  public func clear() {
    backend.stop(.primary)
    backend.stop(.secondary)
    currentItem = nil
    queuedItem = nil
    currentDuration = 0
    currentStartPosition = 0
    queuedDuration = nil
    lastObservedPosition = 0
    startedAt = nil
    transitionHasStarted = false
    hasRequestedNext = false
    isPlaying = false
    isScrubbing = false
    lastScrubPreviewAt = nil
    scrubPreviewNode = nil
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

  /// Re-schedules the current item from an absolute position while preserving play/pause state.
  public func seek(to position: TimeInterval) throws {
    guard currentItem != nil else { throw AudioPlaybackControllerError.missingCurrentItem }
    let shouldResume = isScrubbing ? wasPlayingBeforeScrub : isPlaying
    isScrubbing = false
    try rescheduleCurrent(at: position, resumePlayback: shouldResume)
  }

  /// Stops normal playback and keeps the current/queued items ready for audible vinyl scrubbing.
  public func beginScrubbing() throws {
    guard currentItem != nil else { throw AudioPlaybackControllerError.missingCurrentItem }
    guard !isScrubbing else { return }

    let capturedPosition = position
    wasPlayingBeforeScrub = isPlaying
    backend.stop(.primary)
    backend.stop(.secondary)
    lastObservedPosition = capturedPosition
    currentStartPosition = capturedPosition
    startedAt = nil
    transitionHasStarted = false
    isPlaying = false
    isScrubbing = true
    lastScrubPreviewAt = nil
    scrubPreviewNode = nil
    applyGains(progress: 0)
  }

  /// Plays a short forward or reversed fragment at `position` and updates the pending seek target.
  public func scrub(to position: TimeInterval, direction: AudioScrubDirection) throws {
    guard let currentItem else { throw AudioPlaybackControllerError.missingCurrentItem }
    if !isScrubbing { try beginScrubbing() }

    let target = clampedPosition(position)
    lastObservedPosition = target
    currentStartPosition = target

    let now = clock.now
    let shouldPreview = lastScrubPreviewAt == nil || now - (lastScrubPreviewAt ?? 0) >= 0.05
    guard shouldPreview else { return }

    let previewNode = scrubPreviewNode?.other ?? activeNode
    backend.stop(previewNode)
    try backend.startEngine()
    try backend.preview(currentItem, on: previewNode, at: target, direction: direction)
    backend.setVolume(volume, on: previewNode)
    backend.play(previewNode)
    lastScrubPreviewAt = now
    scrubPreviewNode = previewNode
  }

  /// Leaves scratch mode at the selected position and restores the state from before the gesture.
  public func endScrubbing() throws {
    guard isScrubbing else { return }
    let target = lastObservedPosition
    let shouldResume = wasPlayingBeforeScrub
    isScrubbing = false
    wasPlayingBeforeScrub = false
    lastScrubPreviewAt = nil
    scrubPreviewNode = nil
    try rescheduleCurrent(at: target, resumePlayback: shouldResume)
  }

  /// Sets the master output volume. Values outside `0...1` are safely clamped.
  public func setVolume(_ volume: Float) {
    self.volume = min(max(volume, 0), 1)
    let progress = transitionHasStarted ? transitionProgress(at: playbackPosition()) : 0
    applyGains(progress: progress)
  }

  /// Updates the duration used for the next transition without reloading either node.
  public func setCrossfadeDuration(_ duration: TimeInterval) throws {
    guard duration.isFinite, duration >= 0 else {
      throw AudioPlaybackControllerError.invalidCrossfadeDuration
    }
    requestedCrossfadeDuration = duration
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

    queuedDuration = try schedule(item, on: standbyNode, startingAt: 0)
    backend.setVolume(0, on: standbyNode)
    queuedItem = item
    hasRequestedNext = false
  }

  /// Observes render progress and performs any due crossfade state changes.
  public func update() {
    guard isPlaying, !isScrubbing, currentItem != nil else { return }

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

  private func schedule(
    _ item: AudioPlaybackItem,
    on node: AudioPlaybackNode,
    startingAt position: TimeInterval
  ) throws -> TimeInterval {
    let duration = try backend.schedule(item, on: node, startingAt: position)
    guard duration.isFinite, duration > 0 else {
      throw AudioPlaybackControllerError.invalidScheduledDuration
    }
    return duration
  }

  private func playbackPosition() -> TimeInterval {
    if isScrubbing { return lastObservedPosition }
    if let renderedSeconds = backend.renderedSeconds(for: activeNode), renderedSeconds.isFinite {
      return max(0, currentStartPosition + renderedSeconds)
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
    currentStartPosition = 0
    queuedDuration = nil
    lastObservedPosition = incomingPosition
    startedAt = isPlaying ? clock.now : nil
    transitionHasStarted = false
    backend.setVolume(volume, on: activeNode)
    backend.setVolume(0, on: activeNode.other)
    onTransition?(outgoing.id, incoming.id)
    requestNextIfNeeded()
  }

  private func rescheduleCurrent(at requestedPosition: TimeInterval, resumePlayback: Bool) throws {
    guard let currentItem else { throw AudioPlaybackControllerError.missingCurrentItem }
    let target = clampedPosition(requestedPosition)
    let preservedQueuedItem = queuedItem

    backend.stop(.primary)
    backend.stop(.secondary)
    transitionHasStarted = false
    currentStartPosition = target
    lastObservedPosition = target
    startedAt = nil
    isPlaying = false
    currentDuration = try schedule(currentItem, on: activeNode, startingAt: target)

    queuedDuration = nil
    if let preservedQueuedItem {
      queuedDuration = try schedule(preservedQueuedItem, on: activeNode.other, startingAt: 0)
      backend.setVolume(0, on: activeNode.other)
    }
    applyGains(progress: 0)

    guard resumePlayback else { return }
    try backend.startEngine()
    backend.play(activeNode)
    startedAt = clock.now
    isPlaying = true
  }

  private func clampedPosition(_ position: TimeInterval) -> TimeInterval {
    guard currentDuration > 0 else { return 0 }
    let lastPlayablePosition = max(0, currentDuration - (1 / 44_100))
    guard position.isFinite else { return position.sign == .minus ? 0 : lastPlayablePosition }
    return min(max(position, 0), lastPlayablePosition)
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
  private let primarySpeed = AVAudioUnitVarispeed()
  private let secondarySpeed = AVAudioUnitVarispeed()

  public init(engine: AVAudioEngine = AVAudioEngine()) {
    self.engine = engine
    engine.attach(primary)
    engine.attach(secondary)
    engine.attach(primarySpeed)
    engine.attach(secondarySpeed)
    engine.connect(primary, to: primarySpeed, format: nil)
    engine.connect(secondary, to: secondarySpeed, format: nil)
    engine.connect(primarySpeed, to: engine.mainMixerNode, format: nil)
    engine.connect(secondarySpeed, to: engine.mainMixerNode, format: nil)
  }

  public func schedule(
    _ item: AudioPlaybackItem,
    on node: AudioPlaybackNode,
    startingAt position: TimeInterval
  ) throws -> TimeInterval {
    let file = try AVAudioFile(forReading: item.fileURL)
    speed(for: node).rate = 1
    let duration = Double(file.length) / file.processingFormat.sampleRate
    let requestedFrame = AVAudioFramePosition(max(0, position) * file.processingFormat.sampleRate)
    let startFrame = min(max(0, requestedFrame), max(0, file.length - 1))
    let remainingFrames = max(1, file.length - startFrame)
    let frameCount = AVAudioFrameCount(
      min(remainingFrames, AVAudioFramePosition(UInt32.max)))
    player(for: node).scheduleSegment(
      file,
      startingFrame: startFrame,
      frameCount: frameCount,
      at: nil
    )
    return duration
  }

  public func preview(
    _ item: AudioPlaybackItem,
    on node: AudioPlaybackNode,
    at position: TimeInterval,
    direction: AudioScrubDirection
  ) throws {
    let file = try AVAudioFile(forReading: item.fileURL)
    let format = file.processingFormat
    // Short overlapping grains follow the hand more closely than long preview
    // chunks and avoid the flanging produced by two 220 ms fragments colliding.
    let previewFrames = AVAudioFramePosition(max(256, Int(format.sampleRate * 0.11)))
    let targetFrame = min(
      max(0, AVAudioFramePosition(position * format.sampleRate)),
      max(0, file.length - 1)
    )
    let startFrame: AVAudioFramePosition
    switch direction {
    case .forward:
      startFrame = targetFrame
    case .backward:
      startFrame = max(0, targetFrame - previewFrames)
    }
    let availableFrames = max(1, file.length - startFrame)
    let frameCount = AVAudioFrameCount(
      min(previewFrames, availableFrames, AVAudioFramePosition(UInt32.max)))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      return
    }

    file.framePosition = startFrame
    try file.read(into: buffer, frameCount: frameCount)
    if direction == .backward { Self.reverse(buffer) }
    Self.applyScratchEnvelope(buffer)

    speed(for: node).rate = 1

    let player = player(for: node)
    player.scheduleBuffer(buffer, at: nil, options: .interrupts)
  }

  public func startEngine() throws {
    guard !engine.isRunning else { return }
    try engine.start()
  }

  public func play(_ node: AudioPlaybackNode) { player(for: node).play() }
  public func pause(_ node: AudioPlaybackNode) { player(for: node).pause() }
  public func stop(_ node: AudioPlaybackNode) { player(for: node).stop() }
  public func setVolume(_ volume: Float, on node: AudioPlaybackNode) {
    player(for: node).volume = volume
  }

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

  private func speed(for node: AudioPlaybackNode) -> AVAudioUnitVarispeed {
    switch node {
    case .primary: primarySpeed
    case .secondary: secondarySpeed
    }
  }

  private static func reverse(_ buffer: AVAudioPCMBuffer) {
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameCount > 1 else { return }

    if let channels = buffer.floatChannelData {
      for channel in 0..<channelCount {
        let samples = channels[channel]
        for index in 0..<(frameCount / 2) {
          let opposite = frameCount - index - 1
          let value = samples[index]
          samples[index] = samples[opposite]
          samples[opposite] = value
        }
      }
    } else if let channels = buffer.int16ChannelData {
      for channel in 0..<channelCount {
        let samples = channels[channel]
        for index in 0..<(frameCount / 2) {
          let opposite = frameCount - index - 1
          let value = samples[index]
          samples[index] = samples[opposite]
          samples[opposite] = value
        }
      }
    } else if let channels = buffer.int32ChannelData {
      for channel in 0..<channelCount {
        let samples = channels[channel]
        for index in 0..<(frameCount / 2) {
          let opposite = frameCount - index - 1
          let value = samples[index]
          samples[index] = samples[opposite]
          samples[opposite] = value
        }
      }
    }
  }

  private static func applyScratchEnvelope(_ buffer: AVAudioPCMBuffer) {
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    let edge = min(frameCount / 4, max(32, Int(buffer.format.sampleRate * 0.012)))
    guard edge > 0 else { return }

    func gain(_ index: Int) -> Double {
      let phase = Double(index + 1) / Double(edge + 1) * .pi / 2
      let value = sin(phase)
      return value * value
    }

    if let channels = buffer.floatChannelData {
      for channel in 0..<channelCount {
        let samples = channels[channel]
        for index in 0..<edge {
          let value = Float(gain(index))
          samples[index] *= value
          samples[frameCount - index - 1] *= value
        }
      }
    } else if let channels = buffer.int16ChannelData {
      for channel in 0..<channelCount {
        let samples = channels[channel]
        for index in 0..<edge {
          let value = gain(index)
          samples[index] = Int16(Double(samples[index]) * value)
          let opposite = frameCount - index - 1
          samples[opposite] = Int16(Double(samples[opposite]) * value)
        }
      }
    } else if let channels = buffer.int32ChannelData {
      for channel in 0..<channelCount {
        let samples = channels[channel]
        for index in 0..<edge {
          let value = gain(index)
          samples[index] = Int32(Double(samples[index]) * value)
          let opposite = frameCount - index - 1
          samples[opposite] = Int32(Double(samples[opposite]) * value)
        }
      }
    }
  }
}
