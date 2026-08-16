import FlowtoneCore
import Foundation

@main
struct FlowtoneSpike {
  static func main() async {
    do {
      let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
      if options.showHardware {
        printHardware()
        return
      }

      let engine: any GenerationEngine
      switch options.engine {
      case .synthetic:
        engine = SyntheticAudioEngine()
      case .stableAudio:
        guard let executableURL = options.stableAudioExecutable else {
          throw SpikeError.missingStableAudioExecutable
        }
        engine = StableAudioMLXEngine(executableURL: executableURL)
      }

      let configuration = StationConfiguration(
        genres: options.genres,
        energy: .calm,
        tempoBPM: options.tempoBPM,
        mood: .focused,
        vibe: options.vibe
      )
      let scheduler = GenerationScheduler(engine: engine)
      let result = try await scheduler.generateNext(
        configuration: configuration,
        durationSeconds: options.durationSeconds,
        seed: options.seed,
        outputDirectory: options.outputDirectory,
        resources: ResourceSnapshot(
          thermalState: .nominal,
          memoryPressure: .normal,
          lowPowerModeEnabled: false
        )
      )

      guard let result else {
        throw SpikeError.generationDeferred
      }

      print("engine=\(result.engineID)")
      print("output=\(result.fileURL.path)")
      print("duration_seconds=\(result.durationSeconds)")
      print("elapsed_seconds=\(String(format: "%.3f", result.elapsedSeconds))")
      print("bytes=\(result.byteSize)")
      print("seed=\(result.seed)")
    } catch {
      FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }

  private static func printHardware() {
    let hardware = HardwareProfile.current
    let recommendation = ModelRecommender().recommendation(for: hardware)
    print("apple_silicon=\(hardware.isAppleSilicon)")
    print("memory_gib=\(hardware.memoryGiB)")
    print("recommendation=\(String(describing: recommendation))")
  }
}

private struct Options {
  enum Engine: String {
    case synthetic
    case stableAudio = "stable-audio"
  }

  var engine: Engine = .synthetic
  var durationSeconds = 5
  var seed: UInt64 = 42
  var outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("GeneratedAudio", isDirectory: true)
  var stableAudioExecutable: URL?
  var genres = ["ambient", "lo-fi"]
  var tempoBPM = 82
  var vibe: String?
  var showHardware = false

  init(arguments: [String]) throws {
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--hardware":
        showHardware = true
      case "--engine":
        engine = try Engine(rawValue: value(after: &index, in: arguments))
          .orThrow(SpikeError.invalidEngine)
      case "--duration":
        durationSeconds = try Int(value(after: &index, in: arguments))
          .orThrow(SpikeError.invalidNumber("duration"))
      case "--seed":
        seed = try UInt64(value(after: &index, in: arguments))
          .orThrow(SpikeError.invalidNumber("seed"))
      case "--output":
        outputDirectory = URL(fileURLWithPath: try value(after: &index, in: arguments))
      case "--sa3-executable":
        stableAudioExecutable = URL(fileURLWithPath: try value(after: &index, in: arguments))
      case "--genres":
        genres = try value(after: &index, in: arguments)
          .split(separator: ",")
          .map(String.init)
      case "--tempo":
        tempoBPM = try Int(value(after: &index, in: arguments))
          .orThrow(SpikeError.invalidNumber("tempo"))
      case "--vibe":
        vibe = try value(after: &index, in: arguments)
      case "--help", "-h":
        print(Self.help)
        exit(0)
      default:
        throw SpikeError.unknownArgument(argument)
      }
      index += 1
    }
  }

  private func value(after index: inout Int, in arguments: [String]) throws -> String {
    index += 1
    guard index < arguments.count else {
      throw SpikeError.missingValue(arguments[index - 1])
    }
    return arguments[index]
  }

  static let help = """
    Usage: flowtone-spike [options]

      --hardware                       Print current hardware recommendation
      --engine synthetic|stable-audio Select generation engine
      --duration SECONDS               Clip duration (1...120, default 5)
      --seed NUMBER                    Reproducible seed (default 42)
      --output DIRECTORY               Output directory
      --genres LIST                    Comma-separated genres
      --tempo BPM                      Tempo (40...220)
      --vibe TEXT                      Optional vibe
      --sa3-executable PATH            Path to official optimized/mlx/sa3 wrapper
    """
}

private enum SpikeError: LocalizedError {
  case missingStableAudioExecutable
  case invalidEngine
  case invalidNumber(String)
  case missingValue(String)
  case unknownArgument(String)
  case generationDeferred

  var errorDescription: String? {
    switch self {
    case .missingStableAudioExecutable:
      "--sa3-executable is required for the stable-audio engine."
    case .invalidEngine:
      "Engine must be synthetic or stable-audio."
    case .invalidNumber(let name):
      "Invalid numeric value for \(name)."
    case .missingValue(let argument):
      "Missing value after \(argument)."
    case .unknownArgument(let argument):
      "Unknown argument: \(argument). Use --help."
    case .generationDeferred:
      "Generation was deferred by resource policy."
    }
  }
}

extension Optional {
  fileprivate func orThrow(_ error: @autoclosure () -> any Error) throws -> Wrapped {
    guard let value = self else { throw error() }
    return value
  }
}
