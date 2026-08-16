import Foundation

/// Creates lightweight, deterministic Russian track names without another model invocation.
public struct TrackTitleGenerator: Sendable {
  public init() {}

  public func title(for configuration: StationConfiguration, seed: UInt64) -> String {
    let genre = configuration.genres.first ?? "Ambient"
    let candidates = Self.genreTitles[genre] ?? Self.genreTitles["Ambient"]!
    let energyOffset: Int =
      switch configuration.energy {
      case .calm: 0
      case .balanced: 1
      case .driving: 2
      }
    let index = Int((seed &+ UInt64(energyOffset)) % UInt64(candidates.count))
    let base = candidates[index]

    if let vibe = Self.vibeFragment(configuration.vibe) {
      return "\(base) · \(vibe)"
    }

    let moodCandidates = Self.moodTitles[configuration.mood] ?? []
    guard !moodCandidates.isEmpty else { return base }
    let moodIndex = Int((seed / 7) % UInt64(moodCandidates.count))
    return "\(base) · \(moodCandidates[moodIndex])"
  }

  public static func legacyTitle(genres: [String], seed: UInt64) -> String {
    let configuration = StationConfiguration(
      genres: genres.isEmpty ? ["Ambient"] : genres,
      energy: .balanced,
      tempoBPM: 82,
      mood: .focused
    )
    return TrackTitleGenerator().title(for: configuration, seed: seed)
  }

  private static func vibeFragment(_ vibe: String?) -> String? {
    guard let vibe else { return nil }
    let words =
      vibe
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .split(whereSeparator: { $0.isWhitespace || ",;.!?".contains($0) })
      .prefix(4)
      .map(String.init)
    guard !words.isEmpty else { return nil }
    let phrase = words.joined(separator: " ")
    return phrase.prefix(1).uppercased() + phrase.dropFirst()
  }

  private static let moodTitles: [StationMood: [String]] = [
    .focused: ["Чистая линия", "Без лишних слов", "Ровное дыхание"],
    .warm: ["Тёплый свет", "Домашний эфир", "Мягкий вечер"],
    .dreamy: ["Сон наяву", "Дальний берег", "Выше облаков"],
    .dark: ["После полуночи", "Тёмная вода", "Тихая тень"],
    .uplifting: ["Навстречу свету", "Ещё выше", "Хороший день"],
  ]

  private static let genreTitles: [String: [String]] = [
    "Ambient": ["Тихий горизонт", "Воздушное течение", "Между небом и сном"],
    "Lo-fi": ["Пыль на кассете", "Поздний чай", "Окно во двор"],
    "Classical": ["Камерный свет", "Утреннее адажио", "Тени в фойе"],
    "Jazz": ["Дымный поворот", "Синий час", "Свободный столик"],
    "Electronic": ["Импуль города", "Цифровое тепло", "Контур тока"],
    "Post-rock": ["Море антенн", "Долгий подъём", "Свет после бури"],
    "Light Rave": ["Мягкий строб", "Неоновый разгон", "Рассветный рейв"],
    "Fantasy": ["Лесная легенда", "Дорога к башне", "Серебряная карта"],
    "Rock": ["Открытая трасса", "Усилители на закате", "Громче ветра"],
    "Metal": ["Стальной прилив", "Чёрное пламя", "Тяжёлая звезда"],
    "Thrash Metal": ["Точка удара", "Ржавый вихрь", "Скорость без тормозов"],
    "Cute": ["Карамельное облако", "Маленькая радость", "Плюшевый день"],
    "Chaos": ["Сломанная орбита", "Непослушный сигнал", "Всё одновременно"],
    "Synthwave": ["Пурпурное шоссе", "Солнце из хрома", "Ночной протокол"],
    "House": ["Крыша на рассвете", "Четыре шага", "Тёплый танцпол"],
    "Techno": ["Бетонный пульс", "Машинная память", "Туннель 4/4"],
    "Drum and Bass": ["Быстрая река", "Ломаный свет", "Басовая волна"],
    "Hip-hop": ["Ритм квартала", "Виниловый шаг", "Тень на бите"],
    "Funk": ["Медный шаг", "Солнечный грув", "Карманный ритм"],
    "Cinematic": ["Дальний кадр", "Перед титрами", "Большая дорога"],
  ]
}
