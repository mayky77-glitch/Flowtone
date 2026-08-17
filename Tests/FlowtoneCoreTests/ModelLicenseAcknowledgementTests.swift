import Foundation
import Testing

@testable import FlowtoneCore

@Suite(.serialized) struct ModelLicenseAcknowledgementTests {
  @Test func acknowledgementPersistsInInjectedDefaultsSuite() {
    let suiteName = "ModelLicenseAcknowledgementTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let acknowledgement = ModelLicenseAcknowledgement(defaults: defaults)

    #expect(!acknowledgement.hasAcknowledgedStableAudioTerms)
    acknowledgement.acknowledgeStableAudioTerms()
    #expect(acknowledgement.hasAcknowledgedStableAudioTerms)
    #expect(
      ModelLicenseAcknowledgement(defaults: defaults).hasAcknowledgedStableAudioTerms)
  }

  @Test func acknowledgementCanBeCleared() {
    let suiteName = "ModelLicenseAcknowledgementTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let acknowledgement = ModelLicenseAcknowledgement(defaults: defaults)
    acknowledgement.acknowledgeStableAudioTerms()
    acknowledgement.clearStableAudioTermsAcknowledgement()

    #expect(!acknowledgement.hasAcknowledgedStableAudioTerms)
  }
}
