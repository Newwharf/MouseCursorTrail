//
// AppLogger.swift
// MVC: 基础服务（日志）
//
import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.lihan.rainbowcursor.logger", qos: .utility)
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let logsDirectoryURL: URL
    private let logFileURL: URL
    private var isEnabled = true

    private init() {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        logsDirectoryURL = base.appendingPathComponent("Logs/RainbowCursor", isDirectory: true)
        logFileURL = logsDirectoryURL.appendingPathComponent("app.log")
        queue.async { [logsDirectoryURL] in
            try? FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        queue.async {
            if self.isEnabled == enabled {
                return
            }
            self.isEnabled = enabled
            self.write("logger \(enabled ? "enabled" : "disabled")", force: true)
        }
    }

    func log(_ message: String) {
        queue.async {
            self.write(message, force: false)
        }
    }

    func logPath() -> String {
        logFileURL.path
    }

    private func write(_ message: String, force: Bool) {
        guard force || isEnabled else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if
                let handle = try? FileHandle(forWritingTo: logFileURL)
            {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            }
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
}
