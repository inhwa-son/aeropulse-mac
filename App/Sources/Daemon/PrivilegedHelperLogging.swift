import Foundation

func helperDebugLog(_ message: String) {
    guard FileManager.default.fileExists(atPath: "/tmp/.aeropulse-debug") else { return }

    let line = "[AeroPulseHelper] \(message)\n"
    let data = Data(line.utf8)
    FileHandle.standardError.write(data)

    let logURL = URL(fileURLWithPath: "/tmp/aeropulse-helper.log")
    if let handle = try? FileHandle(forWritingTo: logURL) {
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: logURL, options: .atomic)
    }
}
