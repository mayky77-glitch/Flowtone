import Combine
import FlowtoneCore
import Foundation

enum TrackLibraryFilter: String, CaseIterable, Identifiable {
  case all
  case liked

  var id: Self { self }

  var title: String {
    switch self {
    case .all: "Все записи"
    case .liked: "Любимые"
    }
  }
}

@MainActor
final class FlowtoneAppModel: ObservableObject {
  static let availableGenres = GenrePromptCatalog.supportedGenres
  static let genreLabels = [
    "Ambient": "Эмбиент", "Lo-fi": "Лоу-фай", "Classical": "Классика",
    "Jazz": "Джаз", "Electronic": "Электроника", "Post-rock": "Пост-рок",
    "Light Rave": "Лёгкий рейв", "Fantasy": "Фэнтези", "Rock": "Рок", "Metal": "Метал",
    "Thrash Metal": "Трэш-метал", "Cute": "Милая музыка", "Chaos": "Хаос",
    "Synthwave": "Синтвейв", "House": "Хаус", "Techno": "Техно",
    "Drum and Bass": "Драм-н-бэйс", "Hip-hop": "Хип-хоп", "Funk": "Фанк",
    "Cinematic": "Кинематографичная", "Pirate": "Пиратская",
    "Hard Techno": "Хард-техно", "Industrial Techno": "Индастриал-техно",
    "Hardcore": "Хардкор", "Psytrance": "Псайтранс", "Breakbeat": "Брейкбит",
    "Cyberpunk": "Киберпанк",
  ]

  @Published var selectedGenres: Set<String> = ["Ambient", "Lo-fi"]
  @Published var mixGenresEnabled = false
  @Published var presetEditingGenre = "Ambient"
  @Published var selectedPresetIDs: [String: String] = [:]
  @Published var energy: EnergyLevel = .calm
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
  @Published var isStorageLimitAlertPresented = false
  @Published var libraryFilter: TrackLibraryFilter = .all
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
  @Published private(set) var playbackPositionSeconds: TimeInterval = 0
  @Published private(set) var playbackDurationSeconds: TimeInterval = 0
  @Published private(set) var isScrubbing = false
  @Published private(set) var isStoragePaused = false

  let hardware = HardwareProfile.current
  let hardwareSupport: HardwareSupport

  private static let storageLimitKey = "Flowtone.storageLimitGiB"
  private static let requestedCrossfadeSeconds: TimeInterval = 6
  private static let generatedTrackDurationSeconds = 120
  private static let estimatedTrackByteSize: Int64 =
    Int64(generatedTrackDurationSeconds * 44_100 * 2 * 2 + 44)
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
  private var playbackHistory: [UUID] = []
  private var playbackHistoryIndex: Int?

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

  var canGenerateTrack: Bool { generationEnabled && generationRuntimeReady && !isStoragePaused }

  var storageLimitAlertMessage: String {
    "Коллекция занимает \(Self.formatBytes(libraryStatistics.byteSize)) из лимита \(storageLimitGiB) ГБ. Новые треки не будут записываться, пока вы не удалите часть архива или не увеличите лимит. Уже сохранённая музыка продолжит играть."
  }

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

  var primaryGenreDisplayName: String {
    if mixGenresEnabled { return "Микс жанров" }
    return selectedGenres.isEmpty ? "Все жанры" : (Self.genreLabels[primaryGenre] ?? primaryGenre)
  }

  var areAllGenresSelected: Bool { selectedGenres.count == Self.availableGenres.count }

  var canMixGenres: Bool { selectedGenres.isEmpty || selectedGenres.count >= 2 }

  var currentTrack: TrackRecord? {
    guard let currentTrackID else { return nil }
    return tracks.first(where: { $0.id == currentTrackID })
  }

  var currentGenreDisplayName: String {
    guard let genres = currentTrack?.genres, !genres.isEmpty else { return primaryGenreDisplayName }
    let labels = genres.map(genreDisplayName)
    guard labels.count > 1 else { return labels[0] }
    return "Микс · \(labels.prefix(2).joined(separator: " + "))"
  }

  var currentTrackTitle: String {
    guard let currentTrack else { return "Тишина перед эфиром" }
    return currentTrack.title
  }

  var isCurrentTrackLiked: Bool { currentTrack?.isLiked ?? false }

  var playbackProgress: Double {
    guard playbackDurationSeconds > 0 else { return 0 }
    return min(max(playbackPositionSeconds / playbackDurationSeconds, 0), 1)
  }

  var playbackTimeText: String { Self.formatTime(playbackPositionSeconds) }

  var playbackDurationText: String { Self.formatTime(playbackDurationSeconds) }

  var canGoToPreviousTrack: Bool { previousHistoryIndex != nil }

  var canGoToNextTrack: Bool {
    currentTrackID != nil || forwardHistoryIndex != nil || canGenerateTrack
  }

  var librarySummaryText: String {
    "\(libraryStatistics.trackCount) треков · \(Self.formatBytes(libraryStatistics.byteSize))"
  }

  var presetGenreChoices: [String] {
    let active = Self.availableGenres.filter(selectedGenres.contains)
    return active.isEmpty ? Self.availableGenres : active
  }

  var presetsForEditingGenre: [GenrePreset] {
    GenrePromptCatalog().presets(for: presetEditingGenre)
  }

  func genreDisplayName(_ genre: String) -> String { Self.genreLabels[genre] ?? genre }
  func formatBytes(_ bytes: Int64) -> String { Self.formatBytes(bytes) }

  func toggleGenre(_ genre: String) {
    if selectedGenres.contains(genre) {
      selectedGenres.remove(genre)
    } else {
      selectedGenres.insert(genre)
      presetEditingGenre = genre
    }
    if !selectedGenres.isEmpty, !selectedGenres.contains(presetEditingGenre) {
      presetEditingGenre =
        Self.availableGenres.first(where: selectedGenres.contains) ?? primaryGenre
    }
    if !canMixGenres { mixGenresEnabled = false }
  }

  func selectedPresetID(for genre: String) -> String {
    selectedPresetIDs[genre] ?? ""
  }

  func selectPreset(_ presetID: String, for genre: String) {
    if presetID.isEmpty {
      selectedPresetIDs.removeValue(forKey: genre)
    } else {
      selectedPresetIDs[genre] = presetID
    }
    let presetTitle = GenrePromptCatalog().presets(for: genre)
      .first(where: { $0.id == presetID })?.title
    statusText =
      presetTitle.map { "Пресет «\($0)» применится со следующего трека" }
      ?? "Пресет будет выбираться автоматически"
  }

  func toggleAllGenres() {
    if areAllGenresSelected {
      clearGenreFilters()
    } else {
      selectAllGenres()
    }
  }

  func selectAllGenres() {
    selectedGenres = Set(Self.availableGenres)
    statusText = "Все жанры активны"
  }

  func clearGenreFilters() {
    selectedGenres.removeAll()
    statusText = "Фильтры сняты · станция чередует все жанры"
  }

  func togglePlayback() {
    if playbackController.currentID != nil {
      if playbackController.isPlaying {
        playbackController.pause()
        synchronizePlaybackState()
        statusText = "Пауза"
      } else {
        do {
          try playbackController.play()
          synchronizePlaybackState()
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
    nextTrack()
  }

  func previousTrack() {
    guard let destinationIndex = previousHistoryIndex else {
      statusText = "Предыдущей записи в этой сессии нет"
      return
    }
    Task { await navigateHistory(to: destinationIndex) }
  }

  func nextTrack() {
    if let destinationIndex = forwardHistoryIndex {
      Task { await navigateHistory(to: destinationIndex) }
      return
    }

    Task {
      await prepareNextPlaybackItem(for: currentTrackID)
      do {
        try playbackController.skip()
        synchronizePlaybackState()
      } catch {
        statusText = error.localizedDescription
      }
    }
  }

  func seek(to position: TimeInterval) {
    do {
      try playbackController.seek(to: position)
      synchronizePlaybackState()
      statusText = "Позиция изменена"
    } catch {
      statusText = error.localizedDescription
    }
  }

  func seek(by offset: TimeInterval) {
    seek(to: playbackPositionSeconds + offset)
  }

  func seekToBeginning() {
    seek(to: 0)
  }

  func seekToEnd() {
    seek(to: playbackDurationSeconds)
  }

  func beginScrubbing() {
    do {
      try playbackController.beginScrubbing()
      synchronizePlaybackState()
      statusText = "Пластинка под рукой"
    } catch {
      statusText = error.localizedDescription
    }
  }

  func scrub(to position: TimeInterval, direction: AudioScrubDirection) {
    do {
      try playbackController.scrub(to: position, direction: direction)
      synchronizePlaybackState()
    } catch {
      statusText = error.localizedDescription
    }
  }

  func endScrubbing() {
    do {
      try playbackController.endScrubbing()
      synchronizePlaybackState()
      statusText = playbackController.isPlaying ? "Станция в эфире" : "Пауза"
    } catch {
      statusText = error.localizedDescription
    }
  }

  func showLibrary(filter: TrackLibraryFilter) {
    libraryFilter = filter
    isLibraryPresented = true
  }

  func playTrack(trackID: UUID) {
    guard let track = trackRecord(for: trackID) else { return }
    Task {
      do {
        try await play(track)
        isLibraryPresented = false
      } catch {
        statusText = error.localizedDescription
      }
    }
  }

  func updatePlayback() {
    playbackController.update()
    synchronizePlaybackState()
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
        try await refreshLibrary()
        if isStoragePaused { presentStorageLimitAlert() }
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
      if isStoragePaused { presentStorageLimitAlert() }
      if generationEnabled, !generationRuntimeReady { statusText = modelRuntimeStatusText }
      return
    }
    guard hasCapacityForEstimatedTrack else {
      presentStorageLimitAlert()
      return
    }
    isGenerating = true
    statusText = "Создаю новую локальную запись…"
    defer { isGenerating = false }

    do {
      let seed = UInt64.random(in: 1...UInt64.max)
      let genres = nextGenerationGenres(seed: seed)
      guard let leadGenre = genres.first else { return }
      let automaticTempo = TempoPlanner().tempo(for: leadGenre, energy: energy, seed: seed)
      let presetIDs: [String: String] = Dictionary(
        uniqueKeysWithValues: genres.compactMap { genre in
          selectedPresetIDs[genre].map { (genre, $0) }
        }
      )
      let configuration = StationConfiguration(
        genres: genres,
        energy: energy,
        tempoBPM: automaticTempo,
        mood: mood,
        vibe: vibe,
        genrePresetIDs: presetIDs
      )
      let outputDirectory = await library.incomingDirectory
      let audio = try await scheduler.generateNext(
        configuration: configuration,
        durationSeconds: Self.generatedTrackDurationSeconds,
        seed: seed,
        outputDirectory: outputDirectory,
        resources: .current
      )
      guard let audio else {
        statusText = "Генерация отложена · продолжаю играть коллекцию"
        return
      }

      guard
        StorageCapacityPolicy().canStore(
          currentBytes: libraryStatistics.byteSize,
          incomingBytes: audio.byteSize,
          limitBytes: storageLimitBytes
        )
      else {
        try? FileManager.default.removeItem(at: audio.fileURL)
        presentStorageLimitAlert()
        return
      }

      let track = try await library.importGeneratedAudio(audio, configuration: configuration)
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

  private func play(_ track: TrackRecord, historyDestination: Int? = nil) async throws {
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
    if let historyDestination {
      playbackHistoryIndex = historyDestination
    } else {
      recordHistory(track.id)
    }
    synchronizePlaybackState()
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
    recordHistory(incomingID)
    synchronizePlaybackState()
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

  private var previousHistoryIndex: Int? {
    guard let playbackHistoryIndex, playbackHistoryIndex > 0 else { return nil }
    for index in stride(from: playbackHistoryIndex - 1, through: 0, by: -1) {
      if trackRecord(for: playbackHistory[index]) != nil { return index }
    }
    return nil
  }

  private var forwardHistoryIndex: Int? {
    guard let playbackHistoryIndex, playbackHistoryIndex + 1 < playbackHistory.count else {
      return nil
    }
    for index in (playbackHistoryIndex + 1)..<playbackHistory.count {
      if trackRecord(for: playbackHistory[index]) != nil { return index }
    }
    return nil
  }

  private func navigateHistory(to index: Int) async {
    guard playbackHistory.indices.contains(index),
      let track = trackRecord(for: playbackHistory[index])
    else { return }
    do {
      try await play(track, historyDestination: index)
      statusText = "Запись из истории сессии"
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func recordHistory(_ trackID: UUID) {
    if let playbackHistoryIndex,
      playbackHistory.indices.contains(playbackHistoryIndex),
      playbackHistory[playbackHistoryIndex] == trackID
    {
      return
    }

    if let playbackHistoryIndex, playbackHistoryIndex + 1 < playbackHistory.count {
      playbackHistory.removeSubrange((playbackHistoryIndex + 1)..<playbackHistory.count)
    }
    playbackHistory.append(trackID)
    playbackHistoryIndex = playbackHistory.count - 1
  }

  private func synchronizePlaybackState() {
    isPlaying = playbackController.isPlaying
    isScrubbing = playbackController.isScrubbing
    playbackPositionSeconds = playbackController.position
    playbackDurationSeconds = playbackController.duration
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
    let wasStoragePaused = isStoragePaused
    isStoragePaused = !hasCapacityForEstimatedTrack
    if isStoragePaused, !wasStoragePaused {
      presentStorageLimitAlert()
    }
  }

  private var storageLimitBytes: Int64 {
    Int64(storageLimitGiB) * 1_073_741_824
  }

  private var hasCapacityForEstimatedTrack: Bool {
    StorageCapacityPolicy().canStore(
      currentBytes: libraryStatistics.byteSize,
      incomingBytes: Self.estimatedTrackByteSize,
      limitBytes: storageLimitBytes
    )
  }

  private func presentStorageLimitAlert() {
    isStoragePaused = true
    isStorageLimitAlertPresented = true
    statusText = "Хранилище заполнено · генерация новых записей приостановлена"
  }

  private func nextGenerationGenre() -> String {
    let filteredGenres = Self.availableGenres.filter(selectedGenres.contains)
    let genres = filteredGenres.isEmpty ? Self.availableGenres : filteredGenres
    let genre = genres[generationCursor % genres.count]
    generationCursor = (generationCursor + 1) % genres.count
    return genre
  }

  private func nextGenerationGenres(seed: UInt64) -> [String] {
    guard mixGenresEnabled else { return [nextGenerationGenre()] }
    let filteredGenres = Self.availableGenres.filter(selectedGenres.contains)
    let genres = filteredGenres.isEmpty ? Self.availableGenres : filteredGenres
    return GenreMixPlanner().mix(from: genres, seed: seed)
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

  private static func formatTime(_ seconds: TimeInterval) -> String {
    let safeSeconds = max(0, seconds.isFinite ? Int(seconds.rounded(.down)) : 0)
    return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
  }
}
