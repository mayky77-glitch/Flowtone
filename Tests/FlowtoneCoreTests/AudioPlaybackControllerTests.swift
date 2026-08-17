import Foundation
import Testing

@testable import FlowtoneCore

@Suite("Audio playback controller")
struct AudioPlaybackControllerTests {
  @Test("Schedules current and next across the two nodes without hardware")
  func schedulesTwoNodes() throws {
    let backend = TestBackend(durations: [10, 8])
    let controller = makeController(backend: backend)
    let current = item(1)
    let next = item(2)

    try controller.load(current: current, next: next, crossfadeDuration: 2)

    #expect(controller.currentID == current.id)
    #expect(controller.queuedID == next.id)
    #expect(backend.scheduled.map(\.node) == [.primary, .secondary])
    #expect(backend.scheduled.map(\.startingAt) == [0, 0])
    #expect(backend.volumes[.primary] == 1)
    #expect(backend.volumes[.secondary] == 0)
  }

  @Test("Render timing starts an equal-power transition and promotes the queued item")
  func transitionsUsingRenderTime() throws {
    let backend = TestBackend(durations: [10, 8])
    var transitions: [(UUID, UUID)] = []
    var requested: [UUID] = []
    let controller = AudioPlaybackController(
      backend: backend,
      clock: TestClock(),
      gainProvider: { progress in (Float(1 - progress), Float(progress)) },
      onTransition: { transitions.append(($0, $1)) },
      onNextNeeded: { requested.append($0) }
    )
    let current = item(1)
    let next = item(2)
    try controller.load(current: current, next: next, crossfadeDuration: 2)
    try controller.play()

    backend.rendered[.primary] = 9
    controller.update()
    #expect(backend.played == [.primary, .secondary])
    #expect(backend.volumes[.primary] == 0.5)
    #expect(backend.volumes[.secondary] == 0.5)

    backend.rendered[.primary] = 10
    controller.update()
    #expect(controller.currentID == next.id)
    #expect(controller.queuedID == nil)
    #expect(transitions.count == 1)
    #expect(transitions.first?.0 == current.id)
    #expect(transitions.first?.1 == next.id)
    #expect(requested == [next.id])
    #expect(backend.stopped.contains(.primary))
  }

  @Test("Clock fallback drives next-needed once when no queued item exists")
  func requestsNextUsingClockFallback() throws {
    let backend = TestBackend(durations: [10])
    let clock = TestClock(now: 100)
    var requested: [UUID] = []
    let controller = AudioPlaybackController(
      backend: backend,
      clock: clock,
      gainProvider: { _ in (1, 0) },
      onNextNeeded: { requested.append($0) }
    )
    let current = item(1)
    try controller.load(current: current, crossfadeDuration: 3)
    try controller.play()

    clock.now = 107
    controller.update()
    controller.update()

    #expect(requested == [current.id])
  }

  @Test("Pause preserves fallback-clock progress and replacement stays on standby")
  func pauseAndReplaceNext() throws {
    let backend = TestBackend(durations: [10, 9, 7])
    let clock = TestClock(now: 0)
    let controller = AudioPlaybackController(
      backend: backend,
      clock: clock,
      gainProvider: { progress in (Float(1 - progress), Float(progress)) }
    )
    try controller.load(current: item(1), next: item(2), crossfadeDuration: 2)
    try controller.play()
    clock.now = 3
    controller.pause()
    try controller.replaceNext(with: item(3))
    clock.now = 5
    try controller.play()
    clock.now = 10
    controller.update()

    #expect(controller.queuedID == item(3).id)
    #expect(backend.scheduled.map(\.item.id) == [item(1).id, item(2).id, item(3).id])
    #expect(backend.stopped.filter { $0 == .secondary }.count >= 2)
    #expect(backend.played.contains(.secondary))
  }

  @Test("Rejects invalid lifecycle input")
  func rejectsInvalidInput() {
    let backend = TestBackend(durations: [10])
    let controller = makeController(backend: backend)

    #expect(throws: AudioPlaybackControllerError.missingCurrentItem) { try controller.play() }
    #expect(throws: AudioPlaybackControllerError.invalidCrossfadeDuration) {
      try controller.load(current: item(1), crossfadeDuration: -.infinity)
    }
    #expect(throws: AudioPlaybackControllerError.invalidCrossfadeDuration) {
      try controller.setCrossfadeDuration(.nan)
    }
  }

  @Test("Crossfade duration can follow the newly queued pair")
  func updatesCrossfadeDuration() throws {
    let controller = makeController(backend: TestBackend(durations: [10]))
    try controller.load(current: item(1), crossfadeDuration: 2)

    try controller.setCrossfadeDuration(5)

    #expect(controller.crossfadeDuration == 5)
  }

  @Test("Skip immediately promotes and starts the scheduled next item")
  func skipPromotesNext() throws {
    let backend = TestBackend(durations: [10, 8])
    var requested: [UUID] = []
    let controller = AudioPlaybackController(
      backend: backend,
      clock: TestClock(),
      gainProvider: { _ in (1, 0) },
      onNextNeeded: { requested.append($0) }
    )
    let current = item(1)
    let next = item(2)
    try controller.load(current: current, next: next, crossfadeDuration: 2)
    try controller.play()
    try controller.skip()

    #expect(controller.currentID == next.id)
    #expect(controller.queuedID == nil)
    #expect(backend.played == [.primary, .secondary])
    #expect(requested == [next.id])
  }

  @Test("Seek clamps positions, preserves the queue, and resumes playback")
  func seekPreservesQueueAndPlayback() throws {
    let backend = TestBackend(durations: [10, 8, 10, 8, 10, 8, 10, 8])
    let clock = TestClock(now: 0)
    let controller = AudioPlaybackController(
      backend: backend,
      clock: clock,
      gainProvider: { _ in (1, 0) }
    )
    try controller.load(current: item(1), next: item(2), crossfadeDuration: 2)
    try controller.play()
    clock.now = 3

    try controller.seek(to: 7)
    #expect(controller.position == 7)
    #expect(controller.isPlaying)
    #expect(controller.queuedID == item(2).id)
    #expect(backend.scheduled.map(\.startingAt) == [0, 0, 7, 0])

    try controller.seek(to: -.infinity)
    #expect(controller.position == 0)
    try controller.seek(to: .infinity)
    #expect(controller.position > 9.99)
    #expect(controller.position < 10)
  }

  @Test("Vinyl scrub auditions direction and restores prior playback state")
  func vinylScrubRestoresPlayback() throws {
    let backend = TestBackend(durations: [10, 8, 10, 8])
    let clock = TestClock(now: 0)
    let controller = AudioPlaybackController(
      backend: backend,
      clock: clock,
      gainProvider: { _ in (1, 0) }
    )
    try controller.load(current: item(1), next: item(2), crossfadeDuration: 2)
    try controller.play()
    clock.now = 2

    try controller.beginScrubbing()
    try controller.scrub(to: 6, direction: .backward)

    #expect(controller.isScrubbing)
    #expect(!controller.isPlaying)
    #expect(controller.position == 6)
    #expect(backend.previews.count == 1)
    #expect(backend.previews.first?.position == 6)
    #expect(backend.previews.first?.direction == .backward)

    try controller.endScrubbing()
    #expect(!controller.isScrubbing)
    #expect(controller.isPlaying)
    #expect(controller.position == 6)
    #expect(controller.queuedID == item(2).id)
    #expect(backend.scheduled.map(\.startingAt) == [0, 0, 6, 0])
  }

  @Test("Scratch previews are throttled and alternate nodes for smoother overlap")
  func scratchPreviewCadence() throws {
    let backend = TestBackend(durations: [10])
    let clock = TestClock(now: 1)
    let controller = AudioPlaybackController(
      backend: backend,
      clock: clock,
      gainProvider: { _ in (1, 0) }
    )
    try controller.load(current: item(1), crossfadeDuration: 0)
    try controller.beginScrubbing()

    try controller.scrub(to: 2, direction: .forward)
    clock.now = 1.03
    try controller.scrub(to: 3, direction: .forward)
    #expect(controller.position == 3)
    #expect(backend.previews.count == 1)

    clock.now = 1.09
    try controller.scrub(to: 4, direction: .forward)
    #expect(backend.previews.map(\.node) == [.primary, .secondary])

    clock.now = 1.18
    try controller.scrub(to: 3.5, direction: .backward)
    #expect(backend.previews.map(\.direction) == [.forward, .forward, .backward])
    #expect(backend.previews.map(\.node) == [.primary, .secondary, .primary])
  }

  private func makeController(backend: TestBackend) -> AudioPlaybackController {
    AudioPlaybackController(
      backend: backend,
      clock: TestClock(),
      gainProvider: { progress in (Float(1 - progress), Float(progress)) }
    )
  }

  private func item(_ value: UInt8) -> AudioPlaybackItem {
    AudioPlaybackItem(
      id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value)),
      fileURL: URL(fileURLWithPath: "/tmp/track-\(value).wav")
    )
  }
}

private final class TestClock: AudioPlaybackClock {
  var now: TimeInterval

  init(now: TimeInterval = 0) { self.now = now }
}

private final class TestBackend: AudioPlaybackBackend {
  struct Scheduled {
    let item: AudioPlaybackItem
    let node: AudioPlaybackNode
    let startingAt: TimeInterval
  }

  struct Preview {
    let item: AudioPlaybackItem
    let node: AudioPlaybackNode
    let position: TimeInterval
    let direction: AudioScrubDirection
  }

  var durations: [TimeInterval]
  var scheduled: [Scheduled] = []
  var previews: [Preview] = []
  var played: [AudioPlaybackNode] = []
  var stopped: [AudioPlaybackNode] = []
  var volumes: [AudioPlaybackNode: Float] = [:]
  var rendered: [AudioPlaybackNode: TimeInterval] = [:]

  init(durations: [TimeInterval]) { self.durations = durations }

  func schedule(
    _ item: AudioPlaybackItem,
    on node: AudioPlaybackNode,
    startingAt position: TimeInterval
  ) throws -> TimeInterval {
    scheduled.append(Scheduled(item: item, node: node, startingAt: position))
    return durations.removeFirst()
  }

  func preview(
    _ item: AudioPlaybackItem,
    on node: AudioPlaybackNode,
    at position: TimeInterval,
    direction: AudioScrubDirection
  ) throws {
    previews.append(Preview(item: item, node: node, position: position, direction: direction))
  }

  func startEngine() throws {}
  func play(_ node: AudioPlaybackNode) { played.append(node) }
  func pause(_ node: AudioPlaybackNode) {}
  func stop(_ node: AudioPlaybackNode) { stopped.append(node) }
  func setVolume(_ volume: Float, on node: AudioPlaybackNode) { volumes[node] = volume }
  func renderedSeconds(for node: AudioPlaybackNode) -> TimeInterval? { rendered[node] }
}
