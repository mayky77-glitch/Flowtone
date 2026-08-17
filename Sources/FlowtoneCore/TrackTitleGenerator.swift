import Foundation

/// Creates lightweight, deterministic Russian track names without another model invocation.
public struct TrackTitleGenerator: Sendable {
  public init() {}

  public func title(for configuration: StationConfiguration, seed: UInt64) -> String {
    let genres = configuration.genres.isEmpty ? ["Ambient"] : configuration.genres
    let genre = genres[Int(seed % UInt64(genres.count))]
    let candidates = Self.genreTitles[genre] ?? Self.genreTitles["Ambient"]!
    let energyOffset: Int =
      switch configuration.energy {
      case .calm: 0
      case .balanced: 1
      case .driving: 2
      }
    let vibe = configuration.vibe?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let semanticOffset = Self.stableTextHash(
      "\(genres.joined(separator: "|"))|\(configuration.mood.rawValue)|\(vibe)"
    )
    let tempoOffset = UInt64(max(configuration.tempoBPM, 0) / 4)
    let index = Int(
      (seed &+ semanticOffset &+ tempoOffset &+ UInt64(energyOffset))
        % UInt64(candidates.count)
    )
    let base = candidates[index]

    let atmosphereCandidates =
      Self.vibePhrases(for: vibe)
      ?? Self.stationPhrases(energy: configuration.energy, mood: configuration.mood)
    let atmosphereIndex = Int(
      Self.stableTextHash("\(seed)|\(semanticOffset)|atmosphere")
        % UInt64(atmosphereCandidates.count)
    )
    let atmospherePhrase = atmosphereCandidates[atmosphereIndex]

    return Self.limitedToTenWords(
      [base, atmospherePhrase]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    )
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

  /// Repairs names created by the old implementation or exceeding the current ten-word contract.
  public static func normalizedExistingTitle(_ title: String, genres: [String], seed: UInt64)
    -> String
  {
    let lastWord = title.split(separator: " ").last?.lowercased() ?? ""
    let danglingWords: Set<String> = [
      "в", "во", "на", "по", "из", "для", "с", "со", "к", "о", "об", "под", "над",
    ]
    let literalFragments = [
      "на точном разгоне", "мягкий строб", "неоновый разгон", "рассветный рейв",
      "бетонный пульс", "туннель 4/4", "сдвиг ритма", "солнечный грув",
    ]
    guard
      title.contains("·")
        || literalFragments.contains(where: title.localizedCaseInsensitiveContains)
        || title.split(whereSeparator: \.isWhitespace).count > 10
        || danglingWords.contains(lastWord) || hasRepeatedContentStem(title)
    else { return title }
    return legacyTitle(genres: genres, seed: seed)
  }

  private static func limitedToTenWords(_ title: String) -> String {
    let words = title.split(whereSeparator: \.isWhitespace).map(String.init)
    guard words.count > 10 else { return words.joined(separator: " ") }

    let danglingWords: Set<String> = [
      "в", "во", "на", "по", "из", "для", "с", "со", "к", "о", "об", "под", "над",
    ]
    var limited = Array(words.prefix(10))
    if let last = limited.last?.lowercased(), danglingWords.contains(last) {
      limited.removeLast()
    }
    return limited.joined(separator: " ")
  }

  private static func vibePhrases(for vibe: String) -> [String]? {
    let normalized = vibe.lowercased()
    let groups: [([String], [String])] = [
      (["дожд", "rain"], ["в зеркалах пустых улиц", "там где фонари размыты"]),
      (["ноч", "night"], ["когда окна давно погасли", "до первых птиц"]),
      (["маг", "чар", "magic"], ["за дверью без ключа", "там где сбываются старые карты"]),
      (["мор", "ocean", "sea"], ["за линией солёного ветра", "там где кончается берег"]),
      (["лес", "forest"], ["под древними кронами", "там где не бывает троп"]),
      (["косм", "space", "star"], ["за краем звёзд", "между дальними созвездиями"]),
      (["город", "неон", "city", "neon"], ["среди отражений на стекле", "выше спящих кварталов"]),
      (["тьм", "тём", "dark"], ["на обратной стороне света", "там куда не смотрит день"]),
      (["уют", "тепл", "cozy", "warm"], ["когда за окном холода", "там где всегда ждут"]),
    ]

    return groups.first(where: { keywords, _ in
      keywords.contains(where: normalized.contains)
    })?.1
  }

  private static func stableTextHash(_ text: String) -> UInt64 {
    text.utf8.reduce(1_469_598_103_934_665_603) { value, byte in
      (value ^ UInt64(byte)) &* 1_099_511_628_211
    }
  }

  private static func stationPhrases(energy: EnergyLevel, mood: StationMood) -> [String] {
    switch (energy, mood) {
    case (.calm, .focused):
      [
        "до первых лучей", "у линии воды", "перед открытым окном",
      ]
    case (.calm, .warm): ["у домашнего огня", "в мягком свете"]
    case (.calm, .dreamy): ["за серебряной дымкой", "на краю сна"]
    case (.calm, .dark): ["в глубокой тени", "под поздней луной"]
    case (.calm, .uplifting): ["к тихому рассвету", "навстречу свету"]
    case (.balanced, .focused):
      [
        "между делом и мечтой", "у открытого окна", "на полях старой карты",
      ]
    case (.balanced, .warm): ["до тёплого вечера", "в живом свете"]
    case (.balanced, .dreamy): ["над дальним берегом", "между явью и сном"]
    case (.balanced, .dark): ["после полуночи", "над тёмной водой"]
    case (.balanced, .uplifting): ["над новым рассветом", "выше облаков"]
    case (.driving, .focused):
      [
        "за линией горизонта", "где гаснут дальние огни", "до последнего поворота",
        "между башнями и небом", "по ту сторону ночи", "пока город не уснул",
      ]
    case (.driving, .warm): ["в сиянии большого города", "до жаркого рассвета"]
    case (.driving, .dreamy): ["сквозь звёздный поток", "за краем облаков"]
    case (.driving, .dark): ["сквозь ночную бурю", "на краю бездны"]
    case (.driving, .uplifting): ["на полном ходу", "навстречу новому дню"]
    }
  }

  private static func hasRepeatedContentStem(_ title: String) -> Bool {
    let stopWords: Set<String> = [
      "без", "для", "между", "над", "под", "после", "сквозь", "среди", "через",
    ]
    var seen: Set<String> = []
    for word in title.split(whereSeparator: \.isWhitespace) {
      var normalized = word.lowercased().filter(\.isLetter)
      guard normalized.count >= 4, !stopWords.contains(normalized) else { continue }
      let suffixes = [
        "ого", "ему", "ому", "ами", "ями", "ий", "ый", "ой", "ая", "яя", "ое", "ее",
        "ые", "ие", "ом", "ем", "ах", "ях", "ам", "ям", "у", "ю", "а", "я", "ы",
        "и", "е",
      ]
      if let suffix = suffixes.first(where: {
        normalized.hasSuffix($0) && normalized.count - $0.count >= 4
      }) {
        normalized.removeLast(suffix.count)
      }
      guard seen.insert(normalized).inserted else { return true }
    }
    return false
  }

  private static let genreTitles: [String: [String]] = [
    "Ambient": ["Тихий горизонт", "Воздушное течение", "Между небом и сном"],
    "Lo-fi": ["Пыль на кассете", "Поздний чай", "Окно во двор"],
    "Classical": ["Камерный свет", "После старого бала", "Тени в фойе"],
    "Jazz": ["Дымный поворот", "Синий час", "Свободный столик"],
    "Electronic": ["Город внутри схемы", "Цифровое тепло", "Контур без имени"],
    "Post-rock": ["Море антенн", "Долгий подъём", "Свет после бури"],
    "Light Rave": [
      "После последнего поезда", "Город перед рассветом", "Пока не включили свет",
    ],
    "Fantasy": [
      "Корона древних", "Зов рун", "Пламя героев", "Тёмный перевал", "Лесная легенда",
    ],
    "Dark Empire": [
      "Корона бездны", "Бал чёрного владыки", "Триумф тёмной цитадели", "Последний трон",
      "Марш великого завоевания",
    ],
    "Rock": ["Пыль на трассе", "До красной черты", "Громче ветра"],
    "Space Rock": [
      "За орбитой молчания", "Пыль на иллюминаторе", "Свет далёкой станции", "Пока Земля не взошла",
      "Четвёртая луна",
    ],
    "Pirate": [
      "За чёрным парусом", "До первой звезды", "Гавань за горизонтом", "Когда вернутся чайки",
      "Последняя бочка рома",
    ],
    "Metal": ["Стальной прилив", "Чёрное пламя", "Тяжёлая звезда"],
    "Thrash Metal": ["Точка удара", "Ржавый вихрь", "За красной чертой"],
    "Cute": ["Карамельное облако", "Маленькая радость", "Плюшевый день"],
    "Chaos": ["Сломанная орбита", "Непослушное эхо", "Всё одновременно"],
    "Synthwave": [
      "Пурпурное шоссе", "Солнце из хрома", "Ночной протокол", "Память под дождём",
      "Стеклянный архив", "Тёплый неон", "Над пустошью", "Дамба под чёрным небом",
    ],
    "House": ["Последний этаж", "Четыре окна напротив", "Крыша на рассвете"],
    "Techno": ["Глубже под городом", "Машинная память", "Туннель без конца"],
    "Hard Techno": ["Красная зона", "Двери закрываются", "До смены караула"],
    "Industrial Techno": ["После третьей смены", "Сломанный конвейер", "Холодный цех"],
    "Hardcore": ["За аварийной чертой", "Аварийный свет", "Предел прочности"],
    "Psytrance": ["Ночная спираль", "Квантовый лес", "Портал частот"],
    "Breakbeat": ["Погоня по крышам", "Сдвиг координат", "Мосты в движении"],
    "Drum and Bass": ["Быстрая река", "Ломаный свет", "Выше берегов"],
    "Cyberpunk": ["Хромовый квартал", "Город без сна", "Тёмное будущее"],
    "Hip-hop": ["Квартал после дождя", "Двор старой школы", "Тень на ступенях"],
    "Funk": ["Медный полдень", "Солнечный двор", "Костюм цвета мёда"],
    "Cinematic": ["Дальний кадр", "Перед титрами", "Большая дорога"],
  ]
}
