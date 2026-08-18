import Foundation

public enum ModelTier: String, CaseIterable, Codable, Identifiable, Sendable {
  case light
  case quality

  public var id: Self { self }
}

public enum MusicModelID: String, CaseIterable, Codable, Identifiable, Sendable {
  case stableSmall
  case stableMedium
  case aceTurbo
  case aceLite
  case acePro
  case aceMax

  public var id: Self { self }

  public var stableAudioTier: ModelTier? {
    switch self {
    case .stableSmall: .light
    case .stableMedium: .quality
    case .aceTurbo, .aceLite, .acePro, .aceMax: nil
    }
  }
}

public enum ModelPreference: String, CaseIterable, Codable, Identifiable, Sendable {
  case automatic
  case light
  case quality
  case aceTurbo
  case aceLite
  case acePro
  case aceMax

  public var id: Self { self }

  public var requestedModelID: MusicModelID? {
    switch self {
    case .automatic: nil
    case .light: .stableSmall
    case .quality: .stableMedium
    case .aceTurbo: .aceTurbo
    case .aceLite: .aceLite
    case .acePro: .acePro
    case .aceMax: .aceMax
    }
  }

  public init(modelID: MusicModelID) {
    switch modelID {
    case .stableSmall: self = .light
    case .stableMedium: self = .quality
    case .aceTurbo: self = .aceTurbo
    case .aceLite: self = .aceLite
    case .acePro: self = .acePro
    case .aceMax: self = .aceMax
    }
  }
}

public enum HardwareModelGroup: String, CaseIterable, Identifiable, Sendable {
  case compact
  case balanced
  case powerful

  public var id: Self { self }

  public var title: String {
    switch self {
    case .compact: "КОМПАКТНЫЙ ПК"
    case .balanced: "СБАЛАНСИРОВАННЫЙ ПК"
    case .powerful: "МОЩНЫЙ ПК"
    }
  }

  public var requirement: String {
    switch self {
    case .compact: "8–15 ГБ памяти"
    case .balanced: "16–23 ГБ памяти"
    case .powerful: "24 ГБ памяти и больше"
    }
  }

  public var baselineID: MusicModelID {
    switch self {
    case .compact, .balanced: .stableSmall
    case .powerful: .stableMedium
    }
  }

  public var modelIDs: [MusicModelID] {
    switch self {
    case .compact: [.stableSmall, .aceTurbo, .aceLite]
    case .balanced: [.stableSmall, .stableMedium, .acePro]
    case .powerful: [.stableMedium, .acePro, .aceMax]
    }
  }

  public static func current(memoryGiB: Int) -> Self {
    if memoryGiB >= 24 { return .powerful }
    if memoryGiB >= 16 { return .balanced }
    return .compact
  }
}

public enum MusicModelFamily: String, Sendable {
  case stableAudio
  case aceStep
}

public struct MusicModelProfile: Equatable, Identifiable, Sendable {
  public let id: MusicModelID
  public let family: MusicModelFamily
  public let title: String
  public let shortTitle: String
  public let estimatedDownloadGiB: Double
  public let requiredFreeDiskGiB: Int
  public let minimumMemoryGiB: Int
  public let backend: String
  public let summary: String
  public let betterThanBaseline: String
  public let worseThanBaseline: String
  public let isAmbitious: Bool

  public var stableAudioTier: ModelTier? { id.stableAudioTier }

  public static let stableSmall = MusicModelProfile(
    id: .stableSmall,
    family: .stableAudio,
    title: "Stable Audio 3 Small-Music",
    shortTitle: "Small-Music",
    estimatedDownloadGiB: 1.8,
    requiredFreeDiskGiB: 4,
    minimumMemoryGiB: 8,
    backend: "MLX",
    summary: "Базовая модель для непрерывного инструментального радио.",
    betterThanBaseline: "База группы: быстрее, экономнее и предсказуемее в фоне.",
    worseThanBaseline: "Проще аранжировки и меньше музыкальной детализации.",
    isAmbitious: false
  )

  public static let stableMedium = MusicModelProfile(
    id: .stableMedium,
    family: .stableAudio,
    title: "Stable Audio 3 Medium",
    shortTitle: "Medium",
    estimatedDownloadGiB: 6.5,
    requiredFreeDiskGiB: 9,
    minimumMemoryGiB: 16,
    backend: "MLX",
    summary: "Более тяжёлая инструментальная модель с плотным и детальным звуком.",
    betterThanBaseline: "Лучше Small: богаче слои, пространство и длинное развитие.",
    worseThanBaseline: "Хуже Small: заметно медленнее и сильнее нагружает память.",
    isAmbitious: false
  )

  public static let aceTurbo = MusicModelProfile(
    id: .aceTurbo,
    family: .aceStep,
    title: "ACE-Step 1.5 Turbo · без LM",
    shortTitle: "ACE Turbo",
    estimatedDownloadGiB: 10,
    requiredFreeDiskGiB: 16,
    minimumMemoryGiB: 8,
    backend: "MLX / PyTorch",
    summary: "Амбициозная модель полных композиций; работает без языкового планировщика.",
    betterThanBaseline: "Лучше базы: длиннее музыкальная форма и смелее жанровые переходы.",
    worseThanBaseline: "Хуже базы: намного больше загрузка и медленнее первый запуск.",
    isAmbitious: true
  )

  public static let aceLite = MusicModelProfile(
    id: .aceLite,
    family: .aceStep,
    title: "ACE-Step 1.5 Turbo · LM 0,6B",
    shortTitle: "ACE 0,6B",
    estimatedDownloadGiB: 11.5,
    requiredFreeDiskGiB: 18,
    minimumMemoryGiB: 12,
    backend: "MLX / PyTorch",
    summary: "Лёгкий планировщик улучшает структуру, темп и соответствие описанию.",
    betterThanBaseline: "Лучше базы: точнее понимает идею и строит цельную композицию.",
    worseThanBaseline: "Хуже базы: тяжелее, медленнее и на 8 ГБ возможен offload.",
    isAmbitious: true
  )

  public static let acePro = MusicModelProfile(
    id: .acePro,
    family: .aceStep,
    title: "ACE-Step 1.5 Turbo · LM 1,7B",
    shortTitle: "ACE 1,7B",
    estimatedDownloadGiB: 14,
    requiredFreeDiskGiB: 21,
    minimumMemoryGiB: 16,
    backend: "MLX / PyTorch",
    summary: "Сильное музыкальное планирование, метаданные и развитие полной формы.",
    betterThanBaseline: "Лучше базы: сложнее структура, точнее промпт и выразительнее развитие.",
    worseThanBaseline: "Хуже базы: дольше генерация и выше фоновая нагрузка.",
    isAmbitious: true
  )

  public static let aceMax = MusicModelProfile(
    id: .aceMax,
    family: .aceStep,
    title: "ACE-Step 1.5 XL · LM 4B",
    shortTitle: "ACE XL 4B",
    estimatedDownloadGiB: 27,
    requiredFreeDiskGiB: 38,
    minimumMemoryGiB: 32,
    backend: "MLX / PyTorch",
    summary: "Самая амбициозная конфигурация: XL DiT и большой музыкальный планировщик.",
    betterThanBaseline: "Лучше базы: максимум структуры, деталей и следования сложной задумке.",
    worseThanBaseline: "Хуже базы: огромная модель; нужна мощная система и много времени.",
    isAmbitious: true
  )

  public static let all = [stableSmall, stableMedium, aceTurbo, aceLite, acePro, aceMax]

  public static func profile(for id: MusicModelID) -> MusicModelProfile {
    all.first(where: { $0.id == id }) ?? stableSmall
  }
}

public struct StableAudioModelProfile: Equatable, Identifiable, Sendable {
  public let tier: ModelTier
  public let title: String
  public let shortTitle: String
  public let bundleName: String
  public let decoderName: String
  public let engineID: String
  public let estimatedDownloadGiB: Double
  public let requiredFreeDiskGiB: Int
  public let minimumMemoryGiB: Int
  public let summary: String

  public var id: ModelTier { tier }

  public static let small = StableAudioModelProfile(
    tier: .light,
    title: MusicModelProfile.stableSmall.title,
    shortTitle: MusicModelProfile.stableSmall.shortTitle,
    bundleName: "sm-music",
    decoderName: "same-s",
    engineID: "stable-audio-3-small-mlx",
    estimatedDownloadGiB: MusicModelProfile.stableSmall.estimatedDownloadGiB,
    requiredFreeDiskGiB: MusicModelProfile.stableSmall.requiredFreeDiskGiB,
    minimumMemoryGiB: MusicModelProfile.stableSmall.minimumMemoryGiB,
    summary: MusicModelProfile.stableSmall.summary
  )

  public static let medium = StableAudioModelProfile(
    tier: .quality,
    title: MusicModelProfile.stableMedium.title,
    shortTitle: MusicModelProfile.stableMedium.shortTitle,
    bundleName: "medium",
    decoderName: "same-l",
    engineID: "stable-audio-3-medium-mlx",
    estimatedDownloadGiB: MusicModelProfile.stableMedium.estimatedDownloadGiB,
    requiredFreeDiskGiB: MusicModelProfile.stableMedium.requiredFreeDiskGiB,
    minimumMemoryGiB: MusicModelProfile.stableMedium.minimumMemoryGiB,
    summary: MusicModelProfile.stableMedium.summary
  )

  public static let all = [small, medium]

  public static func profile(for tier: ModelTier) -> StableAudioModelProfile {
    tier == .light ? small : medium
  }
}

public struct HardwareProfile: Equatable, Sendable {
  public let isAppleSilicon: Bool
  public let physicalMemoryBytes: UInt64

  public init(isAppleSilicon: Bool, physicalMemoryBytes: UInt64) {
    self.isAppleSilicon = isAppleSilicon
    self.physicalMemoryBytes = physicalMemoryBytes
  }

  public static var current: HardwareProfile {
    #if arch(arm64)
      let appleSilicon = true
    #else
      let appleSilicon = false
    #endif

    return HardwareProfile(
      isAppleSilicon: appleSilicon,
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
    )
  }

  public var memoryGiB: Int {
    Int((physicalMemoryBytes + (1 << 30) - 1) / (1 << 30))
  }

  public var modelGroup: HardwareModelGroup {
    HardwareModelGroup.current(memoryGiB: memoryGiB)
  }
}

public enum HardwareSupport: Equatable, Sendable {
  case unsupported(reason: String)
  case supported(recommended: ModelTier, warning: String?)
}

public struct ModelRecommender: Sendable {
  public init() {}

  public func recommendation(for hardware: HardwareProfile) -> HardwareSupport {
    guard hardware.isAppleSilicon else {
      return .unsupported(reason: "Flowtone нужен Mac с Apple Silicon.")
    }

    guard hardware.memoryGiB >= 8 else {
      return .unsupported(reason: "Лёгкой модели нужно не менее 8 ГБ объединённой памяти.")
    }

    if hardware.memoryGiB >= 24 {
      return .supported(recommended: .quality, warning: nil)
    }

    let warning =
      hardware.memoryGiB < 16
      ? "Поддержка 8 ГБ считается тестовой до бенчмарка устройства."
      : nil
    return .supported(recommended: .light, warning: warning)
  }
}
