import AppKit
import Combine
import FlowtoneCore
import SwiftUI

struct FlowtoneRootView: View {
  @ObservedObject var model: FlowtoneAppModel
  @State private var isWindowVisible = true
  @State private var windowSize = CGSize(width: 1_080, height: 720)
  private let playbackPulse = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

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

      GeometryReader { proxy in
        let sidebarWidth = min(max(proxy.size.width * 0.3, 300), 370)

        HStack(spacing: 0) {
          StationControls(model: model)
            .frame(width: sidebarWidth)

          Rectangle()
            .fill(FlowtonePalette.line)
            .frame(width: 1)

          NowPlayingStage(
            model: model,
            isWindowVisible: isWindowVisible,
            availableWindowSize: windowSize
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .sheet(isPresented: $model.isLibraryPresented) {
      TrackLibraryView(model: model, availableWindowSize: windowSize)
    }
    .alert("Хранилище Flowtone заполнено", isPresented: $model.isStorageLimitAlertPresented) {
      Button("Открыть архив") { model.showLibrary(filter: .all) }
      Button("Понятно", role: .cancel) {}
    } message: {
      Text(model.storageLimitAlertMessage)
    }
    .confirmationDialog(
      "Удалить текущий трек?",
      isPresented: $model.isCurrentDeleteConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("Удалить безвозвратно", role: .destructive) {
        model.confirmCurrentTrackDeletion()
      }
      Button("Отмена", role: .cancel) {}
    } message: {
      Text(model.currentDeleteConfirmationMessage)
    }
    .background {
      WindowVisibilityObserver(
        onVisibilityChange: { isWindowVisible = $0 },
        onSizeChange: { windowSize = $0 }
      )
      .frame(width: 0, height: 0)
    }
    .onReceive(playbackPulse) { _ in
      model.updatePlayback(publishUI: isWindowVisible)
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
            .minimumScaleFactor(0.78)

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

        controlSection("Режим эфира") {
          Picker("Режим эфира", selection: $model.storageMode) {
            ForEach(RadioStorageMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .tint(FlowtonePalette.signal)

          Text(model.storageMode.explanation)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(FlowtonePalette.muted)

          Toggle("Перемешивать треки", isOn: $model.shuffleEnabled)
            .toggleStyle(.switch)
            .tint(FlowtonePalette.signal)

          Text(
            model.shuffleEnabled
              ? "Записи из коллекции играют в случайном порядке без близких повторов"
              : "Записи играются от давно не звучавших к более недавним"
          )
          .font(.system(size: 10, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
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

          Toggle("Микс жанров", isOn: $model.mixGenresEnabled)
            .toggleStyle(.switch)
            .tint(FlowtonePalette.signal)
            .disabled(!model.canMixGenres)

          Text(
            model.canMixGenres
              ? "Flowtone сам сочетает несколько активных жанров в новом треке"
              : "Для микса выберите минимум два жанра"
          )
          .font(.system(size: 10, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
        }

        controlSection("Темп эфира") {
          Picker("Темп эфира", selection: $model.energy) {
            Text("Спокойно").tag(EnergyLevel.calm)
            Text("Ровно").tag(EnergyLevel.balanced)
            Text("Энергично").tag(EnergyLevel.driving)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .tint(FlowtonePalette.signal)

          Text(energyExplanation)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(FlowtonePalette.muted)
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

          Text(moodExplanation)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(FlowtonePalette.muted)
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

        Text(
          model.generationEnabled
            ? "Flowtone создаёт по одному треку в фоне"
            : "Генерация остановлена, процесс модели завершён и память освобождена"
        )
        .font(.system(size: 10, design: .rounded))
        .foregroundStyle(FlowtonePalette.muted)

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

  private var energyExplanation: String {
    switch model.energy {
    case .calm:
      "Мягкое звучание и сдержанный ритм без резких перепадов"
    case .balanced:
      "Уверенное ровное движение с живыми, но не резкими поворотами"
    case .driving:
      "Бодрящий темп, сильная ритм-секция и более яркие кульминации"
    }
  }

  private var moodExplanation: String {
    switch model.mood {
    case .focused:
      "Сдержанная атмосфера, которая не отвлекает от работы"
    case .warm:
      "Уютные тембры и мягкая, спокойная гармония"
    case .dreamy:
      "Воздушное, мечтательное звучание с большим пространством"
    case .dark:
      "Мрачная окраска, минорная гармония и более глубокие тембры"
    case .uplifting:
      "Светлая гармония и ощущение подъёма без лишней суеты"
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
  let isWindowVisible: Bool
  let availableWindowSize: CGSize
  @State private var isModelSetupPresented = false

  var body: some View {
    GeometryReader { proxy in
      let compact = proxy.size.height < 720
      let horizontalPadding = compact ? 18.0 : 28.0
      let vinylHeight = min(max(proxy.size.height * 0.42, 230), 470)
      let vinylWidth = min(max(proxy.size.width - horizontalPadding * 2, 460), 980)

      VStack(spacing: 0) {
        HStack(spacing: 14) {
          modelBadge
          Spacer(minLength: 8)
          libraryBadge
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, compact ? 14 : 24)
        .padding(.bottom, compact ? 6 : 12)

        Spacer(minLength: 0)

        VinylBroadcastVisual(
          isSpinning: isWindowVisible && (model.isPlaying || model.isScrubbing),
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
        .frame(width: vinylWidth, height: vinylHeight)

        VStack(spacing: compact ? 5 : 8) {
          Text(model.isGenerating ? "СОЗДАЁТСЯ НОВАЯ ЗАПИСЬ" : "СЕЙЧАС В ЭФИРЕ")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(FlowtonePalette.signal)

          MarqueeTrackTitle(
            title: model.currentTrackTitle,
            isPlaying: model.isPlaying && isWindowVisible
          )
          .frame(maxWidth: 610, minHeight: compact ? 34 : 42)

          Text(model.statusText)
            .font(.system(size: 12, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .multilineTextAlignment(.center)
            .foregroundStyle(FlowtonePalette.muted)
            .frame(maxWidth: 430, minHeight: compact ? 16 : 20)
        }
        .padding(.horizontal, horizontalPadding)

        PlaybackConsole(model: model)
          .frame(maxWidth: 650)
          .padding(.horizontal, horizontalPadding)
          .padding(.top, compact ? 6 : 12)

        Spacer(minLength: compact ? 4 : 10)

        HStack(spacing: 10) {
          Label(
            model.storageMode == .live
              ? "Временные треки удаляются автоматически"
              : "Записи остаются на этом Mac",
            systemImage: model.storageMode == .live ? "clock.arrow.circlepath" : "lock.fill"
          )
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          Spacer()
          Text("\(model.hardware.memoryGiB) ГБ памяти")
            .fixedSize()
        }
        .font(.system(size: compact ? 9 : 11, design: .monospaced))
        .foregroundStyle(FlowtonePalette.muted)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, compact ? 12 : 20)
      }
    }
    .sheet(isPresented: $isModelSetupPresented) {
      StableAudioSetupSheet(model: model, availableWindowSize: availableWindowSize)
    }
  }

  private var modelBadge: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        isModelSetupPresented = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "cpu")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(FlowtonePalette.signal)
            .frame(width: 28, height: 28)
            .background(FlowtonePalette.signal.opacity(0.1), in: Circle())

          VStack(alignment: .leading, spacing: 3) {
            Text("МОДЕЛИ")
              .font(.system(size: 9, weight: .semibold, design: .monospaced))
              .tracking(1.1)
              .foregroundStyle(FlowtonePalette.muted)
            Text(model.selectedModelText)
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .foregroundStyle(FlowtonePalette.ink)
              .lineLimit(1)
          }

          Spacer(minLength: 4)
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(FlowtonePalette.signal)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Открыть модели. Выбрана \(model.selectedModelText)")

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

private struct WindowVisibilityObserver: NSViewRepresentable {
  let onVisibilityChange: (Bool) -> Void
  let onSizeChange: (CGSize) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onVisibilityChange: onVisibilityChange,
      onSizeChange: onSizeChange
    )
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    context.coordinator.onVisibilityChange = onVisibilityChange
    context.coordinator.onSizeChange = onSizeChange
    DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
  }

  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.detach()
  }

  @MainActor
  final class Coordinator: @unchecked Sendable {
    var onVisibilityChange: (Bool) -> Void
    var onSizeChange: (CGSize) -> Void
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(
      onVisibilityChange: @escaping (Bool) -> Void,
      onSizeChange: @escaping (CGSize) -> Void
    ) {
      self.onVisibilityChange = onVisibilityChange
      self.onSizeChange = onSizeChange
    }

    func attach(to window: NSWindow?) {
      guard let window, self.window !== window else {
        reportWindowState()
        return
      }
      detach()
      self.window = window
      let center = NotificationCenter.default
      let names: [Notification.Name] = [
        NSWindow.didChangeOcclusionStateNotification,
        NSWindow.didMiniaturizeNotification,
        NSWindow.didDeminiaturizeNotification,
        NSWindow.didResizeNotification,
      ]
      observers = names.map { name in
        center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
          Task { @MainActor [weak self] in self?.reportWindowState() }
        }
      }
      reportWindowState()
    }

    func detach() {
      let center = NotificationCenter.default
      observers.forEach(center.removeObserver)
      observers.removeAll()
      window = nil
    }

    private func reportWindowState() {
      guard let window else {
        onVisibilityChange(false)
        return
      }
      onVisibilityChange(window.occlusionState.contains(.visible) && !window.isMiniaturized)
      onSizeChange(window.frame.size)
    }
  }
}

private struct MarqueeTrackTitle: View {
  let title: String
  let isPlaying: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var textWidth: CGFloat = 0
  @State private var marqueeStartedAt = Date()

  var body: some View {
    GeometryReader { proxy in
      let availableWidth = proxy.size.width
      let needsMarquee = textWidth > availableWidth
      let gap = 56.0
      let cycleWidth = max(textWidth + gap, 1)
      let speed = 23.0
      let openingHold = 1.5
      let closingHold = 0.7
      let scrollDuration = cycleWidth / speed
      let totalDuration = openingHold + scrollDuration + closingHold

      TimelineView(
        .animation(
          minimumInterval: 1.0 / 15.0,
          paused: !needsMarquee || !isPlaying || reduceMotion
        )
      ) { timeline in
        let elapsed = max(0, timeline.date.timeIntervalSince(marqueeStartedAt))
        let phase = elapsed.truncatingRemainder(dividingBy: totalDuration)
        let travel =
          if phase < openingHold {
            0.0
          } else if phase < openingHold + scrollDuration {
            min((phase - openingHold) * speed, cycleWidth)
          } else {
            cycleWidth
          }
        let offset =
          needsMarquee && isPlaying && !reduceMotion
          ? -travel
          : 0

        HStack(spacing: needsMarquee ? gap : 0) {
          titleText
          if needsMarquee && isPlaying && !reduceMotion { titleText }
        }
        .frame(minWidth: availableWidth, alignment: needsMarquee ? .leading : .center)
        .offset(x: offset)
      }
      .clipped()
    }
    .frame(height: 34)
    .onAppear { marqueeStartedAt = Date() }
    .onChange(of: title) { _, _ in marqueeStartedAt = Date() }
    .onChange(of: isPlaying) { _, playing in
      if playing { marqueeStartedAt = Date() }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
  }

  private var titleText: some View {
    Text(title)
      .font(.system(size: 23, weight: .medium, design: .serif))
      .foregroundStyle(FlowtonePalette.ink)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .background {
        GeometryReader { proxy in
          Color.clear
            .onAppear { textWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in textWidth = width }
        }
      }
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

        Button(action: model.requestCurrentTrackDeletion) {
          Image(systemName: "trash")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FlowtonePalette.muted)
            .frame(width: 40, height: 40)
            .background(FlowtonePalette.panel, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.currentTrack == nil)
        .accessibilityLabel("Удалить текущий трек")
        .help("Удалить текущий трек с подтверждением")

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

struct StableAudioSetupSheet: View {
  @ObservedObject var model: FlowtoneAppModel
  var availableWindowSize = CGSize(width: 1_080, height: 720)
  @Environment(\.dismiss) private var dismiss
  @State private var pendingRemoval: MusicModelID?
  @State private var confirmsRemoval = false
  @FocusState private var closeButtonFocused: Bool

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [FlowtonePalette.canvasTop, FlowtonePalette.canvas, FlowtonePalette.canvasBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        FlowtoneSheetHeader(
          eyebrow: "ЛОКАЛЬНАЯ ГЕНЕРАЦИЯ",
          title: "Модели",
          subtitle: nil,
          closeAccessibilityLabel: "Закрыть настройку модели",
          close: { dismiss() }
        )
        .focused($closeButtonFocused)

        ScrollView {
          StableAudioSetupGate(
            model: model,
            requestRemoval: { modelID in
              pendingRemoval = modelID
              confirmsRemoval = true
            }
          )
          .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultScrollAnchor(.top)
        .onAppear { closeButtonFocused = true }
        .accessibilityLabel("Управление локальными моделями")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .flowtoneSheetSurface(availableSize: availableWindowSize)
    .alert(
      "Удалить модель с устройства?",
      isPresented: $confirmsRemoval,
      presenting: pendingRemoval
    ) { modelID in
      Button("Удалить", role: .destructive) {
        model.removeModel(modelID)
        pendingRemoval = nil
      }
      Button("Отмена", role: .cancel) { pendingRemoval = nil }
    } message: { modelID in
      Text(
        "\(model.modelName(for: modelID)) и её веса будут удалены. Локальные треки останутся. Flowtone автоматически подключит другую установленную модель."
      )
    }
  }
}

private struct StableAudioSetupGate: View {
  @ObservedObject var model: FlowtoneAppModel
  let requestRemoval: (MusicModelID) -> Void
  @State private var showsTermsReminder = false

  private static let repositoryURL = URL(string: "https://github.com/Stability-AI/stable-audio-3")!
  private static let modelCardURL = URL(
    string: "https://huggingface.co/stabilityai/stable-audio-3-small-music")!
  private static let optimizedModelURL = URL(
    string: "https://huggingface.co/stabilityai/stable-audio-3-optimized")!
  private static let licenseURL = URL(string: "https://stability.ai/license")!
  private static let gemmaTermsURL = URL(string: "https://ai.google.dev/gemma/terms")!
  private static let aceStepURL = URL(string: "https://github.com/ace-step/ACE-Step-1.5")!

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      selectionSection

      VStack(alignment: .leading, spacing: 9) {
        Text("ОФИЦИАЛЬНЫЕ УСЛОВИЯ")
          .font(.system(size: 9, weight: .semibold, design: .monospaced))
          .tracking(0.8)
          .foregroundStyle(FlowtonePalette.signal)

        Text(
          "Код Flowtone распространяется отдельно от весов Stable Audio и ACE-Step. Откройте официальные страницы и лично примите применимые условия."
        )
        .font(.system(size: 10, design: .rounded))
        .foregroundStyle(FlowtonePalette.muted)
        .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 7) {
          officialPageButton("Модель", url: Self.modelCardURL)
          officialPageButton("MLX-набор", url: Self.optimizedModelURL)
          officialPageButton("Лицензия", url: Self.licenseURL)
        }
        HStack(spacing: 7) {
          officialPageButton("Условия Gemma", url: Self.gemmaTermsURL)
          officialPageButton("Исходный код", url: Self.repositoryURL)
          officialPageButton("ACE-Step", url: Self.aceStepURL)
        }

        if model.hasAcknowledgedStableAudioTerms {
          Label("Прочтение условий подтверждено на этом Mac", systemImage: "checkmark.circle.fill")
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(FlowtonePalette.muted)
        } else {
          Button(action: model.acknowledgeStableAudioTermsRead) {
            Label(
              "Подтвердить: я лично открыл(а) и прочитал(а) официальные условия",
              systemImage: "checkmark.shield"
            )
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.roundedRectangle(radius: 10))
          .controlSize(.large)
          .tint(FlowtonePalette.signal)
          .accessibilityHint(model.stableAudioTermsAcknowledgementText)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(FlowtonePalette.panel.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(FlowtonePalette.line) }

      Text("ВЕРСИИ ПО МОЩНОСТИ")
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(FlowtonePalette.signal)

      ForEach(HardwareModelGroup.allCases) { group in
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
              Text(group.title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(FlowtonePalette.ink)
              Text(group.requirement)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(FlowtonePalette.muted)
            }
            Spacer()
            if model.hardware.modelGroup == group { statusPill("ЭТОТ MAC") }
          }

          ForEach(group.modelIDs, id: \.self) { modelID in
            modelCard(
              MusicModelProfile.profile(for: modelID),
              baselineID: group.baselineID
            )
          }
        }
        .padding(.top, 4)
      }

      if let error = model.stableAudioInstallationErrorText {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 10, design: .rounded))
          .foregroundStyle(FlowtonePalette.signal)
          .fixedSize(horizontal: false, vertical: true)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(FlowtonePalette.signal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      }

      DisclosureGroup("Где хранятся модели") {
        Text(model.modelRuntimePaths)
          .font(.system(size: 8, design: .monospaced))
          .textSelection(.enabled)
          .foregroundStyle(FlowtonePalette.muted)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 5)
      }
      .font(.system(size: 9, design: .rounded))
      .tint(FlowtonePalette.signal)
    }
    .padding(.top, 2)
    .alert("Сначала подтвердите чтение условий", isPresented: $showsTermsReminder) {
      Button("Понятно", role: .cancel) {}
    } message: {
      Text(
        "Откройте официальные страницы выше и нажмите оранжевую кнопку подтверждения. После этого выбранная модель сразу начнёт скачиваться."
      )
    }
  }

  private var selectionSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("ВЫБОР МОДЕЛИ")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(FlowtonePalette.signal)
          Text("Этот Mac: Apple Silicon · \(model.hardware.memoryGiB) ГБ памяти")
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(FlowtonePalette.muted)
        }
        Spacer()
        Label("Офлайн", systemImage: "wifi.slash")
          .font(.system(size: 9, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
      }

      Picker("Выбор модели", selection: $model.modelPreference) {
        Text("Автоматически · \(model.modelName(for: model.recommendedModelID))")
          .tag(ModelPreference.automatic)
        ForEach(MusicModelProfile.all) { profile in
          Text(profile.title).tag(ModelPreference(modelID: profile.id))
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .frame(maxWidth: .infinity, alignment: .leading)

      Text(
        "Автоподбор рекомендует \(model.modelName(for: model.recommendedModelID)). Если она не установлена, Flowtone подключит другую доступную модель."
      )
      .font(.system(size: 10, design: .rounded))
      .foregroundStyle(FlowtonePalette.muted)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .background(FlowtonePalette.panel.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(FlowtonePalette.line) }
  }

  private func modelCard(_ profile: MusicModelProfile, baselineID: MusicModelID) -> some View {
    let installed = model.isModelInstalled(profile.id)
    let connected = model.activeModelID == profile.id
    let installing = model.isInstallingStableAudio && model.installingModelID == profile.id

    return VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          Circle().stroke(FlowtonePalette.signal.opacity(0.35), lineWidth: 1)
          Circle().stroke(FlowtonePalette.signal.opacity(0.22), lineWidth: 1).padding(5)
          Circle().fill(FlowtonePalette.signal).frame(width: 5, height: 5)
        }
        .frame(width: 34, height: 34)

        VStack(alignment: .leading, spacing: 4) {
          Text(profile.title)
            .font(.system(size: 14, weight: .semibold, design: .serif))
            .foregroundStyle(FlowtonePalette.ink)
          Text(profile.summary)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(FlowtonePalette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 5) {
          if baselineID == profile.id { statusPill("БАЗОВАЯ") }
          if model.isModelRecommended(profile.id) { statusPill("АВТОВЫБОР") }
          if profile.isAmbitious { statusPill("АМБИЦИОЗНАЯ") }
          if connected { statusPill("ПОДКЛЮЧЕНА") } else if installed { statusPill("УСТАНОВЛЕНА") }
        }
      }

      VStack(alignment: .leading, spacing: 5) {
        Label(profile.betterThanBaseline, systemImage: "plus.circle.fill")
          .foregroundStyle(FlowtonePalette.ink)
        Label(profile.worseThanBaseline, systemImage: "minus.circle.fill")
          .foregroundStyle(FlowtonePalette.muted)
      }
      .font(.system(size: 9, design: .rounded))
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        setupFact(
          icon: "arrow.down.circle",
          title: "≈ \(String(format: "%.1f", profile.estimatedDownloadGiB)) ГБ",
          detail: "загрузка"
        )
        setupFact(
          icon: "memorychip",
          title: "от \(profile.minimumMemoryGiB) ГБ",
          detail: "память"
        )
        setupFact(icon: "lock.shield", title: profile.backend, detail: "локально")
      }

      if installing {
        HStack(spacing: 9) {
          ProgressView().controlSize(.small).tint(FlowtonePalette.signal)
          VStack(alignment: .leading, spacing: 2) {
            Text(model.stableAudioInstallationTitle)
              .font(.system(size: 10, weight: .semibold, design: .rounded))
              .foregroundStyle(FlowtonePalette.ink)
            Text(model.stableAudioInstallationDetail)
              .font(.system(size: 9, design: .rounded))
              .foregroundStyle(FlowtonePalette.muted)
          }
        }
        ProgressView(value: model.stableAudioInstallationFraction)
          .tint(FlowtonePalette.signal)
        Button("Отменить установку", action: model.cancelStableAudioInstallation)
          .buttonStyle(.bordered)
          .tint(FlowtonePalette.signal)
      } else if installed {
        HStack(spacing: 8) {
          if !connected {
            Button("Подключить") { model.selectModel(profile.id) }
              .buttonStyle(.borderedProminent)
              .tint(FlowtonePalette.signal)
          }
          Button("Удалить с устройства", role: .destructive) {
            requestRemoval(profile.id)
          }
          .buttonStyle(.bordered)
          .disabled(model.isInstallingStableAudio || model.isRemovingStableAudio)
        }
      } else {
        Button {
          if model.hasAcknowledgedStableAudioTerms {
            model.installModel(profile.id)
          } else {
            showsTermsReminder = true
          }
        } label: {
          Label(
            "Установить и подключить · ≈ \(String(format: "%.1f", profile.estimatedDownloadGiB)) ГБ",
            systemImage: "arrow.down.circle.fill"
          )
          .font(.system(size: 10, weight: .semibold, design: .rounded))
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(FlowtonePalette.signal)
        .disabled(model.isInstallingStableAudio || model.isRemovingStableAudio)
        .accessibilityHint("Скачает официальную модель на этот Mac и подключит её")
      }
    }
    .padding(14)
    .background(
      connected ? FlowtonePalette.signal.opacity(0.075) : FlowtonePalette.panel.opacity(0.68),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(connected ? FlowtonePalette.signal.opacity(0.6) : FlowtonePalette.line)
    }
  }

  private func statusPill(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 7, weight: .bold, design: .monospaced))
      .tracking(0.6)
      .foregroundStyle(FlowtonePalette.signal)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(FlowtonePalette.signal.opacity(0.09), in: Capsule())
  }

  private func setupFact(icon: String, title: String, detail: String) -> some View {
    HStack(spacing: 7) {
      Image(systemName: icon)
        .foregroundStyle(FlowtonePalette.signal)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 9, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.ink)
        Text(detail)
          .font(.system(size: 8, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(9)
    .background(FlowtonePalette.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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

private enum TrackLibrarySection: String, CaseIterable, Identifiable {
  case tracks
  case statistics

  var id: Self { self }

  var title: String {
    switch self {
    case .tracks: "Треки"
    case .statistics: "Статистика"
    }
  }
}

private struct TrackLibraryView: View {
  @ObservedObject var model: FlowtoneAppModel
  let availableWindowSize: CGSize
  @Environment(\.dismiss) private var dismiss
  @State private var confirmsCleanup = false
  @State private var section: TrackLibrarySection = .tracks
  @State private var selectedGenre: String?

  private let columns = [GridItem(.flexible()), GridItem(.flexible())]

  private var visibleTracks: [TrackRecord] {
    let tracks: [TrackRecord]
    switch model.libraryFilter {
    case .all: tracks = model.tracks
    case .liked: tracks = model.tracks.filter(\.isLiked)
    }

    guard let selectedGenre else { return tracks }
    return tracks.filter { $0.genres.contains(selectedGenre) }
  }

  var body: some View {
    VStack(spacing: 0) {
      FlowtoneSheetHeader(
        eyebrow: "ЛОКАЛЬНАЯ КОЛЛЕКЦИЯ",
        title: "Архив эфира",
        subtitle: "Записи остаются на этом Mac",
        closeAccessibilityLabel: "Закрыть коллекцию",
        close: { dismiss() }
      )

      Picker("Раздел архива", selection: $section) {
        ForEach(TrackLibrarySection.allCases) { item in
          Text(item.title).tag(item)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .tint(FlowtonePalette.signal)
      .frame(maxWidth: 330)
      .padding(.horizontal, 28)
      .padding(.bottom, 16)

      Group {
        switch section {
        case .tracks:
          tracksSection
        case .statistics:
          statisticsSection
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .flowtoneSheetSurface(availableSize: availableWindowSize)
    .onAppear {
      section = .tracks
      selectedGenre = nil
    }
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

  private var tracksSection: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        Picker("Фильтр записей", selection: $model.libraryFilter) {
          ForEach(TrackLibraryFilter.allCases) { filter in
            Text(filter.title).tag(filter)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .tint(FlowtonePalette.signal)
        .frame(width: 260)

        if let selectedGenre {
          Button {
            self.selectedGenre = nil
          } label: {
            Label(model.genreDisplayName(selectedGenre), systemImage: "xmark")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(FlowtonePalette.signal)
          .accessibilityLabel("Сбросить фильтр жанра \(model.genreDisplayName(selectedGenre))")
        }

        Text(
          selectedGenre != nil
            ? "\(visibleTracks.count) треков"
            : model.libraryFilter == .liked
              ? "\(visibleTracks.count) любимых"
              : model.librarySummaryText
        )
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(FlowtonePalette.muted)

        Spacer()
      }
      .padding(.horizontal, 28)
      .padding(.bottom, 13)

      Divider().overlay(FlowtonePalette.line)

      if visibleTracks.isEmpty {
        emptyTracksState
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
        Label("Любимые защищены от очистки", systemImage: "heart.fill")
          .font(.system(size: 10, design: .rounded))
          .foregroundStyle(FlowtonePalette.muted)
        Spacer()
        Button("Удалить всё без лайка") { confirmsCleanup = true }
          .buttonStyle(.plain)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.signal)
          .disabled(model.libraryStatistics.trackCount == model.libraryStatistics.likedTrackCount)
      }
      .padding(.horizontal, 28)
      .frame(height: 54)
      .background(FlowtonePalette.sidebar)
    }
  }

  private var emptyTracksState: some View {
    VStack(spacing: 9) {
      Image(systemName: model.libraryFilter == .liked ? "heart" : "music.note")
        .font(.system(size: 24))
        .foregroundStyle(FlowtonePalette.signal)
      Text(
        selectedGenre != nil
          ? "Нет треков этого жанра"
          : model.libraryFilter == .liked
            ? "Пока нет любимых записей" : "Здесь появятся записи станции"
      )
      .font(.system(size: 15, weight: .medium, design: .serif))
      .foregroundStyle(FlowtonePalette.ink)
      Text(
        selectedGenre != nil
          ? "Сбросьте фильтр жанра над списком"
          : model.libraryFilter == .liked
            ? "Нажмите сердце у трека, который хотите сохранить"
            : "Создайте первую запись на главном экране"
      )
      .font(.system(size: 11, design: .rounded))
      .foregroundStyle(FlowtonePalette.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var statisticsSection: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
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
          storageLimitMetric
        }

        if !model.libraryStatistics.genres.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("ПО ЖАНРАМ")
              .font(.system(size: 9, weight: .semibold, design: .monospaced))
              .tracking(1)
              .foregroundStyle(FlowtonePalette.muted)

            LazyVGrid(columns: columns, spacing: 8) {
              ForEach(model.libraryStatistics.genres, id: \.genre) { item in
                Button {
                  selectedGenre = item.genre
                  model.libraryFilter = .all
                  section = .tracks
                } label: {
                  HStack {
                    Text(model.genreDisplayName(item.genre))
                    Spacer()
                    Text("\(item.trackCount) · \(model.formatBytes(item.byteSize))")
                      .foregroundStyle(FlowtonePalette.muted)
                    Image(systemName: "chevron.right")
                      .font(.system(size: 8, weight: .bold))
                      .foregroundStyle(FlowtonePalette.signal)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(FlowtonePalette.ink)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                  FlowtonePalette.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 9)
                )
                .accessibilityLabel(
                  "Показать \(item.trackCount) треков жанра \(model.genreDisplayName(item.genre))"
                )
              }
            }
          }
        }
      }
      .padding(.horizontal, 28)
      .padding(.bottom, 28)
    }
  }

  private var storageLimitMetric: some View {
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
      if model.isStoragePaused {
        Label("Новые записи приостановлены", systemImage: "exclamationmark.circle.fill")
          .font(.system(size: 9, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.signal)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(FlowtonePalette.panel, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(FlowtonePalette.line) }
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
        if track.isTransient {
          Text("ВРЕМЕННЫЙ · ЛАЙК СОХРАНИТ")
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(FlowtonePalette.signal)
        }
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

private struct SheetCloseButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("Закрыть", systemImage: "xmark")
        .labelStyle(.iconOnly)
        .frame(width: 32, height: 32)
    }
    .buttonStyle(.bordered)
    .tint(FlowtonePalette.signal)
    .focusEffectDisabled()
  }
}

private struct FlowtoneSheetHeader: View {
  let eyebrow: String
  let title: String
  let subtitle: String?
  let closeAccessibilityLabel: String
  let close: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 5) {
          Text(eyebrow)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(FlowtonePalette.signal)
          Text(title)
            .font(.system(size: 28, weight: .medium, design: .serif))
            .foregroundStyle(FlowtonePalette.ink)
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 12, design: .rounded))
              .foregroundStyle(FlowtonePalette.muted)
          } else {
            Color.clear
              .frame(height: 14)
              .accessibilityHidden(true)
          }
        }

        Spacer()

        SheetCloseButton(action: close)
          .accessibilityLabel(closeAccessibilityLabel)
          .accessibilityHint("Также можно нажать Escape")
      }
      .padding(28)

      Rectangle()
        .fill(FlowtonePalette.line)
        .frame(height: 1)
    }
  }
}

extension View {
  func flowtoneSheetSurface(availableSize: CGSize) -> some View {
    let width = min(max((availableSize.width - 300) * 0.75, 700), 780)
    let height = min(max(availableSize.height - 40, 650), 860)

    return frame(width: width, height: height)
      .background(FlowtonePalette.canvas)
      .preferredColorScheme(.dark)
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
  @State private var playbackAnchorPosition: TimeInterval = 0
  @State private var playbackAnchorDate = Date()

  var body: some View {
    GeometryReader { proxy in
      let recordDiameter = min(max(proxy.size.height - 16, 160), proxy.size.width * 0.58)
      let recordCenter = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
      TimelineView(
        .animation(
          minimumInterval: 1.0 / 60.0,
          paused: !isSpinning || isScrubbing || lastDragAngle != nil
        )
      ) { timeline in
        let elapsed = max(0, timeline.date.timeIntervalSince(playbackAnchorDate))
        let interpolatedPosition =
          isPlaying && !isScrubbing
          ? playbackAnchorPosition + elapsed
          : positionSeconds
        let smoothPosition =
          durationSeconds > 0
          ? min(max(interpolatedPosition, 0), durationSeconds)
          : max(interpolatedPosition, 0)
        let displayedAngle =
          lastDragAngle == nil ? smoothPosition * 18 + visualPhaseOffset : dragVisualAngle

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
    }
    .onAppear { resetPlaybackAnchor(to: positionSeconds) }
    .onChange(of: isPlaying) { _, _ in resetPlaybackAnchor(to: positionSeconds) }
    .onChange(of: positionSeconds) { _, position in
      let expectedPosition = playbackAnchorPosition + Date().timeIntervalSince(playbackAnchorDate)
      if !isPlaying || abs(position - expectedPosition) > 0.18 {
        resetPlaybackAnchor(to: position)
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

  private func resetPlaybackAnchor(to position: TimeInterval) {
    playbackAnchorPosition = position
    playbackAnchorDate = Date()
  }

  private func vinylGesture(recordDiameter: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let center = CGPoint(x: recordDiameter / 2, y: recordDiameter / 2)
        let horizontal = value.location.x - center.x
        let vertical = value.location.y - center.y
        let radius = hypot(horizontal, vertical)

        // atan2 becomes unstable next to the spindle and can turn a tiny pointer
        // movement into a half-record jump. Keep the last stable angle until the
        // pointer leaves that small dead zone.
        guard radius >= recordDiameter * 0.1 else { return }
        let angle = atan2(vertical, horizontal)

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

        // A single pointer event must not skip a large part of the track. Normal
        // circular dragging remains 1:1 while sparse or lost events recover
        // smoothly on the following frames.
        delta = min(max(delta, -.pi / 6), .pi / 6)
        guard abs(delta) >= 0.001 else { return }

        let target = min(max(dragPosition + delta / (2 * .pi) * 8, 0), durationSeconds)
        let direction: AudioScrubDirection = delta >= 0 ? .forward : .backward
        dragPosition = target
        dragVisualAngle += delta * 180 / .pi
        let acceptedAngle = previousAngle + delta
        lastDragAngle = atan2(sin(acceptedAngle), cos(acceptedAngle))
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
      let pivot = CGPoint(
        x: min(recordCenter.x + recordRadius * 1.08, size.width - 20),
        y: max(recordCenter.y - recordRadius * 0.52, 20)
      )
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
        : CGPoint(x: pivot.x - recordRadius * 0.18, y: pivot.y + recordRadius * 0.72)
      let pivotRadius = min(max(recordRadius * 0.085, 12), 17)
      let cartridgeWidth = min(max(recordRadius * 0.13, 20), 25)
      let cartridgeHeight = min(max(recordRadius * 0.065, 10), 13)
      let armWidth = min(max(recordRadius * 0.034, 4), 6)

      var shadow = Path()
      shadow.move(to: CGPoint(x: pivot.x + 3, y: pivot.y + 5))
      shadow.addLine(to: CGPoint(x: stylus.x + 3, y: stylus.y + 5))
      context.stroke(shadow, with: .color(.black.opacity(0.46)), lineWidth: armWidth + 3)

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
        style: StrokeStyle(lineWidth: armWidth, lineCap: .round)
      )

      context.fill(
        Path(
          ellipseIn: CGRect(
            x: pivot.x - pivotRadius,
            y: pivot.y - pivotRadius,
            width: pivotRadius * 2,
            height: pivotRadius * 2
          )),
        with: .color(FlowtonePalette.panelWarm)
      )
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: pivot.x - pivotRadius,
            y: pivot.y - pivotRadius,
            width: pivotRadius * 2,
            height: pivotRadius * 2
          )),
        with: .color(FlowtonePalette.copper),
        lineWidth: 2
      )
      context.fill(
        Path(
          roundedRect: CGRect(
            x: stylus.x - cartridgeWidth / 2,
            y: stylus.y - cartridgeHeight / 2,
            width: cartridgeWidth,
            height: cartridgeHeight
          ),
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
    GeometryReader { proxy in
      let diameter = min(proxy.size.width, proxy.size.height)
      let labelDiameter = diameter * 0.4

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

        VinylGrooveCanvas()

        Circle()
          .fill(
            AngularGradient(
              colors: [.clear, FlowtonePalette.ink.opacity(0.11), .clear, .clear],
              center: .center
            )
          )
          .blendMode(.screen)

        Circle()
          .fill(
            RadialGradient(
              colors: [FlowtonePalette.signalBright, FlowtonePalette.copper],
              center: .topLeading,
              startRadius: 3,
              endRadius: 70
            )
          )
          .frame(width: labelDiameter, height: labelDiameter)
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

        Circle()
          .fill(FlowtonePalette.canvasBottom)
          .frame(width: diameter * 0.035, height: diameter * 0.035)
          .overlay { Circle().stroke(FlowtonePalette.ink.opacity(0.4), lineWidth: 1) }
      }
      .frame(width: diameter, height: diameter)
      .rotationEffect(.degrees(angle))
      .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .shadow(color: .black.opacity(0.62), radius: 28, y: 20)
    .shadow(color: FlowtonePalette.signal.opacity(0.08), radius: 36)
  }
}

private struct VinylGrooveCanvas: View {
  var body: some View {
    Canvas { context, size in
      let diameter = min(size.width, size.height)
      let origin = CGPoint(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2)
      let scale = diameter / 258

      for index in 0..<9 {
        let inset = diameter * (0.045 + CGFloat(index) * 0.04)
        let rect = CGRect(
          x: origin.x + inset,
          y: origin.y + inset,
          width: diameter - inset * 2,
          height: diameter - inset * 2
        )
        context.stroke(
          Path(ellipseIn: rect),
          with: .color(
            FlowtonePalette.groove.opacity(0.13 + Double(index % 3) * 0.025)
          ),
          lineWidth: max(0.5, 0.55 * scale)
        )
      }

      let markerSize = CGSize(width: max(2, 3 * scale), height: 34 * scale)
      let markerRect = CGRect(
        x: size.width / 2 - markerSize.width / 2,
        y: origin.y + diameter * 0.065,
        width: markerSize.width,
        height: markerSize.height
      )
      context.fill(
        Path(roundedRect: markerRect, cornerRadius: markerSize.width / 2),
        with: .color(FlowtonePalette.signalBright.opacity(0.58))
      )
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
