import FlowtoneCore
import SwiftUI

struct FlowtoneRootView: View {
  @ObservedObject var model: FlowtoneAppModel

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

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        modelBadge
        Spacer()
        Text("ПРОТОТИП 0")
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .tracking(1.4)
          .foregroundStyle(FlowtonePalette.copper)
      }
      .padding(28)

      Spacer()

      VinylBroadcastVisual(
        isActive: model.isPlaying || model.isGenerating,
        genreTitle: model.primaryGenreDisplayName
      )
      .frame(maxWidth: 560)
      .frame(height: 320)

      VStack(spacing: 8) {
        Text(model.isGenerating ? "СОЗДАЁТСЯ НОВАЯ ЗАПИСЬ" : "СЕЙЧАС В ЭФИРЕ")
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .tracking(2)
          .foregroundStyle(FlowtonePalette.signal)

        Text(model.generatedFileURL == nil ? "Тишина перед эфиром" : "Локальная запись")
          .font(.system(size: 25, weight: .medium, design: .serif))
          .foregroundStyle(FlowtonePalette.ink)

        Text(model.statusText)
          .font(.system(size: 12, design: .rounded))
          .multilineTextAlignment(.center)
          .foregroundStyle(FlowtonePalette.muted)
          .frame(maxWidth: 390)
      }

      HStack(spacing: 14) {
        Button {
          model.togglePlayback()
        } label: {
          Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 48, height: 48)
            .background(FlowtonePalette.panel, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.generatedFileURL == nil)

        Button {
          Task { await model.generateDevelopmentPreview() }
        } label: {
          HStack(spacing: 9) {
            if model.isGenerating {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "waveform.badge.plus")
            }
            Text(model.generatedFileURL == nil ? "Создать тестовую запись" : "Следующая запись")
          }
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundStyle(FlowtonePalette.canvas)
          .padding(.horizontal, 20)
          .frame(height: 48)
          .background(FlowtonePalette.signal, in: Capsule())
          .shadow(color: FlowtonePalette.signal.opacity(0.22), radius: 18, y: 7)
        }
        .buttonStyle(.plain)
        .disabled(!model.generationEnabled || model.isGenerating)
      }
      .padding(.top, 34)

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
  }

  private var modelBadge: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("РЕКОМЕНДОВАННАЯ МОДЕЛЬ")
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1.1)
        .foregroundStyle(FlowtonePalette.muted)
      Text(model.recommendedModelText)
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
}

private struct VinylBroadcastVisual: View {
  let isActive: Bool
  let genreTitle: String

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive)) { timeline in
      let seconds = timeline.date.timeIntervalSinceReferenceDate
      ZStack {
        HStack(spacing: -8) {
          VinylRecord(
            angle: isActive ? seconds * 24 : 0,
            genreTitle: genreTitle
          )
          .frame(width: 305, height: 305)

          ToneArm(isActive: isActive)
            .frame(width: 88, height: 250)
            .offset(y: -6)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      isActive
        ? "Пластинка вращается, жанр \(genreTitle)"
        : "Пластинка остановлена, жанр \(genreTitle)"
    )
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

  var body: some View {
    ZStack(alignment: .top) {
      Circle()
        .fill(FlowtonePalette.panelWarm)
        .frame(width: 42, height: 42)
        .overlay { Circle().stroke(FlowtonePalette.copper, lineWidth: 2) }

      Capsule()
        .fill(
          LinearGradient(
            colors: [FlowtonePalette.ink.opacity(0.82), FlowtonePalette.copper],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .frame(width: 8, height: 184)
        .rotationEffect(.degrees(isActive ? 14 : 3), anchor: .top)
        .offset(y: 26)
        .animation(.spring(response: 0.7, dampingFraction: 0.72), value: isActive)

      RoundedRectangle(cornerRadius: 3)
        .fill(FlowtonePalette.signal)
        .frame(width: 25, height: 14)
        .rotationEffect(.degrees(isActive ? 14 : 3))
        .offset(x: isActive ? 43 : 10, y: 208)
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
