import Foundation

public struct StorageCapacityPolicy: Sendable {
  public init() {}

  public func canStore(currentBytes: Int64, incomingBytes: Int64, limitBytes: Int64) -> Bool {
    guard currentBytes >= 0, incomingBytes >= 0, limitBytes >= 0 else { return false }
    guard currentBytes <= limitBytes else { return false }
    return incomingBytes <= limitBytes - currentBytes
  }
}
