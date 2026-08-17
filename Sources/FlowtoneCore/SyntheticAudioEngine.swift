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

    let task = Task.detached(priority: .utility) {
      try Self.render(request: request)
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
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
    let partialURL = fileURL.appendingPathExtension("partial")

    let sampleRate = 44_100
    let channelCount = 2
    let bitsPerSample = 16
    let frameCount = sampleRate * request.durationSeconds
    let dataByteCount = frameCount * channelCount * bitsPerSample / 8

    let baseFrequency = 110.0 + Double(request.seed % 5) * 27.5
    let fadeFrames = min(sampleRate * 2, frameCount / 3)

    try? fileManager.removeItem(at: partialURL)
    try? fileManager.removeItem(at: fileURL)
    guard fileManager.createFile(atPath: partialURL.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }

    do {
      let handle = try FileHandle(forWritingTo: partialURL)
      defer { try? handle.close() }

      var header = Data(capacity: 44)
      header.appendASCII("RIFF")
      header.appendLittleEndian(UInt32(36 + dataByteCount))
      header.appendASCII("WAVE")
      header.appendASCII("fmt ")
      header.appendLittleEndian(UInt32(16))
      header.appendLittleEndian(UInt16(1))
      header.appendLittleEndian(UInt16(channelCount))
      header.appendLittleEndian(UInt32(sampleRate))
      header.appendLittleEndian(UInt32(sampleRate * channelCount * bitsPerSample / 8))
      header.appendLittleEndian(UInt16(channelCount * bitsPerSample / 8))
      header.appendLittleEndian(UInt16(bitsPerSample))
      header.appendASCII("data")
      header.appendLittleEndian(UInt32(dataByteCount))
      try handle.write(contentsOf: header)

      let framesPerChunk = 4_096
      var frame = 0
      while frame < frameCount {
        try Task.checkCancellation()
        let upperBound = min(frame + framesPerChunk, frameCount)
        var chunk = Data(capacity: (upperBound - frame) * channelCount * 2)
        for currentFrame in frame..<upperBound {
          let time = Double(currentFrame) / Double(sampleRate)
          let fadeIn = min(1, Double(currentFrame) / Double(max(1, fadeFrames)))
          let fadeOut = min(1, Double(frameCount - currentFrame) / Double(max(1, fadeFrames)))
          let envelope = min(fadeIn, fadeOut)
          let slowPulse = 0.72 + 0.28 * sin(2 * Double.pi * 0.08 * time)
          let left =
            sin(2 * Double.pi * baseFrequency * time)
            + 0.45 * sin(2 * Double.pi * baseFrequency * 1.5 * time)
          let right =
            sin(2 * Double.pi * baseFrequency * 1.003 * time)
            + 0.45 * sin(2 * Double.pi * baseFrequency * 1.498 * time)
          let amplitude = 0.16 * envelope * slowPulse

          chunk.appendLittleEndian(
            Int16(clamping: Int(left * amplitude * Double(Int16.max))))
          chunk.appendLittleEndian(
            Int16(clamping: Int(right * amplitude * Double(Int16.max))))
        }
        try handle.write(contentsOf: chunk)
        frame = upperBound
      }
      try handle.synchronize()
    } catch {
      try? fileManager.removeItem(at: partialURL)
      throw error
    }

    try fileManager.moveItem(at: partialURL, to: fileURL)
    let byteSize = Int64(44 + dataByteCount)

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
