import Foundation

public struct RadioPlaybackQueue: Equatable, Sendable {
  public private(set) var currentTrackID: UUID?
  public private(set) var readyTrackIDs: [UUID]

  public init(currentTrackID: UUID? = nil) {
    self.currentTrackID = currentTrackID
    readyTrackIDs = []
  }

  public var protectedTrackIDs: Set<UUID> {
    var trackIDs = Set(readyTrackIDs)
    if let currentTrackID {
      trackIDs.insert(currentTrackID)
    }
    return trackIDs
  }

  public var needsPrefill: Bool {
    readyTrackIDs.count < Self.readyCapacity
  }

  @discardableResult
  public mutating func setCurrent(_ trackID: UUID?) -> Bool {
    guard trackID != currentTrackID else {
      return false
    }
    guard trackID.map({ !readyTrackIDs.contains($0) }) ?? true else {
      return false
    }

    currentTrackID = trackID
    return true
  }

  @discardableResult
  public mutating func enqueue(_ trackID: UUID) -> Bool {
    guard readyTrackIDs.count < Self.readyCapacity else {
      return false
    }
    guard trackID != currentTrackID, !readyTrackIDs.contains(trackID) else {
      return false
    }

    readyTrackIDs.append(trackID)
    return true
  }

  @discardableResult
  public mutating func advance() -> UUID? {
    currentTrackID = readyTrackIDs.isEmpty ? nil : readyTrackIDs.removeFirst()
    return currentTrackID
  }

  @discardableResult
  public mutating func remove(_ trackID: UUID) -> Bool {
    if currentTrackID == trackID {
      currentTrackID = nil
      return true
    }

    guard let index = readyTrackIDs.firstIndex(of: trackID) else {
      return false
    }
    readyTrackIDs.remove(at: index)
    return true
  }

  private static let readyCapacity = 2
}
