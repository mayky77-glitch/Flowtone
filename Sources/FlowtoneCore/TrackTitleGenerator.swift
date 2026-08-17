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
    let vibeOffset = Self.stableTextHash(configuration.vibe ?? "")
    let index = Int((seed &+ vibeOffset &+ UInt64(energyOffset)) % UInt64(candidates.count))
    let base = candidates[index]

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

  /// Repairs names created by the old implementation, which could end on a cut-off vibe phrase.
  public static func normalizedExistingTitle(_ title: String, genres: [String], seed: UInt64)
    -> String
  {
    let lastWord = title.split(separator: " ").last?.lowercased() ?? ""
    let danglingWords: Set<String> = [
      "в", "во", "на", "по", "из", "для", "с", "со", "к", "о", "об", "под", "над",
    ]
    guard title.count > 44 || danglingWords.contains(lastWord) else { return title }
    return legacyTitle(genres: genres, seed: seed)
  }

  private static func stableTextHash(_ text: String) -> UInt64 {
    text.utf8.reduce(1_469_598_103_934_665_603) { value, byte in
      (value ^ UInt64(byte)) &* 1_099_511_628_211
    }
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
    "Fantasy": [
      "Корона древних", "Зов рун", "Пламя героев", "Тёмный перевал", "Лесная легенда",
    ],
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
