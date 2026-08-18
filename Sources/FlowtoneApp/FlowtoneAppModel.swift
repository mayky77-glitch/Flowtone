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

enum RadioStorageMode: String, CaseIterable, Identifiable {
  case live
  case recording

  var id: Self { self }

  var title: String {
    switch self {
    case .live: "Полное радио"
    case .recording: "Радио с записью"
    }
  }

  var explanation: String {
    switch self {
    case .live:
      "Новые треки временные. Flowtone хранит текущий, предыдущий и очередь; лайк защищает трек."
    case .recording:
      "Каждый новый трек остаётся в локальной коллекции до ручной очистки."
    }
  }
}

@MainActor
final class FlowtoneAppModel: ObservableObject {
  static let availableGenres = GenrePromptCatalog.supportedGenres
  static let genreLabels = [
    "Ambient": "Эмбиент", "Lo-fi": "Лоу-фай", "Classical": "Классика",
    "Jazz": "Джаз", "Electronic": "Электроника", "Post-rock": "Пост-рок",
    "Light Rave": "Лёгкий рейв", "Fantasy": "Фэнтези", "Dark Empire": "Тёмная империя",
    "Rock": "Рок", "Space Rock": "Космо-рок", "Metal": "Метал",
    "Thrash Metal": "Трэш-метал", "Cute": "Милая музыка", "Chaos": "Хаос",
    "Synthwave": "Синтвейв", "House": "Хаус", "Techno": "Техно",
    "Drum and Bass": "Драм-н-бэйс", "Hip-hop": "Хип-хоп", "Funk": "Фанк",
    "Cinematic": "Кинематографичная", "Pirate": "Пиратская",
    "Hard Techno": "Хард-техно", "Industrial Techno": "Индастриал-техно",
    "Hardcore": "Хардкор", "Psytrance": "Псайтранс", "Breakbeat": "Брейкбит",
    "Cyberpunk": "Киберпанк",
  ]

  @Published var selectedGenres: Set<String> = ["Ambient", "Lo-fi"] {
    didSet {
      UserDefaults.standard.set(selectedGenres.sorted(), forKey: Self.selectedGenresKey)
    }
  }
  @Published var mixGenresEnabled = false {
    didSet { UserDefaults.standard.set(mixGenresEnabled, forKey: Self.mixGenresKey) }
  }
  @Published var storageMode: RadioStorageMode {
    didSet {
      UserDefaults.standard.set(storageMode.rawValue, forKey: Self.storageModeKey)
      if storageMode == .live { Task { await pruneTransientTracks() } }
    }
  }
  @Published var shuffleEnabled: Bool {
    didSet { UserDefaults.standard.set(shuffleEnabled, forKey: Self.shuffleKey) }
  }
  @Published var energy: EnergyLevel = .calm {
    didSet { UserDefaults.standard.set(energy.rawValue, forKey: Self.energyKey) }
  }
  @Published var mood: StationMood = .focused {
    didSet { UserDefaults.standard.set(mood.rawValue, forKey: Self.moodKey) }
  }
  @Published var vibe = "" {
    didSet { UserDefaults.standard.set(String(vibe.prefix(180)), forKey: Self.vibeKey) }
  }
  @Published var generationEnabled = true {
    didSet {
      UserDefaults.standard.set(generationEnabled, forKey: Self.generationEnabledKey)
      Task { await scheduler.setGenerationEnabled(generationEnabled) }
      if !generationEnabled {
        statusText = "Генерация выключена · станция играет коллекцию"
      }
    }
  }
  @Published var modelPreference: ModelPreference {
    didSet {
      UserDefaults.standard.set(modelPreference.rawValue, forKey: Self.modelPreferenceKey)
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
  @Published var isCurrentDeleteConfirmationPresented = false
  @Published var libraryFilter: TrackLibraryFilter = .all
  @Published private(set) var tracks: [TrackRecord] = []
  @Published private(set) var libraryStatistics = LibraryStatistics.empty
  @Published private(set) var currentTrackID: UUID?
  @Published private(set) var statusText = "Загружаю локальную коллекцию…"
  @Published private(set) var isGenerating = false
  @Published private(set) var generationElapsedSeconds = 0
  @Published private(set) var isPlaying = false
  @Published private(set) var isLibraryLoading = true
  @Published private(set) var generationRuntimeReady = false
  @Published private(set) var modelRuntimeStatusText = "Проверяю локальную модель…"
  @Published private(set) var hasAcknowledgedStableAudioTerms = false
  @Published private(set) var isInstallingStableAudio = false
  @Published private(set) var modelInstallationElapsedSeconds = 0
  @Published private(set) var stableAudioInstallationProgress: StableAudioInstallationProgress?
  @Published private(set) var stableAudioInstallationErrorText: String?
  @Published private(set) var installedModelIDs: Set<MusicModelID> = []
  @Published private(set) var activeModelID: MusicModelID?
  @Published private(set) var installingModelID: MusicModelID?
  @Published private(set) var isRemovingStableAudio = false
  @Published private(set) var isUsingDevelopmentAudio = false
  @Published private(set) var playbackPositionSeconds: TimeInterval = 0
  @Published private(set) var playbackDurationSeconds: TimeInterval = 0
  @Published private(set) var isScrubbing = false
  @Published private(set) var isStoragePaused = false

  let hardware = HardwareProfile.current
  let hardwareSupport: HardwareSupport

  private static let storageLimitKey = "Flowtone.storageLimitGiB"
  private static let storageModeKey = "Flowtone.storageMode"
  private static let shuffleKey = "Flowtone.shuffleEnabled"
  private static let modelPreferenceKey = "Flowtone.modelPreference"
  private static let selectedGenresKey = "Flowtone.selectedGenres"
  private static let mixGenresKey = "Flowtone.mixGenresEnabled"
  private static let energyKey = "Flowtone.energy"
  private static let moodKey = "Flowtone.mood"
  private static let vibeKey = "Flowtone.vibe"
  private static let generationEnabledKey = "Flowtone.generationEnabled"
  private static let requestedCrossfadeSeconds: TimeInterval = 6
  private static let generatedTrackDurationSeconds = RadioGenerationPolicy.trackDurationSeconds
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
  private let stableAudioInstaller = StableAudioInstaller()
  private let licenseAcknowledgement: ModelLicenseAcknowledgement
  private let crossfade = EqualPowerCrossfade()
  private var playbackQueue = RadioPlaybackQueue()
  private var isPreparingNext = false
  private var generationCursor = 0
  private var playbackHistory: [UUID] = []
  private var playbackHistoryIndex: Int?
  private var memoryPressureObservationID: UUID?
  private var modelInstallationTask: Task<Void, Never>?
  private var modelInstallationClockTask: Task<Void, Never>?
  private var generationClockTask: Task<Void, Never>?

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
    let savedGenres = UserDefaults.standard.stringArray(forKey: Self.selectedGenresKey) ?? []
    let validSavedGenres = savedGenres.filter(Self.availableGenres.contains)
    if !validSavedGenres.isEmpty
      || UserDefaults.standard.object(forKey: Self.selectedGenresKey) != nil
    {
      selectedGenres = Set(validSavedGenres)
    }
    mixGenresEnabled = UserDefaults.standard.object(forKey: Self.mixGenresKey) as? Bool ?? false
    if validSavedGenres.count == 1 { mixGenresEnabled = false }
    energy =
      UserDefaults.standard.string(forKey: Self.energyKey)
      .flatMap(EnergyLevel.init(rawValue:)) ?? .calm
    mood =
      UserDefaults.standard.string(forKey: Self.moodKey)
      .flatMap(StationMood.init(rawValue:)) ?? .focused
    vibe = String((UserDefaults.standard.string(forKey: Self.vibeKey) ?? "").prefix(180))
    generationEnabled =
      UserDefaults.standard.object(forKey: Self.generationEnabledKey) as? Bool ?? true
    storageMode =
      UserDefaults.standard.string(forKey: Self.storageModeKey)
      .flatMap(RadioStorageMode.init(rawValue:)) ?? .recording
    shuffleEnabled =
      UserDefaults.standard.object(forKey: Self.shuffleKey) as? Bool ?? true
    let support = ModelRecommender().recommendation(for: .current)
    hardwareSupport = support
    modelPreference = .automatic
    UserDefaults.standard.set(ModelPreference.automatic.rawValue, forKey: Self.modelPreferenceKey)
    let savedStorageLimit = UserDefaults.standard.object(forKey: Self.storageLimitKey) as? Int
    storageLimitGiB = max(1, savedStorageLimit ?? 5)
    licenseAcknowledgement = ModelLicenseAcknowledgement()
    hasAcknowledgedStableAudioTerms = licenseAcknowledgement.hasAcknowledgedStableAudioTerms
    library = TrackLibrary(rootDirectory: Self.libraryRootDirectory)
    scheduler = GenerationScheduler(engine: SyntheticAudioEngine())
    memoryPressureObservationID = SystemMemoryPressureMonitor.shared.observe {
      [weak self] pressure in
      guard pressure != .normal else { return }
      Task { @MainActor [weak self] in
        await self?.handleMemoryPressure(pressure)
      }
    }
    Task {
      await configureGenerationRuntime()
      await bootstrapLibrary()
    }
  }

  deinit {
    modelInstallationTask?.cancel()
    modelInstallationClockTask?.cancel()
    generationClockTask?.cancel()
    if let memoryPressureObservationID {
      SystemMemoryPressureMonitor.shared.removeObservation(memoryPressureObservationID)
    }
  }

  var recommendedModelText: String {
    switch hardwareSupport {
    case .unsupported:
      return hardware.isAppleSilicon
        ? "Нужно не менее 8 ГБ объединённой памяти"
        : "Нужен Mac с Apple Silicon"
    case .supported(_, let warning):
      let name = modelName(for: MusicModelID.stableSmall)
      return warning == nil ? name : "\(name) · тестовый режим"
    }
  }

  var recommendedModelTier: ModelTier { .light }

  var recommendedModelID: MusicModelID { .stableSmall }

  var requestedModelID: MusicModelID { .stableSmall }

  var selectedModelText: String {
    modelName(for: .stableSmall)
  }

  var canGenerateTrack: Bool { generationEnabled && generationRuntimeReady && !isStoragePaused }

  var storageLimitAlertMessage: String {
    "Коллекция занимает \(Self.formatBytes(libraryStatistics.byteSize)) из лимита \(storageLimitGiB) ГБ. Новые треки не будут записываться, пока вы не удалите часть архива или не увеличите лимит. Уже сохранённая музыка продолжит играть."
  }

  var currentDeleteConfirmationMessage: String {
    guard let currentTrack else { return "Трек будет безвозвратно удалён с Mac." }
    return
      "«\(currentTrack.title)» будет безвозвратно удалён с Mac. Flowtone сразу включит соседний трек."
  }

  var stableAudioRuntimePath: String { modelCatalog.stableAudioRuntimePath }

  var modelRuntimePaths: String { stableAudioRuntimePath }

  var stableAudioInstallationIsComplete: Bool {
    installedModelIDs.contains(requestedModelID)
  }

  var stableAudioInstallationFraction: Double {
    stableAudioInstallationProgress?.completedFraction ?? 0
  }

  var stableAudioInstallationTitle: String {
    stableAudioInstallationProgress?.title ?? "Готово к автоматической установке"
  }

  var stableAudioInstallationDetail: String {
    let profile = MusicModelProfile.profile(for: installingModelID ?? requestedModelID)
    return stableAudioInstallationProgress?.detail
      ?? "Flowtone скачает \(profile.title) и подключит её автоматически."
  }

  var stableAudioTermsAcknowledgementText: String {
    ModelLicenseAcknowledgement.stableAudioTermsAcknowledgementText
  }

  var generationActionTitle: String {
    if isGenerating { return "Остановить · \(generationElapsedText)" }
    return isUsingDevelopmentAudio
      ? (currentTrack == nil ? "Создать тестовую" : "Создать тестовую ещё")
      : (currentTrack == nil ? "Создать первую" : "Создать ещё")
  }

  var generationElapsedText: String {
    Self.formatTime(TimeInterval(generationElapsedSeconds))
  }

  var modelInstallationElapsedText: String {
    Self.formatTime(TimeInterval(modelInstallationElapsedSeconds))
  }

  var selectedModelWarning: String? {
    let profile = MusicModelProfile.profile(for: requestedModelID)
    guard hardware.memoryGiB < profile.minimumMemoryGiB else { return nil }
    return "Для этой модели рекомендуется от \(profile.minimumMemoryGiB) ГБ памяти."
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

  func genreDisplayName(_ genre: String) -> String { Self.genreLabels[genre] ?? genre }
  func formatBytes(_ bytes: Int64) -> String { Self.formatBytes(bytes) }

  func toggleGenre(_ genre: String) {
    if selectedGenres.contains(genre) {
      selectedGenres.remove(genre)
    } else {
      selectedGenres.insert(genre)
    }
    if !canMixGenres { mixGenresEnabled = false }
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
    if isModelInstalled(.stableSmall) {
      Task { await configureGenerationRuntime() }
    } else {
      installModel(.stableSmall)
    }
  }

  func refreshGenerationRuntime() {
    Task { await configureGenerationRuntime() }
  }

  func isModelInstalled(_ modelID: MusicModelID) -> Bool {
    installedModelIDs.contains(modelID)
  }

  func isModelRecommended(_ modelID: MusicModelID) -> Bool {
    recommendedModelID == modelID
  }

  func selectModel(_ modelID: MusicModelID) {
    guard modelID == .stableSmall else { return }
    modelPreference = .automatic
  }

  func useAutomaticModelSelection() {
    modelPreference = .automatic
  }

  func installModel(_ modelID: MusicModelID = .stableSmall) {
    guard hasAcknowledgedStableAudioTerms else {
      stableAudioInstallationErrorText =
        "Сначала откройте официальные страницы и подтвердите, что прочитали условия."
      return
    }
    guard !isInstallingStableAudio else { return }
    guard modelID == .stableSmall else {
      stableAudioInstallationErrorText =
        "В этой версии Flowtone доступна только минимальная Stable Audio 3 Small."
      return
    }
    stableAudioInstallationErrorText = nil
    isInstallingStableAudio = true
    installingModelID = modelID
    stableAudioInstallationProgress = nil
    startModelInstallationClock()

    modelInstallationTask = Task { [weak self] in
      guard let self else { return }
      do {
        let updateProgress: @Sendable (StableAudioInstallationProgress) async -> Void = {
          [weak self] progress in
          await MainActor.run {
            self?.stableAudioInstallationProgress = progress
            self?.modelRuntimeStatusText = progress.title
          }
        }
        try await stableAudioInstaller.install(tier: .light, progress: updateProgress)
        installedModelIDs = Set(modelCatalog.installedModelIDs.filter { $0 == .stableSmall })
        modelPreference = .automatic
        await configureGenerationRuntime()
        stopModelInstallationClock()
        isInstallingStableAudio = false
        installingModelID = nil
        statusText = "\(modelName(for: modelID)) установлена и подключена"
      } catch is CancellationError {
        stopModelInstallationClock()
        isInstallingStableAudio = false
        installingModelID = nil
        stableAudioInstallationProgress = nil
        modelRuntimeStatusText = "Установка отменена · уже загруженные веса можно продолжить позже"
      } catch {
        stopModelInstallationClock()
        isInstallingStableAudio = false
        installingModelID = nil
        stableAudioInstallationErrorText = error.localizedDescription
        modelRuntimeStatusText = "Модель пока не установлена"
      }
      modelInstallationTask = nil
    }
  }

  func cancelStableAudioInstallation() {
    modelInstallationTask?.cancel()
  }

  func removeModel(_ modelID: MusicModelID) {
    guard modelID == .stableSmall else { return }
    guard !isInstallingStableAudio, !isRemovingStableAudio else { return }
    isRemovingStableAudio = true
    stableAudioInstallationErrorText = nil
    Task { [weak self] in
      guard let self else { return }
      if activeModelID == modelID {
        await scheduler.cancelActiveGeneration(reason: "Модель удаляется с устройства.")
      }
      do {
        try stableAudioInstaller.remove(tier: .light)
        modelPreference = .automatic
        await configureGenerationRuntime()
        statusText = "\(modelName(for: modelID)) удалена · локальные треки сохранены"
      } catch {
        stableAudioInstallationErrorText = error.localizedDescription
        modelRuntimeStatusText = "Не удалось удалить модель"
      }
      isRemovingStableAudio = false
    }
  }

  func skipTrack() {
    nextTrack()
  }

  func cancelGeneration() async {
    guard isGenerating else { return }
    statusText = "Останавливаю локальную генерацию…"
    await scheduler.cancelActiveGeneration(reason: "Генерация остановлена пользователем.")
    statusText = "Генерация остановлена · сохранённые треки не затронуты"
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

  func updatePlayback(publishUI: Bool = true) {
    guard playbackController.isPlaying || playbackController.isScrubbing else { return }
    playbackController.update()
    if publishUI { synchronizePlaybackState() }
  }

  func isTrackProtected(_ trackID: UUID) -> Bool {
    playbackQueue.protectedTrackIDs.contains(trackID)
  }

  func toggleCurrentLike() {
    guard let currentTrack else { return }
    Task { await setLiked(!currentTrack.isLiked, trackID: currentTrack.id) }
  }

  func requestCurrentTrackDeletion() {
    guard currentTrack != nil else { return }
    isCurrentDeleteConfirmationPresented = true
  }

  func confirmCurrentTrackDeletion() {
    isCurrentDeleteConfirmationPresented = false
    Task { await deleteCurrentTrack() }
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
      _ = try await library.removeOrphanedIncomingAudio()
      try await refreshLibrary()
      await pruneTransientTracks()
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
    await pruneTransientTracks()
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
    startGenerationClock()
    statusText = "Создаю новую локальную запись…"
    defer {
      stopGenerationClock()
      isGenerating = false
    }

    do {
      let seed = UInt64.random(in: 1...UInt64.max)
      let genres = nextGenerationGenres(seed: seed)
      guard let leadGenre = genres.first else { return }
      let automaticTempo = TempoPlanner().tempo(for: leadGenre, energy: energy, seed: seed)
      let configuration = StationConfiguration(
        genres: genres,
        energy: energy,
        tempoBPM: automaticTempo,
        mood: mood,
        vibe: vibe
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

      let track = try await library.importGeneratedAudio(
        audio,
        configuration: configuration,
        isTransient: storageMode == .live
      )
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
      await pruneTransientTracks()
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
    await pruneTransientTracks()
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
      try await fillPlaybackQueue()
      await pruneTransientTracks()
      try await refreshLibrary()
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
      let protected = playbackQueue.protectedTrackIDs
      let recent = Set(playbackHistory.suffix(3))
      let preferredExclusions = protected.union(recent)
      var candidate = try await nextLibraryCandidate(excluding: preferredExclusions)
      if candidate == nil {
        candidate = try await nextLibraryCandidate(excluding: protected)
      }
      guard let candidate, playbackQueue.enqueue(candidate.id) else { break }
    }
  }

  private func nextLibraryCandidate(excluding: Set<UUID>) async throws -> TrackRecord? {
    let filtered: TrackRecord?
    if shuffleEnabled {
      filtered = try await library.randomCompatibleTrack(
        genres: selectedGenres,
        excluding: excluding
      )
    } else {
      filtered = try await library.leastRecentlyPlayedTrack(
        genres: selectedGenres,
        excluding: excluding
      )
    }
    if filtered != nil { return filtered }
    return shuffleEnabled
      ? try await library.randomCompatibleTrack(genres: [], excluding: excluding)
      : try await library.leastRecentlyPlayedTrack(genres: [], excluding: excluding)
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
    let nextIsPlaying = playbackController.isPlaying
    let nextIsScrubbing = playbackController.isScrubbing
    let nextPosition = playbackController.position
    let nextDuration = playbackController.duration

    if isPlaying != nextIsPlaying { isPlaying = nextIsPlaying }
    if isScrubbing != nextIsScrubbing { isScrubbing = nextIsScrubbing }
    if abs(playbackPositionSeconds - nextPosition) >= 0.01 {
      playbackPositionSeconds = nextPosition
    }
    if abs(playbackDurationSeconds - nextDuration) >= 0.01 {
      playbackDurationSeconds = nextDuration
    }
  }

  private func setLiked(_ liked: Bool, trackID: UUID) async {
    do {
      _ = try await library.setLiked(liked, trackID: trackID)
      try await refreshLibrary()
      await pruneTransientTracks()
      statusText = liked ? "Запись сохранена в любимых" : "Запись убрана из любимых"
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func deleteCurrentTrack() async {
    guard let trackID = currentTrackID else { return }
    let replacementID = CurrentTrackDeletionPlanner.replacementTrackID(
      currentTrackID: trackID,
      readyTrackIDs: playbackQueue.readyTrackIDs,
      previousHistoryTrackID: previousHistoryIndex.map { playbackHistory[$0] },
      libraryTrackIDs: tracks.map(\.id)
    )

    playbackController.clear()
    playbackQueue = RadioPlaybackQueue()
    currentTrackID = nil
    synchronizePlaybackState()

    do {
      _ = try await library.removeTrack(trackID: trackID)
      playbackHistory.removeAll { $0 == trackID }
      playbackHistoryIndex = nil
      try await refreshLibrary()

      if let replacementID, let replacement = trackRecord(for: replacementID) {
        try await play(replacement)
        statusText = "Трек удалён · играет соседняя запись"
      } else if canGenerateTrack {
        await generateTrack(playWhenReady: true)
      } else {
        statusText = "Трек удалён · коллекция пуста"
      }
    } catch {
      statusText = error.localizedDescription
    }
  }

  private func pruneTransientTracks() async {
    guard storageMode == .live else { return }
    do {
      var protected = playbackQueue.protectedTrackIDs
      if let playbackHistoryIndex,
        playbackHistory.indices.contains(playbackHistoryIndex)
      {
        protected.insert(playbackHistory[playbackHistoryIndex])
        if playbackHistoryIndex > 0 {
          protected.insert(playbackHistory[playbackHistoryIndex - 1])
        }
      }
      let report = try await library.removeUnlikedTransient(protectedTrackIDs: protected)
      if report.removedTrackCount > 0 { try await refreshLibrary() }
    } catch {
      statusText = "Не удалось очистить временные треки: \(error.localizedDescription)"
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

  func modelName(for tier: ModelTier) -> String {
    StableAudioModelProfile.profile(for: tier).title
  }

  func modelName(for modelID: MusicModelID) -> String {
    MusicModelProfile.profile(for: modelID).title
  }

  private func configureGenerationRuntime() async {
    installedModelIDs = Set(modelCatalog.installedModelIDs.filter { $0 == .stableSmall })
    let requestedID = resolvedInstalledModelID()
    isUsingDevelopmentAudio = false
    activeModelID = nil

    guard hasAcknowledgedStableAudioTerms else {
      await configureUnavailableStableAudioRuntime(
        reason: "Нужно подтвердить, что вы сами прочитали официальные условия и страницу модели.")
      return
    }

    guard let requestedID else {
      await configureUnavailableStableAudioRuntime(
        reason: "Подходящая модель не установлена. Откройте «Модели», чтобы скачать её."
      )
      return
    }

    switch modelCatalog.availability(for: requestedID) {
    case .available:
      guard let engine = modelCatalog.engine(for: requestedID) else {
        generationRuntimeReady = false
        modelRuntimeStatusText = "Локальный музыкальный движок не удалось открыть"
        return
      }
      await scheduler.replaceEngine(engine)
      guard resolvedInstalledModelID() == requestedID else { return }
      activeModelID = requestedID
      generationRuntimeReady = true
      modelRuntimeStatusText = "\(modelName(for: requestedID)) готова · генерация на этом Mac"
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
      isUsingDevelopmentAudio = true
      generationRuntimeReady = true
      modelRuntimeStatusText = "Режим разработки: синтетический звук, не Stable Audio. \(reason)"
    } else {
      generationRuntimeReady = false
      modelRuntimeStatusText = reason
    }
  }

  private func resolvedInstalledModelID() -> MusicModelID? {
    installedModelIDs.contains(.stableSmall) ? .stableSmall : nil
  }

  private func startModelInstallationClock() {
    modelInstallationClockTask?.cancel()
    modelInstallationElapsedSeconds = 0
    modelInstallationClockTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { break }
        guard let self, self.isInstallingStableAudio else { break }
        self.modelInstallationElapsedSeconds += 1
      }
    }
  }

  private func stopModelInstallationClock() {
    modelInstallationClockTask?.cancel()
    modelInstallationClockTask = nil
  }

  private func startGenerationClock() {
    generationClockTask?.cancel()
    generationElapsedSeconds = 0
    generationClockTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { break }
        guard let self, self.isGenerating else { break }
        self.generationElapsedSeconds += 1
        self.statusText =
          "Генерация идёт · \(self.generationElapsedText) · трек появится после завершения"
      }
    }
  }

  private func stopGenerationClock() {
    generationClockTask?.cancel()
    generationClockTask = nil
  }

  private func handleMemoryPressure(_ pressure: MemoryPressure) async {
    let reason =
      pressure == .critical
      ? "Генерация остановлена: системе срочно нужна память."
      : "Генерация остановлена из-за нехватки памяти."
    await scheduler.cancelActiveGeneration(reason: reason)
    _ = try? await library.removeOrphanedIncomingAudio()
    isGenerating = false
    statusText = "\(reason) Временный кэш очищен; музыка продолжает играть."
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
