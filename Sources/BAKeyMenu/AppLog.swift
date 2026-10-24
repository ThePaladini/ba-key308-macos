import Foundation

/// Small diagnostic log at ~/Library/Logs/BA-KEY Menu.log: connections, errors and Mac-effect
/// start/stop, so field problems (e.g. over the 2.4G receiver) can be traced without a debugger.
/// Rotates at 1 MB. Never logs key presses.
enum AppLog {
    private static let queue = DispatchQueue(label: "BAKeyMenu.log")
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BA-KEY Menu.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
                try? fm.removeItem(at: url.deletingPathExtension().appendingPathExtension("old.log"))
                try? fm.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("old.log"))
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        }
    }
}
