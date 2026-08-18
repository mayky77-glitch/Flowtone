import Foundation

/// Stores a user's confirmation that they personally opened and read the official model terms.
///
/// This is deliberately not a record of accepting any third-party terms. Acceptance remains an
/// action the user must complete personally before Flowtone downloads the public MLX bundle.
public final class ModelLicenseAcknowledgement {
  public static let stableAudioTermsAcknowledgementText =
    "Я сам(а) открыл(а) и прочитал(а) официальные условия Stable Audio и страницу модели. "
    + "Flowtone не принимает эти условия от моего имени; после подтверждения он может скачать "
    + "официальный MLX-набор на этот Mac."

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
