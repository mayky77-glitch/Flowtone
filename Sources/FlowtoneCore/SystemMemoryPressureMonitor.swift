import Dispatch
import Foundation

/// Keeps the scheduler's memory gate connected to the macOS pressure notifications.
public final class SystemMemoryPressureMonitor: @unchecked Sendable {
  public static let shared = SystemMemoryPressureMonitor()

  private let lock = NSLock()
  private let source: DispatchSourceMemoryPressure
  private var pressure: MemoryPressure = .normal
  private var observers: [UUID: @Sendable (MemoryPressure) -> Void] = [:]

  private init() {
    source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical],
      queue: DispatchQueue(label: "com.flowtone.memory-pressure", qos: .utility)
    )
    source.setEventHandler { [weak self] in
      self?.recordCurrentEvent()
    }
    source.resume()
  }

  public var current: MemoryPressure {
    lock.withLock { pressure }
  }

  @discardableResult
  public func observe(_ handler: @escaping @Sendable (MemoryPressure) -> Void) -> UUID {
    let id = UUID()
    lock.withLock { observers[id] = handler }
    return id
  }

  public func removeObservation(_ id: UUID) {
    lock.withLock { observers[id] = nil }
  }

  private func recordCurrentEvent() {
    let event = source.data
    let next: MemoryPressure
    if event.contains(.critical) {
      next = .critical
    } else if event.contains(.warning) {
      next = .warning
    } else {
      next = .normal
    }
    let handlers = lock.withLock {
      pressure = next
      return Array(observers.values)
    }
    for handler in handlers {
      handler(next)
    }
  }
}
