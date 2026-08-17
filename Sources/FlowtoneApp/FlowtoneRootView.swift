import AppKit
import Combine
import FlowtoneCore
import SwiftUI

struct FlowtoneRootView: View {
  @ObservedObject var model: FlowtoneAppModel
  private let playbackPulse = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [FlowtonePalette.canvasTop, FlowtonePalette.canvas, FlowtonePalette.canvasBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      RadialGradient(
        colors: [FlowtonePalette.signal.opacity(0.08), .clear],
        center: .trailing,
        startRadius: 20,
        endRadius: 620
      )
      .ignoresSafeArea()

      HStack(spacing: 0) {
        StationControls(model: model)
          .frame(width: 370)

        Rectangle()
          .fill(FlowtonePalette.line)
          .frame(width: 1)

        NowPlayingStage(model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .sheet(isPresented: $model.isLibraryPresented) {
      TrackLibraryView(model: model)
    }
    .onReceive(playbackPulse) { _ in
      model.updatePlayback()
    }
  }
}

private struct StationControls: View {
  @ObservedObject var model: FlowtoneAppModel

  private let columns = [GridItem(.flexible()), GridItem(.flexible())]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        VStack(alignment: .leading, spacing: 7) {
          Text("FLOWTONE")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .tracking(2.6)
            .foregroundStyle(FlowtonePalette.signal)

          Text("Музыка, которая\nне просит внимания")
            .font(.system(size: 31, weight: .medium, design: .serif))
            .tracking(-0.55)
            .foregroundStyle(FlowtonePalette.ink)

          HStack(spacing: 7) {
            Circle()
              .fill(FlowtonePalette.signal)
              .frame(width: 6, height: 6)
              .shadow(color: FlowtonePalette.signal.opacity(0.75), radius: 6)
            Text("ЛОКАЛЬНЫЙ ЭФИР · БЕЗ КОНЦА")
              .font(.system(size: 9, weight: .medium, design: .monospaced))
              .tracking(1.1)
              .foregroundStyle(FlowtonePalette.muted)
          }
          .padding(.top, 3)
        }

        controlSection("Жанры") {
          LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(FlowtoneAppModel.availableGenres, id: \.self) { genre in
              GenreChip(
                title: FlowtoneAppModel.genreLabels[genre] ?? genre,
                selected: model.selectedGenres.contains(genre)
              ) {
                model.toggleGenre(genre)
              }
            }
          }
        }

        controlSection("Энергия") {
          Picker("Энергия", selection: $model.energy) {
            Text("Тихо").tag(EnergyLevel.calm)
            Text("Ровно").tag(EnergyLevel.balanced)
            Text("Драйв").tag(EnergyLevel.driving)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .tint(FlowtonePalette.signal)
        }

        controlSection("Темп · \(Int(model.tempoBPM)) уд/мин") {
          Slider(value: $model.tempoBPM, in: 55...150, step: 1)
            .tint(FlowtonePalette.signal)
        }

        controlSection("Настроение") {
          Picker("Настроение", selection: $model.mood) {
            Text("Фокус").tag(StationMood.focused)
            Text("Тепло").tag(StationMood.warm)
            Text("Мечтательно").tag(StationMood.dreamy)
            Text("Темно").tag(StationMood.dark)
            Text("Светло").tag(StationMood.uplifting)
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        controlSection("Вайб · необязательно") {
          TextField(
            "Например: дождь за окном, ночной город",
            text: $model.vibe
          )
          .textFieldStyle(.plain)
          .padding(12)
          .background(FlowtonePalette.panel, in: RoundedRectangle(cornerRadius: 12))
          .overlay {
            RoundedRectangle(cornerRadius: 12)
              .stroke(FlowtonePalette.line, lineWidth: 1)
          }
        }

        Toggle("Локальная генерация", isOn: $model.generationEnabled)
          .toggleStyle(.switch)
          .tint(FlowtonePalette.signal)

        Text("Изменения применяются со следующего трека")
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(FlowtonePalette.muted)
      }
      .padding(30)
    }
    .background {
      LinearGradient(
        colors: [FlowtonePalette.sidebarTop, FlowtonePalette.sidebar],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  @ViewBuilder
  private func controlSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .tracking(1.2)
        .foregroundStyle(FlowtonePalette.muted)
      content()
    }
  }
}

private struct GenreChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .foregroundStyle(selected ? FlowtonePalette.selectedInk : FlowtonePalette.ink)
        .background(
          selected ? FlowtonePalette.signal : FlowtonePalette.panel,
          in: Capsule()
        )
        .overlay {
          Capsule()
            .stroke(selected ? FlowtonePalette.signalBright.opacity(0.45) : FlowtonePalette.line)
        }
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct NowPlayingStage: View {
  @ObservedObject var model: FlowtoneAppModel
  @State private var isModelSetupPresented = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        modelBadge
        Spacer()
        libraryBadge
      }
      .padding(28)

      Spacer()

      VinylBroadcastVisual(
        isSpinning: model.isPlaying || model.isGenerating,
        isPlaying: model.isPlaying,
        genreTitle: model.currentGenreDisplayName,
        trackID: model.currentTrackID,
        trackDurationSeconds: model.currentTrack?.durationSeconds ?? 120
      )
      .frame(maxWidth: 560)
      .frame(height: 292)

      VStack(spacing: 8) {
        Text(model.isGenerating ? "СОЗДАЁТСЯ НОВАЯ ЗАПИСЬ" : "СЕЙЧАС В ЭФИРЕ")
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .tracking(2)
          .foregroundStyle(FlowtonePalette.signal)

        Text(model.currentTrackTitle)
          .font(.system(size: 25, weight: .medium, design: .serif))
          .foregroundStyle(FlowtonePalette.ink)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .minimumScaleFactor(0.75)
          .frame(maxWidth: 520)

        Text(model.statusText)
          .font(.system(size: 12, design: .rounded))
          .multilineTextAlignment(.center)
          .foregroundStyle(FlowtonePalette.muted)
          .frame(maxWidth: 390)
      }

      HStack(spacing: 12) {
        Button {
          model.toggleCurrentLike()
        } label: {
          Image(systemName: model.isCurrentTrackLiked ? "heart.fill" : "heart")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(
              model.isCurrentTrackLiked ? FlowtonePalette.signal : FlowtonePalette.ink
            )
            .frame(width: 44, height: 44)
            .background(FlowtonePalette.panel, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.currentTrack == nil)

        Button {
          model.togglePlayback()
        } label: {
          Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(FlowtonePalette.selectedInk)
            .frame(width: 48, height: 48)
            .background(FlowtonePalette.signal, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isLibraryLoading)

        Button {
          model.skipTrack()
        } label: {
          Image(systemName: "forward.end.fill")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(FlowtonePalette.panel, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.currentTrack == nil && !model.canGenerateTrack)

        Button {
          Task { await model.generateDevelopmentPreview() }
        } label: {
          HStack(spacing: 9) {
            if model.isGenerating {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "waveform.badge.plus")
            }
            Text(model.generationActionTitle)
          }
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.canvas)
          .padding(.horizontal, 20)
          .frame(height: 48)
          .background(FlowtonePalette.signal, in: Capsule())
          .shadow(color: FlowtonePalette.signal.opacity(0.22), radius: 18, y: 7)
        }
        .buttonStyle(.plain)
        .disabled(!model.canGenerateTrack || model.isGenerating)
      }
      .padding(.top, 24)

      HStack(spacing: 10) {
        Image(systemName: "speaker.fill")
        Slider(value: $model.volume, in: 0...1)
          .tint(FlowtonePalette.signal)
          .frame(width: 180)
        Image(systemName: "speaker.wave.2.fill")
      }
      .font(.system(size: 10))
      .foregroundStyle(FlowtonePalette.muted)
      .padding(.top, 16)

      Spacer()

      HStack {
        Label("Файлы остаются на этом Mac", systemImage: "lock.fill")
        Spacer()
        Text("\(model.hardware.memoryGiB) ГБ объединённой памяти")
      }
      .font(.system(size: 11, design: .monospaced))
      .foregroundStyle(FlowtonePalette.muted)
      .padding(28)
    }
    .sheet(isPresented: $isModelSetupPresented) {
      StableAudioSetupSheet(model: model)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 500, idealHeight: 650)
    }
  }

  private var modelBadge: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("МОДЕЛЬ ГЕНЕРАЦИИ")
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1.1)
        .foregroundStyle(FlowtonePalette.muted)
      Picker("", selection: $model.selectedModelTier) {
        Text("Лёгкая · Stable Audio 3 Small").tag(ModelTier.light)
        Text("Качество · ACE-Step").tag(ModelTier.quality)
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()

      if let warning = model.selectedModelWarning {
        Text(warning)
          .font(.system(size: 9, design: .rounded))
          .foregroundStyle(FlowtonePalette.signal)
          .frame(maxWidth: 250, alignment: .leading)
      }

      Text(model.modelRuntimeStatusText)
        .font(.system(size: 9, design: .rounded))
        .foregroundStyle(
          model.generationRuntimeReady ? FlowtonePalette.muted : FlowtonePalette.signal
        )
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 300, alignment: .leading)

      if model.selectedModelTier == .light {
        Button("Настроить модель") {
          isModelSetupPresented = true
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .buttonStyle(.bordered)
        .tint(FlowtonePalette.signal)
        .accessibilityHint("Откроет настройку Stable Audio 3 Small")
      }
    }
    .frame(width: 300, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(FlowtonePalette.panel, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(FlowtonePalette.line, lineWidth: 1)
    }
  }

  private var libraryBadge: some View {
    Button {
      model.isLibraryPresented = true
    } label: {
      VStack(alignment: .trailing, spacing: 4) {
        HStack(spacing: 6) {
          Image(systemName: "music.note.list")
          Text("КОЛЛЕКЦИЯ")
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1)
        .foregroundStyle(FlowtonePalette.muted)

        Text(model.librarySummaryText)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(FlowtonePalette.ink)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(FlowtonePalette.panel, in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(FlowtonePalette.line, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct StableAudioSetupSheet: View {
  @ObservedObject var model: FlowtoneAppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [FlowtonePalette.canvasTop, FlowtonePalette.canvas, FlowtonePalette.canvasBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 5) {
            Text("НАСТРОЙКА МОДЕЛИ")
              .font(.system(size: 10, weight: .semibold, design: .monospaced))
              .tracking(1.2)
              .foregroundStyle(FlowtonePalette.signal)
            Text("Stable Audio 3 Small")
              .font(.system(size: 25, weight: .medium, design: .serif))
              .foregroundStyle(FlowtonePalette.ink)
            Text("Ручная установка и проверка доступа")
              .font(.system(size: 12, design: .rounded))
              .foregroundStyle(FlowtonePalette.muted)
          }

          Spacer()

          Button(action: { dismiss() }) {
            Label("Закрыть", systemImage: "xmark")
              .labelStyle(.iconOnly)
              .frame(width: 32, height: 32)
          }
          .buttonStyle(.bordered)
          .tint(FlowtonePalette.signal)
          .accessibilityLabel("Закрыть настройку модели")
          .accessibilityHint("Также можно нажать Escape")
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 18)

        Rectangle()
          .fill(FlowtonePalette.line)
          .frame(height: 1)

        ScrollView {
          StableAudioSetupGate(model: model)
            .padding(28)
        }
        .accessibilityLabel("Настройка Stable Audio 3 Small")
      }
    }
  }
}

private struct StableAudioSetupGate: View {
  @ObservedObject var model: FlowtoneAppModel

  private static let repositoryURL = URL(string: "https://github.com/Stability-AI/stable-audio-3")!
  private static let mlxInstructionsURL = URL(
    string: "https://github.com/Stability-AI/stable-audio-3/tree/main/optimized/mlx")!
  private static let modelCardURL = URL(
    string: "https://huggingface.co/stabilityai/stable-audio-3-small-music")!
  private static let licenseURL = URL(string: "https://stability.ai/license")!

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("НАСТРОЙКА STABLE AUDIO 3 SMALL")
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(FlowtonePalette.muted)

      Text("Flowtone не принимает условия за вас и не скачивает веса с ограниченным доступом.")
        .font(.system(size: 10, design: .rounded))
        .foregroundStyle(FlowtonePalette.ink)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 5) {
        Text("Установите исполняемый модуль вручную по пути:")
          .font(.system(size: 9, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
        Text(model.stableAudioRuntimePath)
          .font(.system(size: 8, design: .monospaced))
          .textSelection(.enabled)
          .foregroundStyle(FlowtonePalette.ink)
          .fixedSize(horizontal: false, vertical: true)
        Label(
          model.stableAudioRuntimeIsExecutable
            ? "Исполняемый модуль найден"
            : "Исполняемый модуль не найден или недоступен",
          systemImage: model.stableAudioRuntimeIsExecutable
            ? "checkmark.circle.fill" : "xmark.circle"
        )
        .font(.system(size: 9, design: .rounded))
        .foregroundStyle(
          model.stableAudioRuntimeIsExecutable ? FlowtonePalette.muted : FlowtonePalette.signal)
      }

      HStack(spacing: 7) {
        officialPageButton("Репозиторий", url: Self.repositoryURL)
        officialPageButton("MLX-инструкция", url: Self.mlxInstructionsURL)
      }
      HStack(spacing: 7) {
        officialPageButton("Страница модели", url: Self.modelCardURL)
        officialPageButton("Лицензия", url: Self.licenseURL)
      }

      Text(
        "На Hugging Face доступ к модели ограничен, и она также ссылается на условия Gemma. Примите применимые условия только лично на официальных страницах."
      )
      .font(.system(size: 9, design: .rounded))
      .foregroundStyle(FlowtonePalette.muted)
      .fixedSize(horizontal: false, vertical: true)

      Text(model.stableAudioTermsAcknowledgementText)
        .font(.system(size: 9, design: .rounded))
        .foregroundStyle(FlowtonePalette.muted)
        .fixedSize(horizontal: false, vertical: true)

      if model.hasAcknowledgedStableAudioTerms {
        Label("Отметка о прочтении сохранена", systemImage: "checkmark.circle.fill")
          .font(.system(size: 9, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
      } else {
        Button(action: model.acknowledgeStableAudioTermsRead) {
          Text("Я сам(а) открыл(а) и прочитал(а) официальные условия")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(FlowtonePalette.signal)
        .accessibilityHint(model.stableAudioTermsAcknowledgementText)
      }

      Button("Проверить локальный движок", action: model.refreshGenerationRuntime)
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .buttonStyle(.bordered)
        .tint(FlowtonePalette.signal)
        .accessibilityHint("Повторно проверит исполняемый модуль по указанному пути")
    }
    .padding(.top, 2)
  }

  private func officialPageButton(_ title: String, url: URL) -> some View {
    Button(title) { NSWorkspace.shared.open(url) }
      .font(.system(size: 9, weight: .semibold, design: .rounded))
      .buttonStyle(.bordered)
      .tint(FlowtonePalette.signal)
      .accessibilityLabel("Открыть: \(title)")
      .accessibilityHint("Откроется официальная страница в браузере")
  }
}

private struct TrackLibraryView: View {
  @ObservedObject var model: FlowtoneAppModel
  @Environment(\.dismiss) private var dismiss
  @State private var confirmsCleanup = false

  private let columns = [GridItem(.flexible()), GridItem(.flexible())]

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text("ЛОКАЛЬНАЯ КОЛЛЕКЦИЯ")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(FlowtonePalette.signal)
          Text("Архив эфира")
            .font(.system(size: 28, weight: .medium, design: .serif))
            .foregroundStyle(FlowtonePalette.ink)
          Text("Записи остаются на этом Mac")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(FlowtonePalette.muted)
        }

        Spacer()

        Button("Готово") { dismiss() }
          .buttonStyle(.plain)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.signal)
      }
      .padding(28)

      HStack(spacing: 12) {
        libraryMetric(
          title: "ВСЕГО",
          value: "\(model.libraryStatistics.trackCount) треков",
          detail: model.formatBytes(model.libraryStatistics.byteSize)
        )
        libraryMetric(
          title: "ЛЮБИМЫЕ",
          value: "\(model.libraryStatistics.likedTrackCount)",
          detail: "защищены от очистки"
        )

        VStack(alignment: .leading, spacing: 7) {
          Text("ЛИМИТ ХРАНИЛИЩА")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(FlowtonePalette.muted)
          Picker("", selection: $model.storageLimitGiB) {
            ForEach([1, 5, 10, 20, 50], id: \.self) { value in
              Text("\(value) ГБ").tag(value)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .onChange(of: model.storageLimitGiB) { _, _ in model.applyStorageLimit() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(FlowtonePalette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(FlowtonePalette.line) }
      }
      .padding(.horizontal, 28)

      if !model.libraryStatistics.genres.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text("ПО ЖАНРАМ")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(FlowtonePalette.muted)

          LazyVGrid(columns: columns, spacing: 8) {
            ForEach(model.libraryStatistics.genres, id: \.genre) { item in
              HStack {
                Text(model.genreDisplayName(item.genre))
                Spacer()
                Text("\(item.trackCount) · \(model.formatBytes(item.byteSize))")
                  .foregroundStyle(FlowtonePalette.muted)
              }
              .font(.system(size: 11, design: .rounded))
              .foregroundStyle(FlowtonePalette.ink)
              .padding(.horizontal, 12)
              .frame(height: 34)
              .background(
                FlowtonePalette.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
            }
          }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
      }

      Divider()
        .overlay(FlowtonePalette.line)
        .padding(.top, 18)

      if model.tracks.isEmpty {
        VStack(spacing: 9) {
          Image(systemName: "music.note")
            .font(.system(size: 24))
            .foregroundStyle(FlowtonePalette.signal)
          Text("Здесь появятся записи станции")
            .font(.system(size: 15, weight: .medium, design: .serif))
            .foregroundStyle(FlowtonePalette.ink)
          Text("Создайте первую запись на главном экране")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(FlowtonePalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 1) {
            ForEach(model.tracks) { track in
              trackRow(track)
            }
          }
          .padding(.vertical, 8)
        }
      }

      HStack {
        Text("Лайкнутые записи не удаляются автоматически")
          .font(.system(size: 10, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
        Spacer()
        Button("Удалить всё без лайка") { confirmsCleanup = true }
          .buttonStyle(.plain)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.signal)
          .disabled(model.libraryStatistics.trackCount == model.libraryStatistics.likedTrackCount)
      }
      .padding(20)
      .background(FlowtonePalette.sidebar)
    }
    .frame(minWidth: 700, minHeight: 650)
    .background(FlowtonePalette.canvas)
    .preferredColorScheme(.dark)
    .confirmationDialog(
      "Удалить все записи без лайка?",
      isPresented: $confirmsCleanup,
      titleVisibility: .visible
    ) {
      Button("Удалить", role: .destructive) { model.removeAllUnliked() }
      Button("Отмена", role: .cancel) {}
    } message: {
      Text(
        "Текущая и подготовленные записи доиграют. Остальные файлы без лайка будут удалены с Mac.")
    }
  }

  private func libraryMetric(title: String, value: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1)
        .foregroundStyle(FlowtonePalette.muted)
      Text(value)
        .font(.system(size: 16, weight: .medium, design: .serif))
        .foregroundStyle(FlowtonePalette.ink)
      Text(detail)
        .font(.system(size: 9, design: .rounded))
        .foregroundStyle(FlowtonePalette.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(FlowtonePalette.panel, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(FlowtonePalette.line) }
  }

  private func trackRow(_ track: TrackRecord) -> some View {
    HStack(spacing: 12) {
      Circle()
        .fill(track.id == model.currentTrackID ? FlowtonePalette.signal : FlowtonePalette.orbit)
        .frame(width: 7, height: 7)

      VStack(alignment: .leading, spacing: 3) {
        Text(track.title)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.ink)
          .lineLimit(1)
        Text(track.createdAt.formatted(date: .abbreviated, time: .shortened))
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(FlowtonePalette.muted)
      }

      Text(track.genres.map(model.genreDisplayName).joined(separator: ", "))
        .font(.system(size: 11, design: .rounded))
        .foregroundStyle(FlowtonePalette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(model.formatBytes(track.byteSize))
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(FlowtonePalette.muted)
        .frame(width: 70, alignment: .trailing)

      Button {
        model.toggleLike(trackID: track.id)
      } label: {
        Image(systemName: track.isLiked ? "heart.fill" : "heart")
          .foregroundStyle(track.isLiked ? FlowtonePalette.signal : FlowtonePalette.muted)
      }
      .buttonStyle(.plain)

      Button {
        model.deleteTrack(trackID: track.id)
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(FlowtonePalette.muted)
      }
      .buttonStyle(.plain)
      .disabled(model.isTrackProtected(track.id))
      .help(model.isTrackProtected(track.id) ? "Запись уже подготовлена к эфиру" : "Удалить запись")
    }
    .padding(.horizontal, 28)
    .frame(height: 54)
    .background(track.id == model.currentTrackID ? FlowtonePalette.panel.opacity(0.72) : .clear)
  }
}

private struct VinylBroadcastVisual: View {
  let isSpinning: Bool
  let isPlaying: Bool
  let genreTitle: String
  let trackID: UUID?
  let trackDurationSeconds: Int

  @State private var playbackStartedAt = Date()

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !isSpinning)) { timeline in
      let seconds = timeline.date.timeIntervalSinceReferenceDate
      let elapsed = max(0, timeline.date.timeIntervalSince(playbackStartedAt))
      let grooveProgress = min(elapsed / Double(max(trackDurationSeconds, 1)), 1)
      ZStack {
        HStack(spacing: -18) {
          VinylRecord(
            angle: isSpinning ? seconds * 24 : 0,
            genreTitle: genreTitle
          )
          .frame(width: 305, height: 305)

          ToneArm(isActive: isPlaying, grooveProgress: grooveProgress)
            .frame(width: 88, height: 250)
            .offset(x: -8, y: -6)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      isSpinning
        ? "Пластинка вращается, жанр \(genreTitle)"
        : "Пластинка остановлена, жанр \(genreTitle)"
    )
    .onChange(of: trackID) { _, _ in playbackStartedAt = Date() }
    .onChange(of: isPlaying) { _, playing in
      if playing { playbackStartedAt = Date() }
    }
  }
}

private struct VinylRecord: View {
  let angle: Double
  let genreTitle: String

  var body: some View {
    ZStack {
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [Color(red: 0.18, green: 0.12, blue: 0.09), .black],
              center: .center,
              startRadius: 4,
              endRadius: 145
            )
          )

        ForEach(0..<15, id: \.self) { index in
          Circle()
            .stroke(FlowtonePalette.groove.opacity(0.22 + Double(index % 3) * 0.05), lineWidth: 0.7)
            .padding(CGFloat(11 + index * 7))
        }

        Circle()
          .fill(
            AngularGradient(
              colors: [.clear, FlowtonePalette.ink.opacity(0.11), .clear, .clear],
              center: .center
            )
          )
          .blendMode(.screen)

        Capsule()
          .fill(FlowtonePalette.signalBright.opacity(0.58))
          .frame(width: 3, height: 34)
          .offset(y: -112)
      }
      .rotationEffect(.degrees(angle))

      Circle()
        .fill(
          RadialGradient(
            colors: [FlowtonePalette.signalBright, FlowtonePalette.copper],
            center: .topLeading,
            startRadius: 3,
            endRadius: 70
          )
        )
        .frame(width: 104, height: 104)
        .overlay {
          VStack(spacing: 4) {
            Text("FLOWTONE")
              .font(.system(size: 9, weight: .bold, design: .monospaced))
              .tracking(1.4)
            Text(genreTitle.uppercased())
              .font(.system(size: 8, weight: .semibold, design: .rounded))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          .foregroundStyle(FlowtonePalette.selectedInk)
          .padding(.horizontal, 12)
        }
        .rotationEffect(.degrees(angle))

      Circle()
        .fill(FlowtonePalette.canvasBottom)
        .frame(width: 9, height: 9)
        .overlay { Circle().stroke(FlowtonePalette.ink.opacity(0.4), lineWidth: 1) }
    }
    .shadow(color: .black.opacity(0.62), radius: 28, y: 20)
    .shadow(color: FlowtonePalette.signal.opacity(0.08), radius: 36)
  }
}

private struct ToneArm: View {
  let isActive: Bool
  let grooveProgress: Double

  private var angle: Double {
    guard isActive else { return -7 }
    // The pickup starts at the outer edge and slowly travels left, toward the record centre.
    return 10 + (grooveProgress * 12)
  }

  var body: some View {
    ZStack(alignment: .top) {
      Circle()
        .fill(FlowtonePalette.panelWarm)
        .frame(width: 42, height: 42)
        .overlay { Circle().stroke(FlowtonePalette.copper, lineWidth: 2) }

      VStack(spacing: -2) {
        Capsule()
          .fill(
            LinearGradient(
              colors: [FlowtonePalette.ink.opacity(0.82), FlowtonePalette.copper],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 8, height: 184)

        RoundedRectangle(cornerRadius: 3)
          .fill(FlowtonePalette.signal)
          .frame(width: 25, height: 14)
          .rotationEffect(.degrees(5))
          .offset(x: 7)
      }
      .rotationEffect(.degrees(angle), anchor: .top)
      .offset(y: 26)
      .animation(.spring(response: 0.7, dampingFraction: 0.72), value: isActive)
    }
  }
}

private enum FlowtonePalette {
  static let canvasTop = Color(red: 0.105, green: 0.072, blue: 0.055)
  static let canvas = Color(red: 0.075, green: 0.052, blue: 0.043)
  static let canvasBottom = Color(red: 0.045, green: 0.035, blue: 0.032)
  static let sidebarTop = Color(red: 0.145, green: 0.095, blue: 0.065)
  static let sidebar = Color(red: 0.095, green: 0.064, blue: 0.052)
  static let panel = Color(red: 0.145, green: 0.102, blue: 0.078)
  static let panelWarm = Color(red: 0.22, green: 0.14, blue: 0.085)
  static let ink = Color(red: 0.94, green: 0.875, blue: 0.74)
  static let selectedInk = Color(red: 0.13, green: 0.075, blue: 0.04)
  static let muted = Color(red: 0.67, green: 0.56, blue: 0.43)
  static let signal = Color(red: 0.91, green: 0.57, blue: 0.24)
  static let signalBright = Color(red: 1.0, green: 0.72, blue: 0.38)
  static let copper = Color(red: 0.72, green: 0.39, blue: 0.20)
  static let orbit = Color(red: 0.46, green: 0.29, blue: 0.19)
  static let groove = Color(red: 0.65, green: 0.43, blue: 0.28)
  static let line = Color(red: 0.84, green: 0.61, blue: 0.36).opacity(0.16)
}
