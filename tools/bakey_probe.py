"""Minimal BA-KEY308 (Dareu TK51G_0130) config-channel driver for macOS.
Uses Homebrew libhidapi via ctypes, non-exclusive open (no seize)."""
import ctypes, time

VID, PID = 0x260D, 0x0130
LIB = ctypes.CDLL("/opt/homebrew/lib/libhidapi.dylib")


class _Info(ctypes.Structure):
    pass


_Info._fields_ = [
    ("path", ctypes.c_char_p), ("vid", ctypes.c_ushort), ("pid", ctypes.c_ushort),
    ("sn", ctypes.c_wchar_p), ("rel", ctypes.c_ushort), ("mfr", ctypes.c_wchar_p),
    ("prod", ctypes.c_wchar_p), ("up", ctypes.c_ushort), ("u", ctypes.c_ushort),
    ("iface", ctypes.c_int), ("next", ctypes.POINTER(_Info)), ("bus", ctypes.c_int),
]
LIB.hid_enumerate.restype = ctypes.POINTER(_Info)
LIB.hid_open_path.restype = ctypes.c_void_p
LIB.hid_send_feature_report.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
LIB.hid_get_feature_report.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
LIB.hid_close.argtypes = [ctypes.c_void_p]
LIB.hid_error.restype = ctypes.c_wchar_p
LIB.hid_error.argtypes = [ctypes.c_void_p]
LIB.hid_init()
LIB.hid_darwin_set_open_exclusive(0)


class Keyboard:
    def __init__(self, report_id=None):
        p = LIB.hid_enumerate(VID, PID)
        self.h = None
        while p:
            i = p.contents
            if i.up == 0x0C and i.u == 0x01:
                self.h = LIB.hid_open_path(i.path)
                bus = i.bus
                break
            p = i.next
        if not self.h:
            raise SystemExit("BA-KEY308 config interface not found / open failed")
        # BLE descriptor uses report ID 7; USB (per decompiled app) uses 0.
        self.rid = report_id if report_id is not None else (7 if bus == 2 else 0)

    def close(self):
        LIB.hid_close(self.h)

    def xfer(self, cls, cmd, length=0, profile=0, payload=b"", wait=True):
        buf = bytearray(65)
        buf[0] = self.rid
        buf[2], buf[3], buf[4], buf[5] = length, cls, cmd, profile
        buf[7:7 + len(payload)] = payload
        if LIB.hid_send_feature_report(self.h, bytes(buf), 65) < 0:
            raise IOError(f"send failed: {LIB.hid_error(self.h)}")
        if not wait:
            return None
        rb = ctypes.create_string_buffer(65)
        last = None
        for _ in range(60):
            time.sleep(0.01)
            rb[0] = bytes([self.rid])
            n = LIB.hid_get_feature_report(self.h, rb, 65)
            if n < 0:
                raise IOError(f"get failed: {LIB.hid_error(self.h)}")
            r = rb.raw[:n]
            # On macOS the returned buffer may or may not include the report ID byte.
            if r and r[0] != self.rid and n == 64:
                r = bytes([self.rid]) + r
            last = r
            st = r[1] & 0x0F
            if st == 2 and r[3] == cls and r[4] == cmd:
                return r
            if st == 5:
                raise NotImplementedError("command not supported by firmware")
        raise TimeoutError(f"no ready response, last={last[:16].hex(' ') if last else None}")

    def get(self, cls, cmd, length=0, profile=0, payload=b""):
        assert cmd & 0x80
        return self.xfer(cls, cmd, length, profile, payload)
