import Combine
import FlowtoneCore
import Foundation

@MainActor
final class FlowtoneAppModel: ObservableObject {
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
  @Published var selectedModelTier: ModelTier {
    didSet {
      generationRuntimeReady = false
      modelRuntimeStatusText = "Переключаю локальный движок…"
      Task { await configureGenerationRuntime() }
    }
  }
  @Published var volume = 0.72 {
    didSet { playbackController.setVolume(Float(volume)) }
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
  @Published private(set) var generationRuntimeReady = false
  @Published private(set) var modelRuntimeStatusText = "Проверяю локальную модель…"
  @Published private(set) var hasAcknowledgedStableAudioTerms = false
  @Published private(set) var isUsingDevelopmentAudio = false

  let hardware = HardwareProfile.current
  let hardwareSupport: HardwareSupport

  private static let storageLimitKey = "Flowtone.storageLimitGiB"
  private static let requestedCrossfadeSeconds: TimeInterval = 6
  #if DEBUG
    private static let developmentAudioEnabled = true
  #else
    private static let developmentAudioEnabled = false
  #endif

  private let library: TrackLibrary
  private let scheduler: GenerationScheduler
  private let modelCatalog = ModelRuntimeCatalog()
  private let licenseAcknowledgement: ModelLicenseAcknowledgement
  private let crossfade = EqualPowerCrossfade()
  private var playbackQueue = RadioPlaybackQueue()
  private var isPreparingNext = false
  private var generationCursor = 0

  private lazy var playbackController: AudioPlaybackController = {
    let curve = EqualPowerCrossfade()
    return AudioPlaybackController(
      backend: AVAudioEnginePlaybackBackend(),
      gainProvider: { progress in
        let gains = curve.gains(for: progress)
        return (Float(gains.outgoing), Float(gains.incoming))
      },
      onTransition: { [weak self] outgoingID, incomingID in
        Task { @MainActor [weak self] in
          await self?.didTransition(from: outgoingID, to: incomingID)
        }
      },
      onNextNeeded: { [weak self] currentID in
        Task { @MainActor [weak self] in
          await self?.prepareNextPlaybackItem(for: currentID)
        }
      }
    )
  }()

  init() {
    let support = ModelRecommender().recommendation(for: .current)
    hardwareSupport = support
    selectedModelTier = {
      if case .supported(let recommended, _) = support { return recommended }
      return .light
    }()
    let savedStorageLimit = UserDefaults.standard.object(forKey: Self.storageLimitKey) as? Int
    storageLimitGiB = max(1, savedStorageLimit ?? 5)
    licenseAcknowledgement = ModelLicenseAcknowledgement()
    hasAcknowledgedStableAudioTerms = licenseAcknowledgement.hasAcknowledgedStableAudioTerms
    library = TrackLibrary(rootDirectory: Self.libraryRootDirectory)
    scheduler = GenerationScheduler(engine: SyntheticAudioEngine())
    Task {
      await configureGenerationRuntime()
      await bootstrapLibrary()
    }
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

  var canGenerateTrack: Bool { generationEnabled && generationRuntimeReady }

  var stableAudioRuntimePath: String { modelCatalog.stableAudioRuntimePath }

  var stableAudioRuntimeIsExecutable: Bool { modelCatalog.hasStableAudioExecutable }

  var stableAudioTermsAcknowledgementText: String {
    ModelLicenseAcknowledgement.stableAudioTermsAcknowledgementText
  }

  var generationActionTitle: String {
    isUsingDevelopmentAudio
      ? (currentTrack == nil ? "Создать тестовую" : "Создать тестовую ещё")
      : (currentTrack == nil ? "Создать первую" : "Создать ещё")
  }

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
    if playbackController.currentID != nil {
      if playbackController.isPlaying {
        playbackController.pause()
        isPlaying = false
        statusText = "Пауза"
      } else {
        do {
          try playbackController.play()
          isPlaying = true
          statusText = "Станция в эфире"
        } catch {
          statusText = error.localizedDescription
        }
      }
    } else {
      Task { await startStation() }
    }
  }

  func generateDevelopmentPreview() async {
    await generateTrack(playWhenReady: currentTrackID == nil)
  }

  func acknowledgeStableAudioTermsRead() {
    licenseAcknowledgement.acknowledgeStableAudioTerms()
    hasAcknowledgedStableAudioTerms = true
    Task { await configureGenerationRuntime() }
  }

  func refreshGenerationRuntime() {
    Task { await configureGenerationRuntime() }
  }

  func skipTrack() {
    Task {
      await prepareNextPlaybackItem(for: currentTrackID)
      do {
        try playbackController.skip()
      } catch {
        statusText = error.localizedDescription
      }
    }
  }

  func updatePlayback() {
    playbackController.update()
    isPlaying = playbackController.isPlaying
  }

  func isTrackProtected(_ trackID: UUID) -> Bool {
    playbackQueue.protectedTrackIDs.contains(trackID)
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
        guard !playbackQueue.protectedTrackIDs.contains(trackID) else {
          statusText = "Текущая или подготовленная запись должна доиграть"
          return
        }
        _ = try await library.removeTrack(trackID: trackID)
        try await refreshLibrary()
        statusText = "Запись удалена"
      } catch {
        statusText = error.localizedDescription
      }
    }
  }

  func removeAllUnliked() {
    Task {
      do {
        let report = try await library.removeAllUnliked(
          protectedTrackIDs: playbackQueue.protectedTrackIDs)
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

  private func bootstrapLibrary() async {
    do {
      _ = try await library.load()
      try await refreshLibrary()
      isLibraryLoading = false
      if let track = try await library.randomCompatibleTrack(genres: selectedGenres) {
        try await play(track)
        statusText = "Станция запущена из локальной коллекции"
        if canGenerateTrack { Task { await generateTrack(playWhenReady: false) } }
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
        if canGenerateTrack { Task { await generateTrack(playWhenReady: false) } }
      } else if canGenerateTrack {
        await generateTrack(playWhenReady: true)
      } else {
        statusText =
          generationEnabled ? modelRuntimeStatusText : "Коллекция пуста, а генерация выключена"
      }
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func generateTrack(playWhenReady: Bool) async {
    guard canGenerateTrack, !isGenerating else {
      if generationEnabled, !generationRuntimeReady { statusText = modelRuntimeStatusText }
      return
    }
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
        durationSeconds: 120,
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
        if playbackQueue.readyTrackIDs.count == 2,
          let replaceableID = playbackQueue.readyTrackIDs.last
        {
          _ = playbackQueue.remove(replaceableID)
        }
        _ = playbackQueue.enqueue(track.id)
        await prepareNextPlaybackItem(for: currentTrackID)
        statusText = "Новая запись готова и добавлена в очередь"
      }
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func play(_ track: TrackRecord) async throws {
    playbackQueue = RadioPlaybackQueue(currentTrackID: track.id)
    try await fillPlaybackQueue()

    let currentItem = try await playbackItem(for: track.id)
    let nextID = playbackQueue.readyTrackIDs.first
    let nextItem: AudioPlaybackItem?
    if let nextID {
      nextItem = try await playbackItem(for: nextID)
    } else {
      nextItem = nil
    }
    let nextDuration = nextID.flatMap(trackRecord(for:))?.durationSeconds ?? track.durationSeconds
    let duration = crossfade.effectiveDuration(
      requested: Self.requestedCrossfadeSeconds,
      currentDuration: TimeInterval(track.durationSeconds),
      nextDuration: TimeInterval(nextDuration)
    )

    try playbackController.load(
      current: currentItem,
      next: nextItem,
      crossfadeDuration: duration
    )
    playbackController.setVolume(Float(volume))
    try playbackController.play()
    currentTrackID = track.id
    isPlaying = true
    _ = try await library.markPlayed(trackID: track.id)
    try await refreshLibrary()
    statusText = "Станция в эфире"
  }

  private func didTransition(from outgoingID: UUID, to incomingID: UUID) async {
    if playbackQueue.currentTrackID == outgoingID,
      playbackQueue.readyTrackIDs.first == incomingID
    {
      _ = playbackQueue.advance()
    } else {
      playbackQueue = RadioPlaybackQueue(currentTrackID: incomingID)
    }

    currentTrackID = incomingID
    isPlaying = playbackController.isPlaying
    do {
      _ = try await library.markPlayed(trackID: incomingID)
      try await refreshLibrary()
      try await fillPlaybackQueue()
      await prepareNextPlaybackItem(for: incomingID)
      statusText = "Плавный переход · станция в эфире"
      if canGenerateTrack, !isGenerating {
        Task { await generateTrack(playWhenReady: false) }
      }
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func prepareNextPlaybackItem(for requestedCurrentID: UUID?) async {
    guard !isPreparingNext,
      let requestedCurrentID,
      requestedCurrentID == currentTrackID,
      requestedCurrentID == playbackController.currentID,
      playbackController.queuedID == nil
    else { return }

    isPreparingNext = true
    defer { isPreparingNext = false }
    do {
      try await fillPlaybackQueue()
      let nextID = playbackQueue.readyTrackIDs.first ?? requestedCurrentID
      let nextItem = try await playbackItem(for: nextID)
      let currentDuration = trackRecord(for: requestedCurrentID)?.durationSeconds ?? 120
      let nextDuration = trackRecord(for: nextID)?.durationSeconds ?? currentDuration
      let duration = crossfade.effectiveDuration(
        requested: Self.requestedCrossfadeSeconds,
        currentDuration: TimeInterval(currentDuration),
        nextDuration: TimeInterval(nextDuration)
      )
      try playbackController.setCrossfadeDuration(duration)
      try playbackController.replaceNext(with: nextItem)
    } catch {
      statusText = "Не удалось подготовить следующую запись: \(error.localizedDescription)"
    }
  }

  private func fillPlaybackQueue() async throws {
    while playbackQueue.needsPrefill {
      let excluded = playbackQueue.protectedTrackIDs
      var candidate = try await library.leastRecentlyPlayedTrack(
        genres: selectedGenres,
        excluding: excluded
      )
      if candidate == nil {
        candidate = try await library.leastRecentlyPlayedTrack(genres: [], excluding: excluded)
      }
      guard let candidate, playbackQueue.enqueue(candidate.id) else { break }
    }
  }

  private func playbackItem(for trackID: UUID) async throws -> AudioPlaybackItem {
    AudioPlaybackItem(id: trackID, fileURL: try await library.audioURL(for: trackID))
  }

  private func trackRecord(for trackID: UUID) -> TrackRecord? {
    tracks.first(where: { $0.id == trackID })
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
    let protectedIDs = playbackQueue.protectedTrackIDs.union(additionalIDs)
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

  private func configureGenerationRuntime() async {
    let requestedTier = selectedModelTier
    isUsingDevelopmentAudio = false

    guard requestedTier == .light else {
      generationRuntimeReady = false
      if case .unsupported(let reason) = modelCatalog.availability(for: requestedTier) {
        modelRuntimeStatusText = reason
      }
      return
    }

    guard hasAcknowledgedStableAudioTerms else {
      await configureUnavailableStableAudioRuntime(
        reason: "Нужно подтвердить, что вы сами прочитали официальные условия и страницу модели.")
      return
    }

    switch modelCatalog.availability(for: requestedTier) {
    case .available:
      guard let engine = modelCatalog.stableAudioEngine() else {
        generationRuntimeReady = false
        modelRuntimeStatusText = "Локальный движок Stable Audio не удалось открыть"
        return
      }
      await scheduler.replaceEngine(engine)
      guard selectedModelTier == requestedTier else { return }
      generationRuntimeReady = true
      modelRuntimeStatusText = "Stable Audio 3 Small готова · генерация на этом Mac"
    case .unavailable(let reason):
      await configureUnavailableStableAudioRuntime(reason: reason)
    case .unsupported(let reason):
      generationRuntimeReady = false
      modelRuntimeStatusText = reason
    }
  }

  private func configureUnavailableStableAudioRuntime(reason: String) async {
    if Self.developmentAudioEnabled {
      await scheduler.replaceEngine(SyntheticAudioEngine())
      guard selectedModelTier == .light else { return }
      isUsingDevelopmentAudio = true
      generationRuntimeReady = true
      modelRuntimeStatusText = "Режим разработки: синтетический звук, не Stable Audio. \(reason)"
    } else {
      generationRuntimeReady = false
      modelRuntimeStatusText = reason
    }
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
