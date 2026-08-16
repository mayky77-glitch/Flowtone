import AVFoundation
import Combine
import FlowtoneCore
import Foundation

@MainActor
final class FlowtoneAppModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
  static let availableGenres = [
    "Ambient", "Lo-fi", "Classical", "Jazz", "Electronic", "Post-rock",
  ]
  static let genreLabels = [
    "Ambient": "Эмбиент",
    "Lo-fi": "Лоу-фай",
    "Classical": "Классика",
    "Jazz": "Джаз",
    "Electronic": "Электроника",
    "Post-rock": "Пост-рок",
  ]

  @Published var selectedGenres: Set<String> = ["Ambient", "Lo-fi"]
  @Published var energy: EnergyLevel = .calm
  @Published var tempoBPM = 82.0
  @Published var mood: StationMood = .focused
  @Published var vibe = ""
  @Published var generationEnabled = true
  @Published private(set) var statusText = "Станция готова к настройке"
  @Published private(set) var generatedFileURL: URL?
  @Published private(set) var isGenerating = false
  @Published private(set) var isPlaying = false

  let hardware = HardwareProfile.current
  let hardwareSupport: HardwareSupport

  private var audioPlayer: AVAudioPlayer?

  override init() {
    hardwareSupport = ModelRecommender().recommendation(for: .current)
    super.init()
  }

  var recommendedModelText: String {
    switch hardwareSupport {
    case .unsupported:
      return hardware.isAppleSilicon
        ? "Нужно не менее 8 ГБ объединённой памяти"
        : "Нужен Mac с Apple Silicon"
    case .supported(let recommended, let warning):
      let name =
        recommended == .quality
        ? "Качество · ACE-Step"
        : "Лёгкая · Stable Audio 3 Small"
      return warning == nil ? name : "\(name) · тестовый режим"
    }
  }

  var primaryGenre: String {
    Self.availableGenres.first(where: selectedGenres.contains) ?? "Ambient"
  }

  var primaryGenreDisplayName: String {
    Self.genreLabels[primaryGenre] ?? primaryGenre
  }

  func toggleGenre(_ genre: String) {
    if selectedGenres.contains(genre) {
      guard selectedGenres.count > 1 else { return }
      selectedGenres.remove(genre)
    } else {
      selectedGenres.insert(genre)
    }
  }

  func generateDevelopmentPreview() async {
    guard generationEnabled, !isGenerating else { return }
    isGenerating = true
    statusText = "Создаю локальную тестовую запись…"

    do {
      let outputDirectory = try Self.previewDirectory()
      let configuration = StationConfiguration(
        genres: Array(selectedGenres),
        energy: energy,
        tempoBPM: Int(tempoBPM.rounded()),
        mood: mood,
        vibe: vibe
      )
      let scheduler = GenerationScheduler(engine: SyntheticAudioEngine())
      let audio = try await scheduler.generateNext(
        configuration: configuration,
        durationSeconds: 8,
        seed: UInt64.random(in: 1...UInt64.max),
        outputDirectory: outputDirectory,
        resources: .current
      )

      guard let audio else {
        statusText = "Генерация приостановлена; будет играть коллекция"
        isGenerating = false
        return
      }

      generatedFileURL = audio.fileURL
      statusText = String(
        format: "Тестовая запись готова за %.2f с · музыкальная модель подключается отдельно",
        audio.elapsedSeconds
      )
      try play(url: audio.fileURL)
    } catch {
      statusText = error.localizedDescription
    }

    isGenerating = false
  }

  func togglePlayback() {
    guard let audioPlayer else { return }
    if audioPlayer.isPlaying {
      audioPlayer.pause()
      isPlaying = false
      statusText = "Пауза"
    } else {
      audioPlayer.play()
      isPlaying = true
      statusText = "Играет локальная тестовая запись"
    }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor [weak self] in
      self?.isPlaying = false
      self?.statusText =
        flag ? "Тестовая запись завершена" : "Не удалось завершить воспроизведение"
    }
  }

  private func play(url: URL) throws {
    let player = try AVAudioPlayer(contentsOf: url)
    player.delegate = self
    player.prepareToPlay()
    player.play()
    audioPlayer = player
    isPlaying = true
    statusText = "Играет локальная тестовая запись"
  }

  private static func previewDirectory() throws -> URL {
    let applicationSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return
      applicationSupport
      .appendingPathComponent("Flowtone", isDirectory: true)
      .appendingPathComponent("DevelopmentPreviews", isDirectory: true)
  }
}
