import BAKeyCore
import Foundation

/// Owns the `KeyboardClient` and runs every HID call on one serial queue.
///
/// HID transactions are blocking (a GET over Bluetooth takes ~100-300 ms), so they must
/// never run on the main thread, and two of them must never interleave: the firmware
/// answers one request at a time through the same feature report.
final class HIDWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "BAKeyMenu.hid", qos: .userInitiated)
    private var client: KeyboardClient?

    /// Runs `body` on the HID queue with the connected client.
    func run<T>(_ body: @escaping (KeyboardClient) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let c = self.client else { return cont.resume(throwing: BAKeyError.noDevice) }
                do { cont.resume(returning: try body(c)) } catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Opens the first candidate that answers a firmware-version query.
    func connect(to candidates: [HIDDevice]) async throws -> DeviceInfo {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.client = nil
                var lastError: Error = BAKeyError.noDevice
                for hid in candidates {
                    do {
                        let c = try KeyboardClient(hid: hid)
                        let info = try c.info()
                        self.client = c
                        return cont.resume(returning: info)
                    } catch {
                        lastError = error
                    }
                }
                cont.resume(throwing: lastError)
            }
        }
    }

    func disconnect() {
        queue.async { self.client = nil }
    }
}
