@testable import BAKeyCore
import XCTest

final class ReportDescriptorTests: XCTestCase {
    /// The real descriptor of the BA-KEY308 over Bluetooth LE (from ioreg, 2026-10-19).
    static let bleDescriptor: [UInt8] = hex("""
    05010906a1018501050719e029e715002501750195088102050819012903950375019102950175059101050719002aff00\
    150026ff007508950a8100c005010902a10185020901a100050919012905150025017501950581027501950381030600ff\
    0940750895021581257f8102050109381581257f7508950181060930093116008026ff7f751095028106050c0a38021581\
    257f750895018106c0c0050c0901a101850319002a9d021500269d02950175108100950a75088101c005010980a1018504\
    1981298315002501750195038102950581017508950b8101c0050c0901a10185050903150026ff00350046ff0075089\
    50c8100c0050c0901a10185060903150026ff00350046ff007508950c8100c0050c0901a10185070600ff0902150026ff\
    0075089540b101c00501090ea1018508050d0921a1000509090195017501150025018102750781030501093795017510\
    550f651436f0f146100e16f0f126100e8106c0c0
    """)

    func testBluetoothDescriptorUsesReportID7() {
        XCTAssertEqual(ReportDescriptor.featureReportID(in: Self.bleDescriptor), 7)
    }

    func testDescriptorWithoutReportIDs() {
        // Usage Page (Vendor), Usage, Collection, Report Size 8, Report Count 64, Feature, End
        let d: [UInt8] = [0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x75, 0x08, 0x95, 0x40, 0xB1, 0x02, 0xC0]
        XCTAssertEqual(ReportDescriptor.featureReportID(in: d), 0)
    }

    func testDescriptorWithoutFeatureReport() {
        let d: [UInt8] = [0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x75, 0x08, 0x95, 0x40, 0x81, 0x02, 0xC0]
        XCTAssertNil(ReportDescriptor.featureReportID(in: d))
    }

    static func hex(_ s: String) -> [UInt8] {
        let chars = Array(s.filter(\.isHexDigit))
        return stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0 + 1]), radix: 16)! }
    }
}

final class PacketTests: XCTestCase {
    func testSetEffectLayoutMatchesCapturedPacket() {
        // Static red on the backlight, profile 1, as sent during the 2026-10-19 experiment.
        let p = Packet(reportID: 7, commandClass: 3, command: 0x02, profile: 1, payload: [1, 1, 0, 0, 1, 255, 0, 0])
        XCTAssertEqual(Array(p.bytes.prefix(15)), [7, 0, 8, 3, 2, 1, 0, 1, 1, 0, 0, 1, 255, 0, 0])
        XCTAssertEqual(p.bytes.count, 65)
    }

    func testParsesCapturedBatteryResponse() {
        let r = Packet(bytes: ReportDescriptorTests.hex("07 02 04 07 80 00 00 00 64 64"))
        XCTAssertEqual(r.status, .ready)
        XCTAssertEqual(r.commandClass, 7)
        XCTAssertEqual(r.command, 0x80)
        XCTAssertEqual(r[8], 100)
    }

    func testFramePackets() {
        let rows = [[RGB]](repeating: [RGB](repeating: RGB(1, 2, 3), count: 15), count: 6)
        let packets = PacketBuilder.framePackets(reportID: 7, region: 1, rows: rows)
        XCTAssertEqual(packets.count, 6)
        for (i, p) in packets.enumerated() {
            XCTAssertEqual(p[3], 3)
            XCTAssertEqual(p[4], 4)
            XCTAssertEqual(p[2], 6 + 45)
            XCTAssertEqual(p[7], 1)
            XCTAssertEqual(p[8], i == 5 ? 0x81 : 0x01)
            XCTAssertEqual(p[9], UInt8(i))
            XCTAssertEqual(p[10], 0)
            XCTAssertEqual(p[11], 14)
            XCTAssertEqual(Array(p.bytes[12..<15]), [1, 2, 3])
        }
    }

    func testRGBHex() {
        XCTAssertEqual(RGB(hex: "#FF8800"), RGB(255, 136, 0))
        XCTAssertEqual(RGB(255, 136, 0).hex, "FF8800")
        XCTAssertNil(RGB(hex: "nope"))
    }
}

final class LayoutTests: XCTestCase {
    func testEveryCellIsInsideTheMatrixAndUsedOnce() {
        var seen = Set<MatrixCell>()
        for k in KeyLayout.keys {
            for c in k.cells {
                XCTAssert((0..<KeyLayout.rows).contains(c.row) && (0..<KeyLayout.columns).contains(c.col), "\(k.label)")
                XCTAssertTrue(seen.insert(c).inserted, "cell \(c) used twice")
            }
        }
    }

    func testCalibratedPositions() {
        // Verified on the real keyboard with photos.
        func cells(_ id: Int) -> [MatrixCell] { KeyLayout.key(id: id)!.cells }
        XCTAssertEqual(cells(91), [MatrixCell(row: 4, col: 13)])  // Right Shift
        XCTAssertEqual(cells(92), [MatrixCell(row: 4, col: 14)])  // Up
        XCTAssertEqual(cells(73), [MatrixCell(row: 2, col: 13)])  // Enter
        XCTAssertEqual(cells(71), [MatrixCell(row: 3, col: 11)])  // ~
        XCTAssertEqual(cells(52), [MatrixCell(row: 3, col: 13)])  // ]
        XCTAssertEqual(cells(100), [MatrixCell(row: 4, col: 1)])  // backslash
        XCTAssertEqual(cells(135), [MatrixCell(row: 4, col: 12)]) // slash
        XCTAssertEqual(cells(106), [MatrixCell(row: 5, col: 9)])  // AltGr
        XCTAssertTrue(cells(102).contains(MatrixCell(row: 5, col: 7)))  // Space
    }

    func testFrameFromColors() {
        let f = KeyLayout.frame(from: [41: RGB(255, 0, 0)]) // W
        XCTAssertEqual(f[2][2], RGB(255, 0, 0))
        XCTAssertEqual(f[0][0], .black)
    }
}

final class SafetyTests: XCTestCase {
    func testDangerousClassesAreNotRepresentable() {
        XCTAssertNil(CommandClass(rawValue: 9))   // firmware update
        XCTAssertNil(CommandClass(rawValue: 10))  // test / factory
        XCTAssertNil(CommandClass(rawValue: 12))  // flash erase / program
    }

    func testOnlyAllowlistedSets() {
        XCTAssertTrue(KeyboardClient.allowedSets.contains([3, 0x02]))
        XCTAssertFalse(KeyboardClient.allowedSets.contains([0, 0x02])) // serial number
        XCTAssertFalse(KeyboardClient.allowedSets.contains([0, 0x03])) // device mode (DFU)
        XCTAssertFalse(KeyboardClient.allowedSets.contains([5, 0x05])) // profile reset
    }
}

final class KeyPressMonitorTests: XCTestCase {
    /// In event-tap mode every lit key must be reachable from a macOS key code.
    func testEveryLitKeyHasAKeyCodeMapping() {
        let reachable = Set(KeyPressMonitor.usageForKeyCode.values).union(KeyPressMonitor.modifiers.values.map(\.0))
        for k in KeyLayout.keys where !k.cells.isEmpty {
            XCTAssertTrue(reachable.contains(k.hidUsage), "\(k.label) (HID 0x\(String(k.hidUsage, radix: 16))) has no key code mapping")
        }
    }
}

final class FrameDifferTests: XCTestCase {
    private func frame(_ colors: [Int: RGB]) -> [[RGB]] { KeyLayout.frame(from: colors) }
    private var allKeys: [Int] { KeyLayout.keys.filter { !$0.cells.isEmpty }.map(\.id) }

    func testFirstPushSendsEverythingOrFill() {
        let d = FrameDiffer()
        let blue = frame(Dictionary(uniqueKeysWithValues: allKeys.map { ($0, RGB(0, 0, 255)) }))
        let plan = d.plan(blue, reportID: 7)
        XCTAssertEqual(plan.count, 1, "uniform frame should be one fill packet")
        XCTAssertEqual(plan[0][8], 0x03)
        XCTAssertEqual(Array(plan[0].bytes[9...11]), [0, 0, 255])
    }

    func testOnlyChangedRowIsSent() {
        var d = FrameDiffer()
        let base = frame([:])
        d.applied(PacketBuilder.framePackets(reportID: 7, region: 1, rows: base), frame: base)
        let w = frame([41: RGB(255, 0, 0)]) // W is in row 2
        let plan = d.plan(w, reportID: 7)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0][8], 0x81)
        XCTAssertEqual(plan[0][9], 2)
        d.applied(plan, frame: w)
        XCTAssertTrue(d.plan(w, reportID: 7).isEmpty, "nothing left to send")
    }

    func testMostChangedRowFirstWhenLimited() {
        var d = FrameDiffer()
        let base = frame([:])
        d.applied(PacketBuilder.framePackets(reportID: 7, region: 1, rows: base), frame: base)
        // Row 2: one dim key. Row 3: three bright keys.
        let f = frame([41: RGB(10, 0, 0), 61: .white, 62: .white, 63: .white])
        let plan = d.plan(f, reportID: 7, maxPackets: 1)
        XCTAssertEqual(plan.map { $0[9] }, [3])
    }
}

final class KeyboardModelTests: XCTestCase {
    func testPIDsMapToModels() {
        XCTAssertEqual(KeyboardModel.forPID(0x0130), .baKey308)
        XCTAssertEqual(KeyboardModel.forPID(0x0101), .ek75)
        XCTAssertEqual(KeyboardModel.forPID(0x0045), .ek75)
        XCTAssertNil(KeyboardModel.forPID(0x0042), "the receiver is not a keyboard model")
        XCTAssertTrue(BAKey.keyboardPIDs.contains(0x0130) && BAKey.keyboardPIDs.contains(0x0101))
    }

    func testEveryModelLayoutIsConsistent() {
        for model in KeyboardModel.all {
            var seen = Set<MatrixCell>()
            for k in model.keys {
                for c in k.cells {
                    XCTAssert((0..<KeyLayout.rows).contains(c.row) && (0..<KeyLayout.columns).contains(c.col), "\(model.name) \(k.label)")
                    XCTAssertTrue(seen.insert(c).inserted, "\(model.name): cell \(c) used twice")
                }
            }
            XCTAssertEqual(Set(model.keys.map(\.id)).count, model.keys.count, "\(model.name): duplicate key IDs")
        }
    }

    func testEK75IsANSI() {
        let ids = Set(KeyboardModel.ek75.keys.map(\.id))
        XCTAssertFalse(ids.contains(100), "no ISO backslash key")
        XCTAssertFalse(ids.contains(135), "no ABNT2 slash key")
        XCTAssertEqual(KeyboardModel.ek75.keys.first { $0.id == 73 }?.label, "Enter")
    }

    func testEK75KeysReachableInEventTapMode() {
        let reachable = Set(KeyPressMonitor.usageForKeyCode.values).union(KeyPressMonitor.modifiers.values.map(\.0))
        for k in KeyboardModel.ek75.keys where !k.cells.isEmpty && k.hidUsage != 0 {
            XCTAssertTrue(reachable.contains(k.hidUsage), "EK75 \(k.label) (HID 0x\(String(k.hidUsage, radix: 16)))")
        }
    }

    func testLayoutFollowsCurrentModel() {
        defer { KeyLayout.current = .baKey308 }
        KeyLayout.current = .ek75
        XCTAssertNil(KeyLayout.key(id: 135))
        XCTAssertEqual(KeyLayout.frame(from: [78: RGB(1, 2, 3)])[4][1], RGB(1, 2, 3), "wide ANSI Left Shift fills both cells")
    }
}

final class BluetoothBatteryTests: XCTestCase {
    /// Shape of real `system_profiler SPBluetoothDataType -json` output (2026-10-20, macOS 26),
    /// addresses replaced. The mouse and AirPods entries follow the same format.
    static let json = #"""
    {"SPBluetoothDataType": [{
      "device_connected": [
        {"BA-KEY308": {"device_address": "AA:BB:CC:00:00:01", "device_batteryLevelMain": "100%",
                       "device_minorType": "Keyboard", "device_vendorID": "0x260D", "device_productID": "0x0130"}},
        {"IMICE GW-X7 5.1": {"device_address": "AA:BB:CC:00:00:02", "device_batteryLevelMain": "62%",
                             "device_minorType": "Mouse"}},
        {"AirPods Pro": {"device_address": "AA:BB:CC:00:00:03", "device_minorType": "Headphones",
                         "device_batteryLevelLeft": "80%", "device_batteryLevelRight": "75%", "device_batteryLevelCase": "40%"}},
        {"Speaker": {"device_address": "AA:BB:CC:00:00:04", "device_minorType": "Speaker"}}
      ],
      "device_not_connected": [
        {"Old Mouse": {"device_address": "AA:BB:CC:00:00:05", "device_minorType": "Mouse", "device_batteryLevelMain": "10%"}}
      ]
    }]}
    """#

    func testParsesConnectedDevicesWithBattery() {
        let list = BluetoothBatteryDevice.parse(Data(Self.json.utf8))
        XCTAssertEqual(list.map(\.name), ["IMICE GW-X7 5.1", "AirPods Pro", "BA-KEY308"], "mice first, no-battery and disconnected devices skipped")
        let mouse = list[0]
        XCTAssertTrue(mouse.isMouse)
        XCTAssertEqual(mouse.primary, 62)
        XCTAssertEqual(mouse.symbol, "computermouse")
        let pods = list[1]
        XCTAssertEqual(pods.levels.map(\.label), ["L", "R", "Case"])
        XCTAssertEqual(pods.primary, 75, "lower earbud when there is no main battery; the case doesn't count")
        XCTAssertEqual(list[2].symbol, "keyboard")
        XCTAssertTrue(list[2].isDareuKeyboard, "VID 0x260D: shown by the app itself, not in the Bluetooth list")
        XCTAssertFalse(mouse.isDareuKeyboard)
    }

    func testGarbageIsEmpty() {
        XCTAssertTrue(BluetoothBatteryDevice.parse(Data("not json".utf8)).isEmpty)
    }
}
