import Dispatch
import Foundation

/// Keeps the scheduler's memory gate connected to the macOS pressure notifications.
public final class SystemMemoryPressureMonitor: @unchecked Sendable {
  public static let shared = SystemMemoryPressureMonitor()

  private let lock = NSLock()
  private let source: DispatchSourceMemoryPressure
  private var pressure: MemoryPressure = .normal

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
    lock.withLock { pressure = next }
  }
}
