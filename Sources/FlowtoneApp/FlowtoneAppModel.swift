import AVFoundation
import Combine
import FlowtoneCore
import Foundation

@MainActor
final class FlowtoneAppModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
  static let availableGenres = [
    "Ambient", "Lo-fi", "Light Rave", "Fantasy", "Rock", "Metal", "Thrash Metal", "Cute",
    "Chaos", "Electronic", "Synthwave", "House", "Techno", "Drum and Bass", "Hip-hop", "Funk",
    "Jazz", "Classical", "Post-rock", "Cinematic",
  ]
  static let genreLabels = [
    "Ambient": "Эмбиент", "Lo-fi": "Лоу-фай", "Classical": "Классика",
    "Jazz": "Джаз", "Electronic": "Электроника", "Post-rock": "Пост-рок",
    "Light Rave": "Лёгкий рейв", "Fantasy": "Фэнтези", "Rock": "Рок", "Metal": "Метал",
    "Thrash Metal": "Трэш-метал", "Cute": "Милая музыка", "Chaos": "Хаос",
    "Synthwave": "Синтвейв", "House": "Хаус", "Techno": "Техно",
    "Drum and Bass": "Драм-н-бэйс", "Hip-hop": "Хип-хоп", "Funk": "Фанк",
    "Cinematic": "Кинематографичная",
  ]

  @Published var selectedGenres: Set<String> = ["Ambient", "Lo-fi"]
  @Published var energy: EnergyLevel = .calm
  @Published var tempoBPM = 82.0
  @Published var mood: StationMood = .focused
  @Published var vibe = ""
  @Published var generationEnabled = true {
    didSet {
      Task { await scheduler.setGenerationEnabled(generationEnabled) }
      if !generationEnabled {
        statusText = "Генерация выключена · станция играет коллекцию"
      }
    }
  }
  @Published var selectedModelTier: ModelTier
  @Published var volume = 0.72 {
    didSet { audioPlayer?.volume = Float(volume) }
  }
  @Published var storageLimitGiB: Int {
    didSet { UserDefaults.standard.set(storageLimitGiB, forKey: Self.storageLimitKey) }
  }
  @Published var isLibraryPresented = false
  @Published private(set) var tracks: [TrackRecord] = []
  @Published private(set) var libraryStatistics = LibraryStatistics.empty
  @Published private(set) var currentTrackID: UUID?
  @Published private(set) var statusText = "Загружаю локальную коллекцию…"
  @Published private(set) var isGenerating = false
  @Published private(set) var isPlaying = false
  @Published private(set) var isLibraryLoading = true

  let hardware = HardwareProfile.current
  let hardwareSupport: HardwareSupport

  private static let storageLimitKey = "Flowtone.storageLimitGiB"
  private let library: TrackLibrary
  private let scheduler: GenerationScheduler
  private var audioPlayer: AVAudioPlayer?
  private var generationCursor = 0

  override init() {
    let support = ModelRecommender().recommendation(for: .current)
    hardwareSupport = support
    selectedModelTier = {
      if case .supported(let recommended, _) = support { return recommended }
      return .light
    }()
    let savedStorageLimit = UserDefaults.standard.object(forKey: Self.storageLimitKey) as? Int
    storageLimitGiB = max(1, savedStorageLimit ?? 5)
    library = TrackLibrary(rootDirectory: Self.libraryRootDirectory)
    scheduler = GenerationScheduler(engine: SyntheticAudioEngine())
    super.init()
    Task { await bootstrapLibrary() }
  }

  var recommendedModelText: String {
    switch hardwareSupport {
    case .unsupported:
      return hardware.isAppleSilicon
        ? "Нужно не менее 8 ГБ объединённой памяти"
        : "Нужен Mac с Apple Silicon"
    case .supported(let recommended, let warning):
      let name = modelName(for: recommended)
      return warning == nil ? name : "\(name) · тестовый режим"
    }
  }

  var selectedModelText: String { modelName(for: selectedModelTier) }

  var selectedModelWarning: String? {
    guard selectedModelTier == .quality, hardware.memoryGiB < 24 else { return nil }
    return "На этом Mac тяжёлая модель может сильно нагружать систему."
  }

  var primaryGenre: String {
    Self.availableGenres.first(where: selectedGenres.contains) ?? "Ambient"
  }

  var primaryGenreDisplayName: String { Self.genreLabels[primaryGenre] ?? primaryGenre }

  var currentTrack: TrackRecord? {
    guard let currentTrackID else { return nil }
    return tracks.first(where: { $0.id == currentTrackID })
  }

  var currentGenreDisplayName: String {
    guard let genre = currentTrack?.genres.first else { return primaryGenreDisplayName }
    return Self.genreLabels[genre] ?? genre
  }

  var currentTrackTitle: String {
    guard let currentTrack else { return "Тишина перед эфиром" }
    return currentTrack.title
  }

  var isCurrentTrackLiked: Bool { currentTrack?.isLiked ?? false }

  var librarySummaryText: String {
    "\(libraryStatistics.trackCount) треков · \(Self.formatBytes(libraryStatistics.byteSize))"
  }

  func genreDisplayName(_ genre: String) -> String { Self.genreLabels[genre] ?? genre }
  func formatBytes(_ bytes: Int64) -> String { Self.formatBytes(bytes) }

  func toggleGenre(_ genre: String) {
    if selectedGenres.contains(genre) {
      guard selectedGenres.count > 1 else { return }
      selectedGenres.remove(genre)
    } else {
      selectedGenres.insert(genre)
    }
  }

  func togglePlayback() {
    if let audioPlayer {
      if audioPlayer.isPlaying {
        audioPlayer.pause()
        isPlaying = false
        statusText = "Пауза"
      } else {
        audioPlayer.play()
        isPlaying = true
        statusText = "Станция в эфире"
      }
    } else {
      Task { await startStation() }
    }
  }

  func generateDevelopmentPreview() async {
    await generateTrack(playWhenReady: currentTrackID == nil)
  }

  func skipTrack() {
    Task { await advanceStation(forceNewTrack: true) }
  }

  func toggleCurrentLike() {
    guard let currentTrack else { return }
    Task { await setLiked(!currentTrack.isLiked, trackID: currentTrack.id) }
  }

  func toggleLike(trackID: UUID) {
    guard let track = tracks.first(where: { $0.id == trackID }) else { return }
    Task { await setLiked(!track.isLiked, trackID: trackID) }
  }

  func deleteTrack(trackID: UUID) {
    Task {
      do {
        let wasCurrent = currentTrackID == trackID
        if wasCurrent {
          audioPlayer?.stop()
          audioPlayer = nil
          currentTrackID = nil
          isPlaying = false
        }
        _ = try await library.removeTrack(trackID: trackID)
        try await refreshLibrary()
        statusText = "Запись удалена"
        if wasCurrent { await advanceStation(forceNewTrack: false) }
      } catch {
        statusText = error.localizedDescription
      }
    }
  }

  func removeAllUnliked() {
    Task {
      do {
        let protectedIDs = currentTrackID.map { Set([$0]) } ?? []
        let report = try await library.removeAllUnliked(protectedTrackIDs: protectedIDs)
        try await refreshLibrary()
        statusText =
          report.removedTrackCount == 0
          ? "Нет записей для очистки"
          : "Удалено записей: \(report.removedTrackCount)"
      } catch {
        statusText = error.localizedDescription
      }
    }
  }

  func applyStorageLimit() {
    Task {
      do {
        try await enforceStorageLimit()
        try await refreshLibrary()
      } catch {
        statusText = error.localizedDescription
      }
    }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      isPlaying = false
      if flag {
        await advanceStation(forceNewTrack: false)
      } else {
        statusText = "Не удалось завершить воспроизведение"
      }
    }
  }

  private func bootstrapLibrary() async {
    do {
      _ = try await library.load()
      try await refreshLibrary()
      isLibraryLoading = false
      if let track = try await library.randomCompatibleTrack(genres: selectedGenres) {
        try await play(track)
        statusText = "Станция запущена из локальной коллекции"
      } else {
        statusText = "Коллекция пуста · создайте первую запись"
      }
    } catch {
      isLibraryLoading = false
      statusText = error.localizedDescription
    }
  }

  private func startStation() async {
    do {
      if let track = try await library.randomCompatibleTrack(genres: selectedGenres) {
        try await play(track)
      } else if generationEnabled {
        await generateTrack(playWhenReady: true)
      } else {
        statusText = "Коллекция пуста, а генерация выключена"
      }
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func generateTrack(playWhenReady: Bool) async {
    guard generationEnabled, !isGenerating else { return }
    isGenerating = true
    statusText = "Создаю новую локальную запись…"
    defer { isGenerating = false }

    do {
      let genre = nextGenerationGenre()
      let configuration = StationConfiguration(
        genres: [genre], energy: energy, tempoBPM: Int(tempoBPM.rounded()), mood: mood, vibe: vibe
      )
      let outputDirectory = await library.incomingDirectory
      let audio = try await scheduler.generateNext(
        configuration: configuration,
        durationSeconds: 8,
        seed: UInt64.random(in: 1...UInt64.max),
        outputDirectory: outputDirectory,
        resources: .current
      )
      guard let audio else {
        statusText = "Генерация отложена · продолжаю играть коллекцию"
        return
      }

      let track = try await library.importGeneratedAudio(audio, configuration: configuration)
      try await enforceStorageLimit(protecting: [track.id])
      try await refreshLibrary()
      if playWhenReady || currentTrackID == nil {
        try await play(track)
      } else {
        statusText = "Новая запись добавлена в коллекцию"
      }
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func advanceStation(forceNewTrack: Bool) async {
    audioPlayer?.stop()
    isPlaying = false
    do {
      let excluded = currentTrackID.map { Set([$0]) } ?? []
      var next = try await library.leastRecentlyPlayedTrack(
        genres: selectedGenres, excluding: excluded)
      if next == nil, !forceNewTrack {
        next = try await library.leastRecentlyPlayedTrack(genres: selectedGenres)
      }
      if next == nil { next = try await library.leastRecentlyPlayedTrack(genres: []) }

      if let next {
        try await play(next)
        if generationEnabled, !isGenerating {
          Task { await generateTrack(playWhenReady: false) }
        }
      } else if generationEnabled {
        await generateTrack(playWhenReady: true)
      } else {
        audioPlayer = nil
        currentTrackID = nil
        statusText = "В коллекции нет других записей"
      }
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func play(_ track: TrackRecord) async throws {
    let url = try await library.audioURL(for: track.id)
    let player = try AVAudioPlayer(contentsOf: url)
    player.delegate = self
    player.volume = Float(volume)
    player.prepareToPlay()
    player.play()
    audioPlayer = player
    currentTrackID = track.id
    isPlaying = true
    _ = try await library.markPlayed(trackID: track.id)
    try await refreshLibrary()
    statusText = "Станция в эфире"
  }

  private func setLiked(_ liked: Bool, trackID: UUID) async {
    do {
      _ = try await library.setLiked(liked, trackID: trackID)
      try await refreshLibrary()
      statusText = liked ? "Запись сохранена в любимых" : "Запись убрана из любимых"
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func refreshLibrary() async throws {
    tracks = try await library.allTracks()
    libraryStatistics = try await library.statistics()
  }

  private func enforceStorageLimit(protecting additionalIDs: Set<UUID> = []) async throws {
    var protectedIDs = additionalIDs
    if let currentTrackID { protectedIDs.insert(currentTrackID) }
    let report = try await library.enforceStorageLimit(
      bytes: Int64(storageLimitGiB) * 1_073_741_824,
      protectedTrackIDs: protectedIDs
    )
    if report.limitStillExceeded {
      statusText = "Лайкнутые записи превышают лимит и не будут удалены"
    }
  }

  private func nextGenerationGenre() -> String {
    let genres = Self.availableGenres.filter(selectedGenres.contains)
    guard !genres.isEmpty else { return "Ambient" }
    let genre = genres[generationCursor % genres.count]
    generationCursor = (generationCursor + 1) % genres.count
    return genre
  }

  private func modelName(for tier: ModelTier) -> String {
    tier == .quality ? "Качество · ACE-Step" : "Лёгкая · Stable Audio 3 Small"
  }

  private static var libraryRootDirectory: URL {
    URL.applicationSupportDirectory
      .appendingPathComponent("Flowtone", isDirectory: true)
      .appendingPathComponent("Library", isDirectory: true)
  }

  private static func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
