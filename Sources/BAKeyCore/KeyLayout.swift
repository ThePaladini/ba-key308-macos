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
    /// Label as printed on the ABNT2 keycap.
    public let label: String
    /// USB HID usage the key sends by default.
    public let hidUsage: Int
    /// Position in "Windows app pixels" (1 unit ≈ 40 px), origin at the top-left of Esc.
    public let rect: CGRect
    /// LED matrix cells under this key. Empty for keys without an LED (the knob).
    /// Space has several cells; painting it fills all of them.
    public let cells: [MatrixCell]
}

/// The BA-KEY308 (ABNT2) layout.
///
/// Key rectangles come from the Windows app (TK51G_0130.cs `_keyUnitArray`).
/// The LED matrix was calibrated on the real keyboard on 2026-10-19, because the
/// Windows app's own `_matrixIds` table is wrong for rows 2-4 (it is an ANSI table:
/// it misses the `\` and `/` keys and shifts Right Shift / Up by two columns).
/// See docs/KEY-MATRIX.md.
public enum KeyLayout {
    public static let rows = 6
    public static let columns = 15

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

    public static let keys: [KeyDef] = [
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
}
