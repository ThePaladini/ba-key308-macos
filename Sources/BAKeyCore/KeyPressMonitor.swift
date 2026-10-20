import CoreGraphics
import Foundation
import IOKit.hid

/// Reports key presses as USB HID usages (page 0x07). Used by the reactive Mac effects.
///
/// Two sources, tried in order:
/// 1. **Raw HID** from the BA-KEY308 itself (`IOHIDManager`). Exact, and ignores other keyboards.
///    Fails with `kIOReturnExclusiveAccess` (0xE00002C5) when another program has seized the
///    keyboard, typically Karabiner-Elements when the BA-KEY308 is enabled in its Devices tab.
/// 2. **macOS key events** (`CGEventTap`, listen-only). Works alongside Karabiner, because it sees
///    the events Karabiner emits, but it can't tell keyboards apart, so the built-in keyboard
///    triggers effects too. Virtual key codes are mapped back to HID usages.
///
/// Both need the **Input Monitoring** permission. Only the usage of a newly pressed key is
/// passed on; nothing is stored.
public final class KeyPressMonitor: @unchecked Sendable {
    public enum Source: Sendable { case none, rawHID, eventTap }

    private let manager: IOHIDManager
    private var hidOpen = false
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    public private(set) var source: Source = .none
    /// Why listening failed, for display.
    public private(set) var lastFailure: String?
    /// Called on the main run loop with the HID usage of each key press.
    public var onKeyDown: ((Int) -> Void)?

    public static var accessGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the system permission prompt the first time; afterwards returns the current state.
    @discardableResult
    public static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [BAKey.keyboardPID, BAKey.donglePID].map {
            [kIOHIDVendorIDKey as String: BAKey.vendorID, kIOHIDProductIDKey as String: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            guard let ctx else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == 0x07 else { return }
            let usage = Int(IOHIDElementGetUsage(element))
            // 0x04...0xE7: real keys and modifiers. Skip "no event" / rollover codes 0-3.
            guard (0x04...0xE7).contains(usage), IOHIDValueGetIntegerValue(value) == 1 else { return }
            Unmanaged<KeyPressMonitor>.fromOpaque(ctx).takeUnretainedValue().onKeyDown?(usage)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit { stop() }

    /// Starts listening. Returns false when nothing could be started (see `lastFailure`).
    @discardableResult
    public func start() -> Bool {
        guard source == .none else { return true }
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        guard access == kIOHIDAccessTypeGranted || Self.requestAccess() else {
            lastFailure = access == kIOHIDAccessTypeDenied
                ? "macOS reports Input Monitoring as denied for this build of the app."
                : "macOS has not been asked yet (access unknown)."
            return false
        }

        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnSuccess {
            hidOpen = true
            source = .rawHID
            lastFailure = nil
            return true
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        if startEventTap() {
            source = .eventTap
            lastFailure = nil
            return true
        }
        lastFailure = String(format: "Opening the keyboard failed (IOReturn 0x%08X) and the macOS key event tap could not be created.", r)
        return false
    }

    public func stop() {
        if hidOpen {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidOpen = false
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        }
        tap = nil
        tapSource = nil
        source = .none
    }

    // MARK: - Event tap fallback

    private func startEventTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, ctx in
                guard let ctx else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyPressMonitor>.fromOpaque(ctx).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: ctx)
        else { return false }
        self.tap = tap
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if let usage = Self.usageForKeyCode[code] { onKeyDown?(usage) }
        case .flagsChanged:
            // Modifiers have no keyDown. React when the modifier's flag turned on (pressed).
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            guard let (usage, flag) = Self.modifiers[code], event.flags.contains(flag) else { return }
            onKeyDown?(usage)
        default:
            break
        }
    }

    /// macOS virtual key code → HID usage (page 7). Covers every key of the BA-KEY308,
    /// including the ABNT2 keys (`\` = ISO section 0x0A, `/?` = JIS underscore 0x5E).
    static let usageForKeyCode: [Int: Int] = [
        0x00: 0x04, 0x0B: 0x05, 0x08: 0x06, 0x02: 0x07, 0x0E: 0x08, 0x03: 0x09, 0x05: 0x0A, 0x04: 0x0B,
        0x22: 0x0C, 0x26: 0x0D, 0x28: 0x0E, 0x25: 0x0F, 0x2E: 0x10, 0x2D: 0x11, 0x1F: 0x12, 0x23: 0x13,
        0x0C: 0x14, 0x0F: 0x15, 0x01: 0x16, 0x11: 0x17, 0x20: 0x18, 0x09: 0x19, 0x0D: 0x1A, 0x07: 0x1B,
        0x10: 0x1C, 0x06: 0x1D,
        0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x17: 0x22, 0x16: 0x23, 0x1A: 0x24, 0x1C: 0x25,
        0x19: 0x26, 0x1D: 0x27,
        0x24: 0x28, 0x35: 0x29, 0x33: 0x2A, 0x30: 0x2B, 0x31: 0x2C, 0x1B: 0x2D, 0x18: 0x2E, 0x21: 0x2F,
        0x1E: 0x30, 0x2A: 0x31, 0x29: 0x33, 0x27: 0x34, 0x32: 0x35, 0x2B: 0x36, 0x2F: 0x37, 0x2C: 0x38,
        0x39: 0x39,
        0x7A: 0x3A, 0x78: 0x3B, 0x63: 0x3C, 0x76: 0x3D, 0x60: 0x3E, 0x61: 0x3F, 0x62: 0x40, 0x64: 0x41,
        0x65: 0x42, 0x6D: 0x43, 0x67: 0x44, 0x6F: 0x45,
        0x74: 0x4B, 0x75: 0x4C, 0x79: 0x4E, 0x7C: 0x4F, 0x7B: 0x50, 0x7D: 0x51, 0x7E: 0x52,
        0x0A: 0x64, 0x5E: 0x87,
    ]

    static let modifiers: [Int: (Int, CGEventFlags)] = [
        0x3B: (0xE0, .maskControl), 0x38: (0xE1, .maskShift), 0x3A: (0xE2, .maskAlternate),
        0x37: (0xE3, .maskCommand), 0x3E: (0xE4, .maskControl), 0x3C: (0xE5, .maskShift),
        0x3D: (0xE6, .maskAlternate), 0x36: (0xE7, .maskCommand),
    ]
}
