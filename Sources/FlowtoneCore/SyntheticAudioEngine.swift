import Foundation

public struct SyntheticAudioEngine: GenerationEngine {
  public let descriptor = EngineDescriptor(
    id: "synthetic-dev",
    displayName: "Synthetic development engine",
    tier: .light,
    isDevelopmentOnly: true
  )

  public init() {}

  public func generate(_ request: GenerationRequest) async throws -> GeneratedAudio {
    guard (1...120).contains(request.durationSeconds) else {
      throw GenerationEngineError.invalidDuration(request.durationSeconds)
    }

    return try await Task.detached(priority: .utility) {
      try Self.render(request: request)
    }.value
  }

  private static func render(request: GenerationRequest) throws -> GeneratedAudio {
    let startedAt = Date()
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: request.outputDirectory,
      withIntermediateDirectories: true
    )

    let fileURL = request.outputDirectory
      .appendingPathComponent("flowtone-\(request.seed).wav")

    let sampleRate = 44_100
    let channelCount = 2
    let bitsPerSample = 16
    let frameCount = sampleRate * request.durationSeconds
    let dataByteCount = frameCount * channelCount * bitsPerSample / 8

    var data = Data(capacity: 44 + dataByteCount)
    data.appendASCII("RIFF")
    data.appendLittleEndian(UInt32(36 + dataByteCount))
    data.appendASCII("WAVE")
    data.appendASCII("fmt ")
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt16(channelCount))
    data.appendLittleEndian(UInt32(sampleRate))
    data.appendLittleEndian(UInt32(sampleRate * channelCount * bitsPerSample / 8))
    data.appendLittleEndian(UInt16(channelCount * bitsPerSample / 8))
    data.appendLittleEndian(UInt16(bitsPerSample))
    data.appendASCII("data")
    data.appendLittleEndian(UInt32(dataByteCount))

    let baseFrequency = 110.0 + Double(request.seed % 5) * 27.5
    let fadeFrames = min(sampleRate * 2, frameCount / 3)

    for frame in 0..<frameCount {
      let time = Double(frame) / Double(sampleRate)
      let fadeIn = min(1, Double(frame) / Double(max(1, fadeFrames)))
      let fadeOut = min(1, Double(frameCount - frame) / Double(max(1, fadeFrames)))
      let envelope = min(fadeIn, fadeOut)
      let slowPulse = 0.72 + 0.28 * sin(2 * Double.pi * 0.08 * time)
      let left =
        sin(2 * Double.pi * baseFrequency * time)
        + 0.45 * sin(2 * Double.pi * baseFrequency * 1.5 * time)
      let right =
        sin(2 * Double.pi * baseFrequency * 1.003 * time)
        + 0.45 * sin(2 * Double.pi * baseFrequency * 1.498 * time)
      let amplitude = 0.16 * envelope * slowPulse

      data.appendLittleEndian(Int16(clamping: Int(left * amplitude * Double(Int16.max))))
      data.appendLittleEndian(Int16(clamping: Int(right * amplitude * Double(Int16.max))))
    }

    try data.write(to: fileURL, options: .atomic)
    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
    let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? Int64(data.count)

    return GeneratedAudio(
      fileURL: fileURL,
      durationSeconds: request.durationSeconds,
      byteSize: byteSize,
      engineID: "synthetic-dev",
      elapsedSeconds: Date().timeIntervalSince(startedAt),
      seed: request.seed
    )
  }
}

extension Data {
  fileprivate mutating func appendASCII(_ value: String) {
    append(contentsOf: value.utf8)
  }

  fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { bytes in
      append(contentsOf: bytes)
    }
  }
}
