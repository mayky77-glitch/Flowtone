import Foundation

/// Stores a user's confirmation that they personally opened and read the official model terms.
///
/// This is deliberately not a record of accepting any third-party terms. Acceptance remains an
/// action the user must complete personally before Flowtone downloads third-party model weights.
public final class ModelLicenseAcknowledgement {
  public static let stableAudioTermsAcknowledgementText =
    "Я сам(а) открыл(а) и прочитал(а) официальные страницы Stable Audio, Gemma и ACE-Step. "
    + "Flowtone не принимает эти условия от моего имени; после подтверждения он может скачать "
    + "выбранную официальную модель на этот Mac."

  private static let stableAudioTermsAcknowledgementKey =
    "Flowtone.stableAudioTermsAcknowledgement"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var hasAcknowledgedStableAudioTerms: Bool {
    defaults.bool(forKey: Self.stableAudioTermsAcknowledgementKey)
  }

  public func acknowledgeStableAudioTerms() {
    defaults.set(true, forKey: Self.stableAudioTermsAcknowledgementKey)
  }

  public func clearStableAudioTermsAcknowledgement() {
    defaults.removeObject(forKey: Self.stableAudioTermsAcknowledgementKey)
  }
}
