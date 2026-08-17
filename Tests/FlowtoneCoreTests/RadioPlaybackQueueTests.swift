import Foundation
import Testing

@testable import FlowtoneCore

@Suite("RadioPlaybackQueue")
struct RadioPlaybackQueueTests {
  @Test("Enqueue preserves insertion order, rejects duplicates, and caps ready tracks")
  func enqueueMaintainsTwoReadyTracks() {
    let current = UUID()
    let first = UUID()
    let second = UUID()
    let overflow = UUID()
    var queue = RadioPlaybackQueue(currentTrackID: current)

    let insertedFirst = queue.enqueue(first)
    let insertedSecond = queue.enqueue(second)
    let rejectedCurrent = queue.enqueue(current)
    let rejectedDuplicate = queue.enqueue(first)
    let rejectedOverflow = queue.enqueue(overflow)

    #expect(insertedFirst)
    #expect(insertedSecond)
    #expect(queue.readyTrackIDs == [first, second])
    #expect(!rejectedCurrent)
    #expect(!rejectedDuplicate)
    #expect(!rejectedOverflow)
  }

  @Test("Advance promotes the first ready track and consumes it")
  func advancePromotesFirstReadyTrack() {
    let current = UUID()
    let first = UUID()
    let second = UUID()
    var queue = RadioPlaybackQueue(currentTrackID: current)
    _ = queue.enqueue(first)
    _ = queue.enqueue(second)

    let promotedFirst = queue.advance()
    #expect(promotedFirst == first)
    #expect(queue.currentTrackID == first)
    #expect(queue.readyTrackIDs == [second])
    #expect(queue.needsPrefill)

    let promotedSecond = queue.advance()
    #expect(promotedSecond == second)
    #expect(queue.currentTrackID == second)
    #expect(queue.readyTrackIDs.isEmpty)

    let promotedEmptyQueue = queue.advance()
    #expect(promotedEmptyQueue == nil)
    #expect(queue.currentTrackID == nil)
  }

  @Test("Protected IDs always match current plus ready tracks")
  func protectedTrackIDsMatchQueueState() {
    let current = UUID()
    let first = UUID()
    let second = UUID()
    var queue = RadioPlaybackQueue(currentTrackID: current)
    _ = queue.enqueue(first)
    _ = queue.enqueue(second)

    #expect(queue.protectedTrackIDs == Set([current, first, second]))
  }

  @Test("Removal leaves a valid queue and indicates when prefill is needed")
  func removalMaintainsValidState() {
    let current = UUID()
    let first = UUID()
    let second = UUID()
    var queue = RadioPlaybackQueue(currentTrackID: current)
    _ = queue.enqueue(first)
    _ = queue.enqueue(second)

    let removedFirst = queue.remove(first)
    #expect(removedFirst)
    #expect(queue.currentTrackID == current)
    #expect(queue.readyTrackIDs == [second])
    #expect(queue.needsPrefill)

    let removedCurrent = queue.remove(current)
    let removedMissingTrack = queue.remove(first)
    #expect(removedCurrent)
    #expect(queue.currentTrackID == nil)
    #expect(queue.protectedTrackIDs == Set([second]))
    #expect(!removedMissingTrack)
  }

  @Test("Current track cannot duplicate a ready track")
  func setCurrentRejectsReadyTrack() {
    let current = UUID()
    let ready = UUID()
    var queue = RadioPlaybackQueue(currentTrackID: current)
    _ = queue.enqueue(ready)

    let rejectedReadyTrack = queue.setCurrent(ready)
    let rejectedExistingCurrent = queue.setCurrent(current)

    #expect(!rejectedReadyTrack)
    #expect(queue.currentTrackID == current)
    #expect(!rejectedExistingCurrent)

    let clearedCurrent = queue.setCurrent(nil)
    #expect(clearedCurrent)
    #expect(queue.currentTrackID == nil)
  }

  @Test("Current deletion prefers the queued neighbor then history then library")
  func deletionReplacementOrder() {
    let current = UUID()
    let queued = UUID()
    let previous = UUID()
    let remaining = UUID()
    let library = [current, remaining, previous, queued]

    #expect(
      CurrentTrackDeletionPlanner.replacementTrackID(
        currentTrackID: current,
        readyTrackIDs: [queued],
        previousHistoryTrackID: previous,
        libraryTrackIDs: library
      ) == queued
    )
    #expect(
      CurrentTrackDeletionPlanner.replacementTrackID(
        currentTrackID: current,
        readyTrackIDs: [],
        previousHistoryTrackID: previous,
        libraryTrackIDs: library
      ) == previous
    )
    #expect(
      CurrentTrackDeletionPlanner.replacementTrackID(
        currentTrackID: current,
        readyTrackIDs: [],
        previousHistoryTrackID: nil,
        libraryTrackIDs: [current, remaining]
      ) == remaining
    )
  }
}
