import Foundation
import IOKit.hid

/// One IOKit HID device that exposes the 64-byte configuration feature report.
///
/// On macOS a single `IOHIDDevice` covers every top-level collection of an interface,
/// so there is no "pick the right collection" step like on Windows. A USB keyboard can
/// still show up as several devices (one per interface); `init` rejects the ones whose
/// report descriptor has no 64-byte feature report.
public final class HIDDevice: @unchecked Sendable {
    public let device: IOHIDDevice
    public let reportID: UInt8
    public let productID: Int
    public let name: String
    /// "Bluetooth Low Energy", "USB", ...
    public let transport: String

    public var isReceiver: Bool { productID == BAKey.donglePID }

    public init?(device: IOHIDDevice) {
        guard let desc = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data,
              let rid = ReportDescriptor.featureReportID(in: [UInt8](desc)) else { return nil }
        self.device = device
        self.reportID = rid
        self.productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        self.name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "BA-KEY308"
        self.transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?"
    }

    /// Opens without seizing. An exclusive open would fail (and would steal the keyboard
    /// from macOS), which is why the first experiment with stock hidapi said "open failed".
    public func open() throws {
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw BAKeyError.openFailed(r) }
    }

    public func close() {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Sends a feature report. `packet.bytes[0]` is the report ID (hidapi convention):
    /// with ID 0 the byte is stripped before handing it to IOKit, otherwise it is sent as-is.
    public func setFeature(_ packet: Packet) throws {
        var data = packet.bytes
        data[0] = reportID
        if reportID == 0 { data.removeFirst() }
        let r = data.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), $0.baseAddress!, $0.count)
        }
        guard r == kIOReturnSuccess else { throw BAKeyError.ioFailed("SetReport", r) }
    }

    /// Reads the feature report back. The result always has the report ID at [0].
    public func getFeature() throws -> Packet {
        var buf = [UInt8](repeating: 0, count: BAKey.reportLength)
        var len: CFIndex
        let r: IOReturn
        if reportID == 0 {
            len = CFIndex(BAKey.payloadLength)
            r = buf.withUnsafeMutableBufferPointer {
                IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress! + 1, &len)
            }
        } else {
            buf[0] = reportID
            len = CFIndex(BAKey.reportLength)
            r = buf.withUnsafeMutableBufferPointer {
                IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), $0.baseAddress!, &len)
            }
            // Some stacks return the report without its ID byte.
            if r == kIOReturnSuccess && len == BAKey.payloadLength && buf[0] != reportID {
                buf = [reportID] + buf.prefix(BAKey.payloadLength)
            }
        }
        guard r == kIOReturnSuccess else { throw BAKeyError.ioFailed("GetReport", r) }
        return Packet(bytes: buf)
    }
}

/// Finds BA-KEY308 devices and reports plug/unplug (and Bluetooth connect/disconnect).
public final class DeviceMonitor: @unchecked Sendable {
    private let manager: IOHIDManager
    /// Called on the main run loop whenever a matching device appears or disappears.
    public var onChange: (() -> Void)?

    public init(scheduleOnMainRunLoop: Bool = true) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [BAKey.keyboardPID, BAKey.donglePID].map {
            [kIOHIDVendorIDKey as String: BAKey.vendorID, kIOHIDProductIDKey as String: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        guard scheduleOnMainRunLoop else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { ctx, _, _, _ in
            guard let ctx else { return }
            Unmanaged<DeviceMonitor>.fromOpaque(ctx).takeUnretainedValue().onChange?()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Devices that expose the configuration channel, the keyboard itself first
    /// (Bluetooth or cable), then the 2.4G receiver.
    public func candidates() -> [HIDDevice] {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.compactMap(HIDDevice.init(device:))
            .sorted { a, b in (a.isReceiver ? 1 : 0, a.transport) < (b.isReceiver ? 1 : 0, b.transport) }
    }
}
