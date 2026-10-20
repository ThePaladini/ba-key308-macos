import CoreGraphics

/// A cell of the firmware's LED matrix (row 0 = function row, col 0 = leftmost).
public struct MatrixCell: Hashable, Codable, Sendable {
    public var row: Int, col: Int
    public init(row: Int, col: Int) { self.row = row; self.col = col }
}

/// A physical key.
public struct KeyDef: Identifiable, Hashable, Sendable {
    /// Firmware key ID (used by key-remapping commands).
    public let id: Int
    /// Label as printed on the keycap.
    public let label: String
    /// USB HID usage the key sends by default.
    public let hidUsage: Int
    /// Position in "Windows app pixels" (1 unit ≈ 40 px), origin at the top-left of Esc.
    public let rect: CGRect
    /// LED matrix cells under this key. Empty for keys without an LED (the knob).
    /// Space has several cells; painting it fills all of them.
    public let cells: [MatrixCell]
}

/// A keyboard built on the Dareu TK51G platform: which USB PIDs it uses and its key layout.
public struct KeyboardModel: Sendable, Equatable {
    public let name: String
    /// Product IDs of the keyboard itself (USB cable or Bluetooth). VID is always 0x260D.
    public let pids: Set<Int>
    public let layoutName: String
    public let keys: [KeyDef]
    /// Tested with this app on real hardware.
    public let tested: Bool
    /// LED cells verified on real hardware (otherwise inferred, see docs/KEY-MATRIX.md).
    public let ledMapCalibrated: Bool

    public static func == (a: KeyboardModel, b: KeyboardModel) -> Bool { a.name == b.name }

    /// Basike BA-KEY308, ABNT2. Model code TK51G_0130. Tested; LED map calibrated with photos.
    public static let baKey308 = KeyboardModel(
        name: "Basike BA-KEY308", pids: [0x0130], layoutName: "ABNT2",
        keys: KeyLayout.abnt2Keys, tested: true, ledMapCalibrated: true)

    /// Dareu EK75 / Husky Nomadic HTG200/500/800 V2, ANSI. Dareu's public catalog lists both PIDs
    /// as "Model": "TK51G". Not tested with this app; LED cells inferred from the BA-KEY308.
    public static let ek75 = KeyboardModel(
        name: "Dareu EK75", pids: [0x0101, 0x0045], layoutName: "ANSI",
        keys: KeyLayout.ek75Keys, tested: false, ledMapCalibrated: false)

    public static let all: [KeyboardModel] = [.baKey308, .ek75]

    /// The model for a keyboard PID, or nil for PIDs this app doesn't know.
    public static func forPID(_ pid: Int) -> KeyboardModel? { all.first { $0.pids.contains(pid) } }
}

/// Key layout of the connected keyboard (defaults to the BA-KEY308).
///
/// BA-KEY308 key rectangles come from the Windows app (TK51G_0130.cs `_keyUnitArray`); the EK75's from
/// Dareu's public web-driver profile (tools/gen_layout_dareu_json.py). The LED matrix was calibrated on
/// the real BA-KEY308 on 2026-10-19, because the Windows app's own `_matrixIds` table is wrong for rows
/// 2-4 (it misses the `\` and `/` keys and shifts Right Shift / Up by two columns). See docs/KEY-MATRIX.md.
public enum KeyLayout {
    public static let rows = 6
    public static let columns = 15

    /// Set when a keyboard connects (`KeyboardModel.forPID`). Read from any thread; written rarely.
    nonisolated(unsafe) public static var current: KeyboardModel = .baKey308

    public static var keys: [KeyDef] { current.keys }

    public static var size: CGSize {
        let maxX = keys.map(\.rect.maxX).max() ?? 0
        let maxY = keys.map(\.rect.maxY).max() ?? 0
        return CGSize(width: maxX, height: maxY)
    }

    /// Builds a 6 x 15 frame from per-key colors. Cells without a key stay black.
    public static func frame(from colors: [Int: RGB]) -> [[RGB]] {
        var grid = [[RGB]](repeating: [RGB](repeating: .black, count: columns), count: rows)
        for key in keys {
            guard let c = colors[key.id] else { continue }
            for cell in key.cells { grid[cell.row][cell.col] = c }
        }
        return grid
    }

    public static func key(id: Int) -> KeyDef? { keys.first { $0.id == id } }

    static let abnt2Keys: [KeyDef] = [
        KeyDef(id: 1, label: "Esc", hidUsage: 41, rect: CGRect(x: 0.5, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 0)]),
        KeyDef(id: 2, label: "F1", hidUsage: 58, rect: CGRect(x: 79, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 1)]),
        KeyDef(id: 3, label: "F2", hidUsage: 59, rect: CGRect(x: 120, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 2)]),
        KeyDef(id: 4, label: "F3", hidUsage: 60, rect: CGRect(x: 161, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 3)]),
        KeyDef(id: 5, label: "F4", hidUsage: 61, rect: CGRect(x: 202, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 4)]),
        KeyDef(id: 6, label: "F5", hidUsage: 62, rect: CGRect(x: 266, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 5)]),
        KeyDef(id: 7, label: "F6", hidUsage: 63, rect: CGRect(x: 307, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 6)]),
        KeyDef(id: 8, label: "F7", hidUsage: 64, rect: CGRect(x: 348, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 7)]),
        KeyDef(id: 9, label: "F8", hidUsage: 65, rect: CGRect(x: 389, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 8)]),
        KeyDef(id: 10, label: "F9", hidUsage: 66, rect: CGRect(x: 450, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 9)]),
        KeyDef(id: 11, label: "F10", hidUsage: 67, rect: CGRect(x: 491, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 10)]),
        KeyDef(id: 12, label: "F11", hidUsage: 68, rect: CGRect(x: 532, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 11)]),
        KeyDef(id: 13, label: "F12", hidUsage: 69, rect: CGRect(x: 573, y: 0, width: 40, height: 40), cells: [MatrixCell(row: 0, col: 12)]),
        KeyDef(id: 17, label: "'", hidUsage: 53, rect: CGRect(x: 0, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 0)]),
        KeyDef(id: 18, label: "1", hidUsage: 30, rect: CGRect(x: 41, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 1)]),
        KeyDef(id: 19, label: "2", hidUsage: 31, rect: CGRect(x: 82, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 2)]),
        KeyDef(id: 20, label: "3", hidUsage: 32, rect: CGRect(x: 123, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 3)]),
        KeyDef(id: 21, label: "4", hidUsage: 33, rect: CGRect(x: 164, y: 53, width: 39, height: 40), cells: [MatrixCell(row: 1, col: 4)]),
        KeyDef(id: 22, label: "5", hidUsage: 34, rect: CGRect(x: 204, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 5)]),
        KeyDef(id: 23, label: "6", hidUsage: 35, rect: CGRect(x: 245, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 6)]),
        KeyDef(id: 24, label: "7", hidUsage: 36, rect: CGRect(x: 286, y: 53, width: 39, height: 40), cells: [MatrixCell(row: 1, col: 7)]),
        KeyDef(id: 25, label: "8", hidUsage: 37, rect: CGRect(x: 326, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 8)]),
        KeyDef(id: 26, label: "9", hidUsage: 38, rect: CGRect(x: 367, y: 53, width: 39, height: 40), cells: [MatrixCell(row: 1, col: 9)]),
        KeyDef(id: 27, label: "0", hidUsage: 39, rect: CGRect(x: 407, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 10)]),
        KeyDef(id: 28, label: "-", hidUsage: 45, rect: CGRect(x: 448, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 11)]),
        KeyDef(id: 29, label: "=", hidUsage: 46, rect: CGRect(x: 489, y: 53, width: 39, height: 40), cells: [MatrixCell(row: 1, col: 12)]),
        KeyDef(id: 31, label: "⌫", hidUsage: 42, rect: CGRect(x: 529, y: 53, width: 84, height: 40), cells: [MatrixCell(row: 1, col: 13)]),
        KeyDef(id: 34, label: "PgUp", hidUsage: 75, rect: CGRect(x: 636, y: 53, width: 40, height: 40), cells: [MatrixCell(row: 1, col: 14)]),
        KeyDef(id: 39, label: "Tab", hidUsage: 43, rect: CGRect(x: 0, y: 94, width: 60, height: 40), cells: [MatrixCell(row: 2, col: 0)]),
        KeyDef(id: 40, label: "Q", hidUsage: 20, rect: CGRect(x: 61, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 1)]),
        KeyDef(id: 41, label: "W", hidUsage: 26, rect: CGRect(x: 102, y: 94, width: 39, height: 40), cells: [MatrixCell(row: 2, col: 2)]),
        KeyDef(id: 42, label: "E", hidUsage: 8, rect: CGRect(x: 142, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 3)]),
        KeyDef(id: 43, label: "R", hidUsage: 21, rect: CGRect(x: 183, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 4)]),
        KeyDef(id: 44, label: "T", hidUsage: 23, rect: CGRect(x: 224, y: 94, width: 39, height: 40), cells: [MatrixCell(row: 2, col: 5)]),
        KeyDef(id: 45, label: "Y", hidUsage: 28, rect: CGRect(x: 264, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 6)]),
        KeyDef(id: 46, label: "U", hidUsage: 24, rect: CGRect(x: 305, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 7)]),
        KeyDef(id: 47, label: "I", hidUsage: 12, rect: CGRect(x: 346, y: 94, width: 39, height: 40), cells: [MatrixCell(row: 2, col: 8)]),
        KeyDef(id: 48, label: "O", hidUsage: 18, rect: CGRect(x: 386, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 9)]),
        KeyDef(id: 49, label: "P", hidUsage: 19, rect: CGRect(x: 427, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 10)]),
        KeyDef(id: 50, label: "´", hidUsage: 47, rect: CGRect(x: 468, y: 94, width: 39, height: 40), cells: [MatrixCell(row: 2, col: 11)]),
        KeyDef(id: 51, label: "[", hidUsage: 48, rect: CGRect(x: 508, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 12)]),
        KeyDef(id: 53, label: "Del", hidUsage: 76, rect: CGRect(x: 636, y: 94, width: 40, height: 40), cells: [MatrixCell(row: 2, col: 14)]),
        KeyDef(id: 60, label: "Caps", hidUsage: 57, rect: CGRect(x: 0, y: 135, width: 71, height: 39), cells: [MatrixCell(row: 3, col: 0)]),
        KeyDef(id: 61, label: "A", hidUsage: 4, rect: CGRect(x: 72, y: 135, width: 40, height: 39), cells: [MatrixCell(row: 3, col: 1)]),
        KeyDef(id: 62, label: "S", hidUsage: 22, rect: CGRect(x: 113, y: 135, width: 39, height: 39), cells: [MatrixCell(row: 3, col: 2)]),
        KeyDef(id: 63, label: "D", hidUsage: 7, rect: CGRect(x: 153, y: 135, width: 40, height: 39), cells: [MatrixCell(row: 3, col: 3)]),
        KeyDef(id: 64, label: "F", hidUsage: 9, rect: CGRect(x: 194, y: 135, width: 40, height: 39), cells: [MatrixCell(row: 3, col: 4)]),
        KeyDef(id: 65, label: "G", hidUsage: 10, rect: CGRect(x: 235, y: 135, width: 39, height: 39), cells: [MatrixCell(row: 3, col: 5)]),
        KeyDef(id: 66, label: "H", hidUsage: 11, rect: CGRect(x: 275, y: 135, width: 40, height: 39), cells: [MatrixCell(row: 3, col: 6)]),
        KeyDef(id: 67, label: "J", hidUsage: 13, rect: CGRect(x: 316, y: 135, width: 40, height: 39), cells: [MatrixCell(row: 3, col: 7)]),
        KeyDef(id: 68, label: "K", hidUsage: 14, rect: CGRect(x: 357, y: 135, width: 39, height: 39), cells: [MatrixCell(row: 3, col: 8)]),
        KeyDef(id: 69, label: "L", hidUsage: 15, rect: CGRect(x: 397, y: 135, width: 40, height: 39), cells: [MatrixCell(row: 3, col: 9)]),
        KeyDef(id: 70, label: "Ç", hidUsage: 51, rect: CGRect(x: 438, y: 135, width: 40, height: 39), cells: [MatrixCell(row: 3, col: 10)]),
        KeyDef(id: 71, label: "~", hidUsage: 52, rect: CGRect(x: 479, y: 135, width: 39, height: 39), cells: [MatrixCell(row: 3, col: 11)]),
        KeyDef(id: 52, label: "]", hidUsage: 49, rect: CGRect(x: 519, y: 135, width: 39, height: 39), cells: [MatrixCell(row: 3, col: 13)]),
        KeyDef(id: 73, label: "Enter", hidUsage: 40, rect: CGRect(x: 549, y: 94, width: 64, height: 80), cells: [MatrixCell(row: 2, col: 13)]),
        KeyDef(id: 55, label: "PgDn", hidUsage: 78, rect: CGRect(x: 636, y: 135, width: 40, height: 39), cells: [MatrixCell(row: 3, col: 14)]),
        KeyDef(id: 78, label: "Shift", hidUsage: 225, rect: CGRect(x: 0, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 0)]),
        KeyDef(id: 80, label: "Z", hidUsage: 29, rect: CGRect(x: 81, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 2)]),
        KeyDef(id: 81, label: "X", hidUsage: 27, rect: CGRect(x: 122, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 3)]),
        KeyDef(id: 82, label: "C", hidUsage: 6, rect: CGRect(x: 163, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 4)]),
        KeyDef(id: 83, label: "V", hidUsage: 25, rect: CGRect(x: 204, y: 175, width: 39, height: 40), cells: [MatrixCell(row: 4, col: 5)]),
        KeyDef(id: 84, label: "B", hidUsage: 5, rect: CGRect(x: 244, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 6)]),
        KeyDef(id: 85, label: "N", hidUsage: 17, rect: CGRect(x: 285, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 7)]),
        KeyDef(id: 86, label: "M", hidUsage: 16, rect: CGRect(x: 326, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 8)]),
        KeyDef(id: 87, label: ",", hidUsage: 54, rect: CGRect(x: 367, y: 175, width: 39, height: 40), cells: [MatrixCell(row: 4, col: 9)]),
        KeyDef(id: 88, label: ".", hidUsage: 55, rect: CGRect(x: 407, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 10)]),
        KeyDef(id: 89, label: ";", hidUsage: 56, rect: CGRect(x: 448, y: 175, width: 39, height: 40), cells: [MatrixCell(row: 4, col: 11)]),
        KeyDef(id: 135, label: "/", hidUsage: 135, rect: CGRect(x: 488, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 12)]),
        KeyDef(id: 91, label: "Shift", hidUsage: 229, rect: CGRect(x: 529, y: 175, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 13)]),
        KeyDef(id: 92, label: "↑", hidUsage: 82, rect: CGRect(x: 596, y: 186, width: 40, height: 40), cells: [MatrixCell(row: 4, col: 14)]),
        KeyDef(id: 97, label: "Ctrl", hidUsage: 224, rect: CGRect(x: 0, y: 216, width: 50, height: 40), cells: [MatrixCell(row: 5, col: 0)]),
        KeyDef(id: 98, label: "Win", hidUsage: 227, rect: CGRect(x: 51, y: 216, width: 49, height: 40), cells: [MatrixCell(row: 5, col: 1)]),
        KeyDef(id: 99, label: "Alt", hidUsage: 226, rect: CGRect(x: 101, y: 216, width: 50, height: 40), cells: [MatrixCell(row: 5, col: 2)]),
        KeyDef(id: 100, label: "\\", hidUsage: 100, rect: CGRect(x: 41, y: 175, width: 39, height: 40), cells: [MatrixCell(row: 4, col: 1)]),
        KeyDef(id: 102, label: "Space", hidUsage: 44, rect: CGRect(x: 152, y: 216, width: 256, height: 40), cells: [MatrixCell(row: 5, col: 3), MatrixCell(row: 5, col: 4), MatrixCell(row: 5, col: 5), MatrixCell(row: 5, col: 6), MatrixCell(row: 5, col: 7), MatrixCell(row: 5, col: 8)]),
        KeyDef(id: 106, label: "AltGr", hidUsage: 230, rect: CGRect(x: 409, y: 216, width: 40, height: 40), cells: [MatrixCell(row: 5, col: 9)]),
        KeyDef(id: 107, label: "Fn", hidUsage: 231, rect: CGRect(x: 450, y: 216, width: 40, height: 40), cells: [MatrixCell(row: 5, col: 10)]),
        KeyDef(id: 109, label: "Ctrl", hidUsage: 228, rect: CGRect(x: 491, y: 216, width: 40, height: 40), cells: [MatrixCell(row: 5, col: 11)]),
        KeyDef(id: 110, label: "←", hidUsage: 80, rect: CGRect(x: 555, y: 228, width: 40, height: 40), cells: [MatrixCell(row: 5, col: 12)]),
        KeyDef(id: 111, label: "↓", hidUsage: 81, rect: CGRect(x: 596, y: 228, width: 40, height: 40), cells: [MatrixCell(row: 5, col: 13)]),
        KeyDef(id: 112, label: "→", hidUsage: 79, rect: CGRect(x: 637, y: 228, width: 40, height: 40), cells: [MatrixCell(row: 5, col: 14)]),
        KeyDef(id: 170, label: "Mute", hidUsage: 0, rect: CGRect(x: 638.5, y: 3, width: 35, height: 35), cells: []),
    ]

    // Generated by tools/gen_layout_dareu_json.py from https://dr.dareu.com/products/0101/0101.json
    static let ek75Keys: [KeyDef] = [
        KeyDef(id: 1, label: "Esc", hidUsage: 41, rect: CGRect(x: 0, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 0)]),
        KeyDef(id: 2, label: "F1", hidUsage: 58, rect: CGRect(x: 71, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 1)]),
        KeyDef(id: 3, label: "F2", hidUsage: 59, rect: CGRect(x: 110, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 2)]),
        KeyDef(id: 4, label: "F3", hidUsage: 60, rect: CGRect(x: 149, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 3)]),
        KeyDef(id: 5, label: "F4", hidUsage: 61, rect: CGRect(x: 188, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 4)]),
        KeyDef(id: 6, label: "F5", hidUsage: 62, rect: CGRect(x: 242, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 5)]),
        KeyDef(id: 7, label: "F6", hidUsage: 63, rect: CGRect(x: 281, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 6)]),
        KeyDef(id: 8, label: "F7", hidUsage: 64, rect: CGRect(x: 320, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 7)]),
        KeyDef(id: 9, label: "F8", hidUsage: 65, rect: CGRect(x: 359, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 8)]),
        KeyDef(id: 10, label: "F9", hidUsage: 66, rect: CGRect(x: 413, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 9)]),
        KeyDef(id: 11, label: "F10", hidUsage: 67, rect: CGRect(x: 452, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 10)]),
        KeyDef(id: 12, label: "F11", hidUsage: 68, rect: CGRect(x: 491, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 11)]),
        KeyDef(id: 13, label: "F12", hidUsage: 69, rect: CGRect(x: 530, y: 0, width: 38, height: 38), cells: [MatrixCell(row: 0, col: 12)]),
        KeyDef(id: 170, label: "Mute", hidUsage: 0, rect: CGRect(x: 590, y: 1, width: 36, height: 36), cells: []),
        KeyDef(id: 17, label: "~", hidUsage: 53, rect: CGRect(x: 0, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 0)]),
        KeyDef(id: 18, label: "1", hidUsage: 30, rect: CGRect(x: 38, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 1)]),
        KeyDef(id: 19, label: "2", hidUsage: 31, rect: CGRect(x: 76, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 2)]),
        KeyDef(id: 20, label: "3", hidUsage: 32, rect: CGRect(x: 114, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 3)]),
        KeyDef(id: 21, label: "4", hidUsage: 33, rect: CGRect(x: 152, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 4)]),
        KeyDef(id: 22, label: "5", hidUsage: 34, rect: CGRect(x: 190, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 5)]),
        KeyDef(id: 23, label: "6", hidUsage: 35, rect: CGRect(x: 228, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 6)]),
        KeyDef(id: 24, label: "7", hidUsage: 36, rect: CGRect(x: 266, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 7)]),
        KeyDef(id: 25, label: "8", hidUsage: 37, rect: CGRect(x: 304, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 8)]),
        KeyDef(id: 26, label: "9", hidUsage: 38, rect: CGRect(x: 342, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 9)]),
        KeyDef(id: 27, label: "0", hidUsage: 39, rect: CGRect(x: 380, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 10)]),
        KeyDef(id: 28, label: "-", hidUsage: 45, rect: CGRect(x: 418, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 11)]),
        KeyDef(id: 29, label: "=", hidUsage: 46, rect: CGRect(x: 456, y: 46, width: 37, height: 38), cells: [MatrixCell(row: 1, col: 12)]),
        KeyDef(id: 31, label: "⌫", hidUsage: 42, rect: CGRect(x: 494, y: 46, width: 74, height: 38), cells: [MatrixCell(row: 1, col: 13)]),
        KeyDef(id: 34, label: "PgUp", hidUsage: 75, rect: CGRect(x: 588, y: 46, width: 38, height: 38), cells: [MatrixCell(row: 1, col: 14)]),
        KeyDef(id: 39, label: "Tab", hidUsage: 43, rect: CGRect(x: 0, y: 85, width: 56, height: 38), cells: [MatrixCell(row: 2, col: 0)]),
        KeyDef(id: 40, label: "Q", hidUsage: 20, rect: CGRect(x: 57, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 1)]),
        KeyDef(id: 41, label: "W", hidUsage: 26, rect: CGRect(x: 95, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 2)]),
        KeyDef(id: 42, label: "E", hidUsage: 8, rect: CGRect(x: 133, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 3)]),
        KeyDef(id: 43, label: "R", hidUsage: 21, rect: CGRect(x: 171, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 4)]),
        KeyDef(id: 44, label: "T", hidUsage: 23, rect: CGRect(x: 209, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 5)]),
        KeyDef(id: 45, label: "Y", hidUsage: 28, rect: CGRect(x: 247, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 6)]),
        KeyDef(id: 46, label: "U", hidUsage: 24, rect: CGRect(x: 285, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 7)]),
        KeyDef(id: 47, label: "I", hidUsage: 12, rect: CGRect(x: 323, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 8)]),
        KeyDef(id: 48, label: "O", hidUsage: 18, rect: CGRect(x: 361, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 9)]),
        KeyDef(id: 49, label: "P", hidUsage: 19, rect: CGRect(x: 399, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 10)]),
        KeyDef(id: 50, label: "[", hidUsage: 47, rect: CGRect(x: 437, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 11)]),
        KeyDef(id: 51, label: "]", hidUsage: 48, rect: CGRect(x: 475, y: 85, width: 37, height: 38), cells: [MatrixCell(row: 2, col: 12)]),
        KeyDef(id: 52, label: "\\", hidUsage: 49, rect: CGRect(x: 513, y: 85, width: 55, height: 38), cells: [MatrixCell(row: 2, col: 13)]),
        KeyDef(id: 53, label: "Del", hidUsage: 76, rect: CGRect(x: 588, y: 85, width: 38, height: 38), cells: [MatrixCell(row: 2, col: 14)]),
        KeyDef(id: 60, label: "Caps", hidUsage: 57, rect: CGRect(x: 0, y: 124, width: 64, height: 38), cells: [MatrixCell(row: 3, col: 0)]),
        KeyDef(id: 61, label: "A", hidUsage: 4, rect: CGRect(x: 65, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 1)]),
        KeyDef(id: 62, label: "S", hidUsage: 22, rect: CGRect(x: 103, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 2)]),
        KeyDef(id: 63, label: "D", hidUsage: 7, rect: CGRect(x: 141, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 3)]),
        KeyDef(id: 64, label: "F", hidUsage: 9, rect: CGRect(x: 179, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 4)]),
        KeyDef(id: 65, label: "G", hidUsage: 10, rect: CGRect(x: 217, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 5)]),
        KeyDef(id: 66, label: "H", hidUsage: 11, rect: CGRect(x: 255, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 6)]),
        KeyDef(id: 67, label: "J", hidUsage: 13, rect: CGRect(x: 293, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 7)]),
        KeyDef(id: 68, label: "K", hidUsage: 14, rect: CGRect(x: 331, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 8)]),
        KeyDef(id: 69, label: "L", hidUsage: 15, rect: CGRect(x: 369, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 9)]),
        KeyDef(id: 70, label: ";", hidUsage: 51, rect: CGRect(x: 407, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 10)]),
        KeyDef(id: 71, label: "'", hidUsage: 52, rect: CGRect(x: 445, y: 124, width: 37, height: 38), cells: [MatrixCell(row: 3, col: 11)]),
        KeyDef(id: 73, label: "Enter", hidUsage: 40, rect: CGRect(x: 483, y: 124, width: 85, height: 38), cells: [MatrixCell(row: 3, col: 12), MatrixCell(row: 3, col: 13)]),
        KeyDef(id: 55, label: "PgDn", hidUsage: 78, rect: CGRect(x: 588, y: 124, width: 38, height: 38), cells: [MatrixCell(row: 3, col: 14)]),
        KeyDef(id: 78, label: "Shift", hidUsage: 225, rect: CGRect(x: 0, y: 163, width: 84, height: 38), cells: [MatrixCell(row: 4, col: 0), MatrixCell(row: 4, col: 1)]),
        KeyDef(id: 80, label: "Z", hidUsage: 29, rect: CGRect(x: 85, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 2)]),
        KeyDef(id: 81, label: "X", hidUsage: 27, rect: CGRect(x: 123, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 3)]),
        KeyDef(id: 82, label: "C", hidUsage: 6, rect: CGRect(x: 161, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 4)]),
        KeyDef(id: 83, label: "V", hidUsage: 25, rect: CGRect(x: 199, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 5)]),
        KeyDef(id: 84, label: "B", hidUsage: 5, rect: CGRect(x: 237, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 6)]),
        KeyDef(id: 85, label: "N", hidUsage: 17, rect: CGRect(x: 275, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 7)]),
        KeyDef(id: 86, label: "M", hidUsage: 16, rect: CGRect(x: 313, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 8)]),
        KeyDef(id: 87, label: ",", hidUsage: 54, rect: CGRect(x: 351, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 9)]),
        KeyDef(id: 88, label: ".", hidUsage: 55, rect: CGRect(x: 389, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 10)]),
        KeyDef(id: 89, label: "/", hidUsage: 56, rect: CGRect(x: 427, y: 163, width: 37, height: 38), cells: [MatrixCell(row: 4, col: 11)]),
        KeyDef(id: 91, label: "Shift", hidUsage: 229, rect: CGRect(x: 465, y: 163, width: 67, height: 38), cells: [MatrixCell(row: 4, col: 12), MatrixCell(row: 4, col: 13)]),
        KeyDef(id: 92, label: "↑", hidUsage: 82, rect: CGRect(x: 550, y: 172, width: 38, height: 38), cells: [MatrixCell(row: 4, col: 14)]),
        KeyDef(id: 97, label: "Ctrl", hidUsage: 224, rect: CGRect(x: 0, y: 202, width: 47, height: 38), cells: [MatrixCell(row: 5, col: 0)]),
        KeyDef(id: 98, label: "Win", hidUsage: 227, rect: CGRect(x: 48, y: 202, width: 47, height: 38), cells: [MatrixCell(row: 5, col: 1)]),
        KeyDef(id: 99, label: "Alt", hidUsage: 226, rect: CGRect(x: 96, y: 202, width: 47, height: 38), cells: [MatrixCell(row: 5, col: 2)]),
        KeyDef(id: 102, label: "Space", hidUsage: 44, rect: CGRect(x: 144, y: 202, width: 232, height: 38), cells: [MatrixCell(row: 5, col: 3), MatrixCell(row: 5, col: 4), MatrixCell(row: 5, col: 5), MatrixCell(row: 5, col: 6), MatrixCell(row: 5, col: 7), MatrixCell(row: 5, col: 8)]),
        KeyDef(id: 106, label: "Alt", hidUsage: 230, rect: CGRect(x: 378, y: 202, width: 38, height: 38), cells: [MatrixCell(row: 5, col: 9)]),
        KeyDef(id: 107, label: "Fn", hidUsage: 0, rect: CGRect(x: 416, y: 202, width: 38, height: 38), cells: [MatrixCell(row: 5, col: 10)]),
        KeyDef(id: 109, label: "Ctrl", hidUsage: 228, rect: CGRect(x: 455, y: 202, width: 38, height: 38), cells: [MatrixCell(row: 5, col: 11)]),
        KeyDef(id: 110, label: "←", hidUsage: 80, rect: CGRect(x: 511, y: 211, width: 38, height: 38), cells: [MatrixCell(row: 5, col: 12)]),
        KeyDef(id: 111, label: "↓", hidUsage: 81, rect: CGRect(x: 550, y: 211, width: 38, height: 38), cells: [MatrixCell(row: 5, col: 13)]),
        KeyDef(id: 112, label: "→", hidUsage: 79, rect: CGRect(x: 589, y: 211, width: 38, height: 38), cells: [MatrixCell(row: 5, col: 14)]),
    ]
}
