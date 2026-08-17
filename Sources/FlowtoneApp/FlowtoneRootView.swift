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
          HStack(spacing: 8) {
            Button("Выбрать все", action: model.selectAllGenres)
              .disabled(model.areAllGenresSelected)
            Button("Снять все", action: model.clearGenreFilters)
              .disabled(model.selectedGenres.isEmpty)
          }
          .font(.system(size: 10, weight: .semibold, design: .rounded))
          .buttonStyle(.bordered)
          .tint(FlowtonePalette.signal)

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
        isSpinning: model.isPlaying || model.isScrubbing,
        isPlaying: model.isPlaying,
        isScrubbing: model.isScrubbing,
        genreTitle: model.currentGenreDisplayName,
        progress: model.playbackProgress,
        positionSeconds: model.playbackPositionSeconds,
        durationSeconds: model.playbackDurationSeconds,
        hasTrack: model.currentTrack != nil,
        onScrubBegan: model.beginScrubbing,
        onScrubChanged: model.scrub,
        onScrubEnded: model.endScrubbing
      )
      .frame(maxWidth: 580)
      .frame(height: 270)

      VStack(spacing: 8) {
        Text(model.isGenerating ? "СОЗДАЁТСЯ НОВАЯ ЗАПИСЬ" : "СЕЙЧАС В ЭФИРЕ")
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .tracking(2)
          .foregroundStyle(FlowtonePalette.signal)

        Text(model.currentTrackTitle)
          .font(.system(size: 23, weight: .medium, design: .serif))
          .foregroundStyle(FlowtonePalette.ink)
          .multilineTextAlignment(.center)
          .lineLimit(2, reservesSpace: true)
          .minimumScaleFactor(0.82)
          .frame(maxWidth: 610, minHeight: 56)

        Text(model.statusText)
          .font(.system(size: 12, design: .rounded))
          .multilineTextAlignment(.center)
          .foregroundStyle(FlowtonePalette.muted)
          .frame(maxWidth: 390)
      }

      PlaybackConsole(model: model)
        .frame(maxWidth: 650)
        .padding(.top, 12)

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
    HStack(spacing: 0) {
      Button {
        model.showLibrary(filter: .all)
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
      }
      .buttonStyle(.plain)

      Rectangle()
        .fill(FlowtonePalette.line)
        .frame(width: 1, height: 38)

      Button {
        model.showLibrary(filter: .liked)
      } label: {
        VStack(spacing: 4) {
          Image(systemName: "heart.fill")
            .font(.system(size: 12, weight: .semibold))
          Text("\(model.libraryStatistics.likedTrackCount) любимых")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(FlowtonePalette.signal)
        .frame(minWidth: 82)
        .padding(.vertical, 10)
      }
      .buttonStyle(.plain)
    }
    .background(FlowtonePalette.panel, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(FlowtonePalette.line) }
  }
}

private struct PlaybackConsole: View {
  @ObservedObject var model: FlowtoneAppModel
  @State private var draftPosition: TimeInterval = 0
  @State private var previousDraftPosition: TimeInterval = 0
  @State private var isEditingPosition = false

  private var sliderPosition: Binding<Double> {
    Binding(
      get: { isEditingPosition ? draftPosition : model.playbackPositionSeconds },
      set: { value in
        if !isEditingPosition {
          isEditingPosition = true
          draftPosition = model.playbackPositionSeconds
          previousDraftPosition = draftPosition
          model.beginScrubbing()
        }
        let direction: AudioScrubDirection = value >= previousDraftPosition ? .forward : .backward
        draftPosition = value
        previousDraftPosition = value
        model.scrub(to: value, direction: direction)
      }
    )
  }

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Button("Начало", action: model.seekToBeginning)
          .frame(width: 52)
          .disabled(model.currentTrack == nil)

        Text(model.playbackTimeText)
          .frame(width: 42, alignment: .trailing)

        Slider(
          value: sliderPosition,
          in: 0...max(model.playbackDurationSeconds, 1),
          onEditingChanged: positionEditingChanged
        )
        .tint(FlowtonePalette.signal)
        .accessibilityLabel("Позиция в треке")
        .accessibilityValue("\(model.playbackTimeText) из \(model.playbackDurationText)")

        Text(model.playbackDurationText)
          .frame(width: 42, alignment: .leading)

        Button("Конец", action: model.seekToEnd)
          .frame(width: 52)
          .disabled(model.currentTrack == nil)
      }
      .font(.system(size: 10, weight: .medium, design: .monospaced))
      .foregroundStyle(FlowtonePalette.muted)
      .buttonStyle(.plain)

      HStack(spacing: 10) {
        transportButton(
          systemName: "backward.end.fill",
          label: "Предыдущая запись",
          disabled: !model.canGoToPreviousTrack,
          action: model.previousTrack
        )
        transportButton(
          systemName: "gobackward.15",
          label: "Назад на 15 секунд",
          disabled: model.currentTrack == nil
        ) { model.seek(by: -15) }

        Button(action: model.togglePlayback) {
          Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(FlowtonePalette.selectedInk)
            .frame(width: 48, height: 48)
            .background(FlowtonePalette.signal, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isLibraryLoading)
        .accessibilityLabel(model.isPlaying ? "Пауза" : "Воспроизвести")

        transportButton(
          systemName: "goforward.15",
          label: "Вперёд на 15 секунд",
          disabled: model.currentTrack == nil
        ) { model.seek(by: 15) }
        transportButton(
          systemName: "forward.end.fill",
          label: "Следующая запись",
          disabled: !model.canGoToNextTrack,
          action: model.nextTrack
        )

        Button(action: model.toggleCurrentLike) {
          Image(systemName: model.isCurrentTrackLiked ? "heart.fill" : "heart")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
              model.isCurrentTrackLiked ? FlowtonePalette.signal : FlowtonePalette.ink
            )
            .frame(width: 40, height: 40)
            .background(FlowtonePalette.panel, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.currentTrack == nil)
        .accessibilityLabel(model.isCurrentTrackLiked ? "Убрать из любимых" : "Добавить в любимые")

        Button {
          Task { await model.generateDevelopmentPreview() }
        } label: {
          HStack(spacing: 8) {
            if model.isGenerating {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "waveform.badge.plus")
            }
            Text(model.generationActionTitle)
          }
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.canvas)
          .padding(.horizontal, 16)
          .frame(height: 42)
          .background(FlowtonePalette.signal, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canGenerateTrack || model.isGenerating)
      }

      HStack(spacing: 10) {
        Image(systemName: "speaker.fill")
        Slider(value: $model.volume, in: 0...1)
          .tint(FlowtonePalette.signal)
          .frame(width: 180)
        Image(systemName: "speaker.wave.2.fill")
      }
      .font(.system(size: 10))
      .foregroundStyle(FlowtonePalette.muted)
    }
    .padding(12)
    .background(FlowtonePalette.panel.opacity(0.52), in: RoundedRectangle(cornerRadius: 16))
    .overlay { RoundedRectangle(cornerRadius: 16).stroke(FlowtonePalette.line) }
  }

  private func positionEditingChanged(_ editing: Bool) {
    if editing {
      guard !isEditingPosition else { return }
      isEditingPosition = true
      draftPosition = model.playbackPositionSeconds
      previousDraftPosition = draftPosition
      model.beginScrubbing()
    } else {
      guard isEditingPosition else { return }
      isEditingPosition = false
      model.endScrubbing()
    }
  }

  private func transportButton(
    systemName: String,
    label: String,
    disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 38, height: 38)
        .background(FlowtonePalette.panel, in: Circle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityLabel(label)
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

  private var visibleTracks: [TrackRecord] {
    switch model.libraryFilter {
    case .all: model.tracks
    case .liked: model.tracks.filter(\.isLiked)
    }
  }

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

      Picker("Раздел коллекции", selection: $model.libraryFilter) {
        ForEach(TrackLibraryFilter.allCases) { filter in
          Text(filter.title).tag(filter)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .tint(FlowtonePalette.signal)
      .padding(.horizontal, 28)
      .padding(.bottom, 16)

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

      if visibleTracks.isEmpty {
        VStack(spacing: 9) {
          Image(systemName: model.libraryFilter == .liked ? "heart" : "music.note")
            .font(.system(size: 24))
            .foregroundStyle(FlowtonePalette.signal)
          Text(
            model.libraryFilter == .liked
              ? "Пока нет любимых записей" : "Здесь появятся записи станции"
          )
          .font(.system(size: 15, weight: .medium, design: .serif))
          .foregroundStyle(FlowtonePalette.ink)
          Text(
            model.libraryFilter == .liked
              ? "Нажмите сердце у трека, который хотите сохранить"
              : "Создайте первую запись на главном экране"
          )
          .font(.system(size: 11, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 1) {
            ForEach(visibleTracks) { track in
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
      Button {
        model.playTrack(trackID: track.id)
      } label: {
        Image(systemName: track.id == model.currentTrackID ? "waveform" : "play.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(
            track.id == model.currentTrackID ? FlowtonePalette.selectedInk : FlowtonePalette.ink
          )
          .frame(width: 32, height: 32)
          .background(
            track.id == model.currentTrackID ? FlowtonePalette.signal : FlowtonePalette.panel,
            in: Circle()
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Запустить трек: \(track.title)")

      VStack(alignment: .leading, spacing: 3) {
        Text(track.title)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.ink)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
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
    .frame(minHeight: 58)
    .background(track.id == model.currentTrackID ? FlowtonePalette.panel.opacity(0.72) : .clear)
  }
}

private struct VinylBroadcastVisual: View {
  let isSpinning: Bool
  let isPlaying: Bool
  let isScrubbing: Bool
  let genreTitle: String
  let progress: Double
  let positionSeconds: TimeInterval
  let durationSeconds: TimeInterval
  let hasTrack: Bool
  let onScrubBegan: () -> Void
  let onScrubChanged: (TimeInterval, AudioScrubDirection) -> Void
  let onScrubEnded: () -> Void

  @State private var lastDragAngle: Double?
  @State private var dragPosition: TimeInterval = 0
  @State private var dragVisualAngle: Double = 0
  @State private var visualPhaseOffset: Double = 0
  @State private var isHovered = false

  var body: some View {
    GeometryReader { proxy in
      let recordDiameter = min(proxy.size.height - 12, 258)
      let recordCenter = CGPoint(x: proxy.size.width * 0.4, y: proxy.size.height * 0.5)
      let displayedAngle =
        lastDragAngle == nil ? positionSeconds * 18 + visualPhaseOffset : dragVisualAngle

      ZStack {
        VinylRecord(
          angle: displayedAngle,
          genreTitle: genreTitle
        )
        .frame(width: recordDiameter, height: recordDiameter)
        .contentShape(Circle())
        .position(recordCenter)
        .gesture(vinylGesture(recordDiameter: recordDiameter))
        .onHover { isHovered = $0 }

        GramophoneToneArm(
          grooveProgress: progress,
          isEngaged: hasTrack,
          isScrubbing: isScrubbing,
          recordCenter: recordCenter,
          recordRadius: recordDiameter / 2
        )

        Text(isScrubbing ? "СКРЕТЧ" : "ПОВЕРНИТЕ ПЛАСТИНКУ")
          .font(.system(size: 9, weight: .semibold, design: .monospaced))
          .tracking(1.3)
          .foregroundStyle(FlowtonePalette.signal.opacity(isHovered || isScrubbing ? 1 : 0.56))
          .padding(.horizontal, 9)
          .padding(.vertical, 4)
          .background(FlowtonePalette.canvas.opacity(0.82), in: Capsule())
          .position(x: recordCenter.x, y: proxy.size.height - 16)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      isScrubbing
        ? "Скретч пластинки, жанр \(genreTitle)"
        : (isSpinning
          ? "Пластинка вращается, жанр \(genreTitle)"
          : "Пластинка остановлена, жанр \(genreTitle)")
    )
    .accessibilityHint("Вращайте пластинку мышью, чтобы перематывать трек и создавать скретчи")
  }

  private func vinylGesture(recordDiameter: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let center = CGPoint(x: recordDiameter / 2, y: recordDiameter / 2)
        let angle = atan2(value.location.y - center.y, value.location.x - center.x)

        guard let previousAngle = lastDragAngle else {
          dragPosition = positionSeconds
          dragVisualAngle = positionSeconds * 18 + visualPhaseOffset
          lastDragAngle = angle
          onScrubBegan()
          return
        }

        var delta = angle - previousAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        let target = min(max(dragPosition + delta / (2 * .pi) * 8, 0), durationSeconds)
        let direction: AudioScrubDirection = delta >= 0 ? .forward : .backward
        dragPosition = target
        dragVisualAngle += delta * 180 / .pi
        lastDragAngle = angle
        onScrubChanged(target, direction)
      }
      .onEnded { _ in
        visualPhaseOffset = dragVisualAngle - dragPosition * 18
        lastDragAngle = nil
        onScrubEnded()
      }
  }
}

private struct GramophoneToneArm: View {
  let grooveProgress: Double
  let isEngaged: Bool
  let isScrubbing: Bool
  let recordCenter: CGPoint
  let recordRadius: CGFloat

  var body: some View {
    Canvas { context, size in
      let pivot = CGPoint(x: size.width * 0.87, y: size.height * 0.13)
      let progress = min(max(grooveProgress, 0), 1)
      let grooveRadius = recordRadius * (0.79 - progress * 0.43)
      let grooveAngle = (-24 + progress * 7) * .pi / 180
      let engagedPoint = CGPoint(
        x: recordCenter.x + cos(grooveAngle) * grooveRadius,
        y: recordCenter.y + sin(grooveAngle) * grooveRadius
      )
      let stylus =
        isEngaged
        ? engagedPoint
        : CGPoint(x: pivot.x - recordRadius * 0.12, y: pivot.y + recordRadius * 0.86)

      var shadow = Path()
      shadow.move(to: CGPoint(x: pivot.x + 3, y: pivot.y + 5))
      shadow.addLine(to: CGPoint(x: stylus.x + 3, y: stylus.y + 5))
      context.stroke(shadow, with: .color(.black.opacity(0.46)), lineWidth: 10)

      var arm = Path()
      arm.move(to: pivot)
      arm.addLine(to: stylus)
      context.stroke(
        arm,
        with: .linearGradient(
          Gradient(colors: [FlowtonePalette.ink.opacity(0.88), FlowtonePalette.copper]),
          startPoint: pivot,
          endPoint: stylus
        ),
        style: StrokeStyle(lineWidth: 7, lineCap: .round)
      )

      context.fill(
        Path(ellipseIn: CGRect(x: pivot.x - 23, y: pivot.y - 23, width: 46, height: 46)),
        with: .color(FlowtonePalette.panelWarm)
      )
      context.stroke(
        Path(ellipseIn: CGRect(x: pivot.x - 23, y: pivot.y - 23, width: 46, height: 46)),
        with: .color(FlowtonePalette.copper),
        lineWidth: 2
      )
      context.fill(
        Path(
          roundedRect: CGRect(x: stylus.x - 13, y: stylus.y - 7, width: 26, height: 14),
          cornerRadius: 4),
        with: .color(FlowtonePalette.signal)
      )
      context.fill(
        Path(ellipseIn: CGRect(x: stylus.x - 3, y: stylus.y - 3, width: 6, height: 6)),
        with: .color(FlowtonePalette.ink)
      )
    }
    .animation(
      isScrubbing ? nil : .spring(response: 0.58, dampingFraction: 0.82),
      value: grooveProgress
    )
    .allowsHitTesting(false)
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
