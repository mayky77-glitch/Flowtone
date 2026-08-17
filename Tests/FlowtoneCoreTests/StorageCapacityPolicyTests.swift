import Testing

@testable import FlowtoneCore

@Suite("StorageCapacityPolicy")
struct StorageCapacityPolicyTests {
  @Test("Incoming track must fit without deleting existing audio")
  func capacity() {
    let policy = StorageCapacityPolicy()

    #expect(policy.canStore(currentBytes: 70, incomingBytes: 30, limitBytes: 100))
    #expect(!policy.canStore(currentBytes: 71, incomingBytes: 30, limitBytes: 100))
    #expect(!policy.canStore(currentBytes: 101, incomingBytes: 0, limitBytes: 100))
  }

  @Test("Invalid and overflowing-like inputs are rejected")
  func invalidInputs() {
    let policy = StorageCapacityPolicy()

    #expect(!policy.canStore(currentBytes: -1, incomingBytes: 1, limitBytes: 100))
    #expect(!policy.canStore(currentBytes: 1, incomingBytes: -1, limitBytes: 100))
    #expect(
      !policy.canStore(
        currentBytes: Int64.max,
        incomingBytes: Int64.max,
        limitBytes: Int64.max
      ))
  }
}
