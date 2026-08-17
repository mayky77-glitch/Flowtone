import Foundation

/// Stores a user's confirmation that they personally opened and read the official model terms.
///
/// This is deliberately not a record of accepting any third-party terms. Gated model access and
/// acceptance on Hugging Face remain actions the user must complete directly with those services.
public final class ModelLicenseAcknowledgement {
  public static let stableAudioTermsAcknowledgementText =
    "Я сам(а) открыл(а) и прочитал(а) официальные условия Stable Audio и страницу модели. "
    + "Это не означает, что Flowtone принимает условия или получает доступ к весам от моего имени."

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
