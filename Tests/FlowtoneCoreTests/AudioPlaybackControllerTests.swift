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
  }

  var durations: [TimeInterval]
  var scheduled: [Scheduled] = []
  var played: [AudioPlaybackNode] = []
  var stopped: [AudioPlaybackNode] = []
  var volumes: [AudioPlaybackNode: Float] = [:]
  var rendered: [AudioPlaybackNode: TimeInterval] = [:]

  init(durations: [TimeInterval]) { self.durations = durations }

  func schedule(_ item: AudioPlaybackItem, on node: AudioPlaybackNode) throws -> TimeInterval {
    scheduled.append(Scheduled(item: item, node: node))
    return durations.removeFirst()
  }

  func startEngine() throws {}
  func play(_ node: AudioPlaybackNode) { played.append(node) }
  func pause(_ node: AudioPlaybackNode) {}
  func stop(_ node: AudioPlaybackNode) { stopped.append(node) }
  func setVolume(_ volume: Float, on node: AudioPlaybackNode) { volumes[node] = volume }
  func renderedSeconds(for node: AudioPlaybackNode) -> TimeInterval? { rendered[node] }
}
