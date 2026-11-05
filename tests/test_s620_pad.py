import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import struct
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("s620_pad", str(ROOT / "s620-pad"))
spec = importlib.util.spec_from_loader("s620_pad", loader)
s620_pad = importlib.util.module_from_spec(spec)
loader.exec_module(s620_pad)


def make_node(sysfs, name, vendor, product, device_name, uniq=""):
    device = sysfs / name / "device"
    (device / "id").mkdir(parents=True)
    (device / "id" / "vendor").write_text(vendor + "\n")
    (device / "id" / "product").write_text(product + "\n")
    (device / "name").write_text(device_name + "\n")
    (device / "uniq").write_text(uniq + "\n")


def event(kind, code, value):
    return struct.pack("llHHi", 0, 0, kind, code, value)


class FindDeviceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sysfs = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    # Nodes as hid-uclogic created them on 2026-10-24 (docs/re/findings.md).
    def test_picks_the_pad_among_the_tablet_nodes(self):
        make_node(self.sysfs, "event22", "256c", "006d", "GAOMON Gaomon Tablet Pen")
        make_node(self.sysfs, "event23", "256c", "006d", "GAOMON Gaomon Tablet Pad")
        make_node(self.sysfs, "event24", "256c", "006d", "GAOMON Gaomon Tablet Touch Strip")
        self.assertEqual(s620_pad.find_device(self.sysfs), "/dev/input/event23")

    def test_ignores_pads_of_other_tablets(self):
        make_node(self.sysfs, "event5", "256c", "006e", "HUION Tablet Pad")
        self.assertIsNone(s620_pad.find_device(self.sysfs))

    def test_sorts_event_nodes_numerically(self):
        make_node(self.sysfs, "event9", "256c", "006d", "GAOMON Gaomon Tablet Pad")
        make_node(self.sysfs, "event10", "256c", "006d", "GAOMON Gaomon Tablet Pad")
        self.assertEqual(s620_pad.find_device(self.sysfs), "/dev/input/event9")


class FirmwareTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sysfs = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    # hid-uclogic puts the firmware name in every node's uniq (docs/re/findings.md).
    def test_reads_the_firmware_from_the_pad_node(self):
        make_node(self.sysfs, "event23", "256c", "006d", "GAOMON Gaomon Tablet Pad", "OEM02_T18e_200919")
        self.assertEqual(s620_pad.read_firmware("/dev/input/event23", self.sysfs), "OEM02_T18e_200919")

    def test_empty_when_the_node_is_gone(self):
        self.assertEqual(s620_pad.read_firmware("/dev/input/event23", self.sysfs), "")


class DecodeTest(unittest.TestCase):
    def test_key_press_and_release(self):
        data = event(1, 0x100, 1) + event(0, 0, 0) + event(1, 0x100, 0) + event(0, 0, 0)
        self.assertEqual(s620_pad.decode(data), [
            {"event": "key", "code": 0x100, "pressed": True},
            {"event": "key", "code": 0x100, "pressed": False},
        ])

    def test_drops_axes_sync_and_autorepeat(self):
        data = event(3, 0, 1) + event(4, 4, 0xF0) + event(1, 0x101, 2)
        self.assertEqual(s620_pad.decode(data), [])

    def test_ignores_a_partial_event(self):
        self.assertEqual(s620_pad.decode(event(1, 0x100, 1)[:20]), [])


class SaveTest(unittest.TestCase):
    def test_saves_atomically(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "gaomon-s620" / "profile.json"
            s620_pad.save_profile({"rotation": 2}, path)
            self.assertEqual(json.loads(path.read_text()), {"rotation": 2})
            self.assertFalse(path.with_suffix(".tmp").exists())


if __name__ == "__main__":
    unittest.main()


def make_otd_node(sysfs, name="event30"):
    # As OTD 0.6.7 creates it: vendor/product 0000 under /devices/virtual/input/.
    device = sysfs / name / "device"
    (device / "id").mkdir(parents=True)
    (device / "id" / "vendor").write_text("0000\n")
    (device / "id" / "product").write_text("0000\n")
    (device / "name").write_text("OpenTabletDriver Virtual Artist Tablet\n")


def make_usb(root, name="3-2", vendor="256c", product="006d"):
    device = root / name
    device.mkdir(parents=True)
    (device / "idVendor").write_text(vendor + "\n")
    (device / "idProduct").write_text(product + "\n")


class DetectBackendTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sysfs = Path(self.tmp.name) / "input"
        self.usb = Path(self.tmp.name) / "usb"
        self.sysfs.mkdir()
        self.usb.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def test_kernel_nodes_mean_the_kernel_backend(self):
        make_node(self.sysfs, "event22", "256c", "006d", "GAOMON Gaomon Tablet Pen")
        make_node(self.sysfs, "event23", "256c", "006d", "GAOMON Gaomon Tablet Pad")
        self.assertEqual(s620_pad.detect_backend(self.sysfs, self.usb), "kernel")

    def test_kernel_wins_when_both_are_there(self):
        make_node(self.sysfs, "event22", "256c", "006d", "GAOMON Gaomon Tablet Pen")
        make_otd_node(self.sysfs)
        make_usb(self.usb)
        self.assertEqual(s620_pad.detect_backend(self.sysfs, self.usb), "kernel")

    def test_usb_plus_the_otd_tablet_is_the_otd_backend(self):
        make_usb(self.usb)
        make_otd_node(self.sysfs)
        self.assertEqual(s620_pad.detect_backend(self.sysfs, self.usb), "otd")

    def test_hid_generic_node_is_not_the_kernel_backend(self):
        # With hid_uclogic blocked by the OTD package, hid-generic binds the
        # tablet and makes one "GAOMON Gaomon Tablet" node (seen 2026-10-25).
        make_usb(self.usb)
        make_node(self.sysfs, "event20", "256c", "006d", "GAOMON Gaomon Tablet")
        make_otd_node(self.sysfs)
        self.assertEqual(s620_pad.detect_backend(self.sysfs, self.usb), "otd")

    def test_usb_alone_has_no_driver(self):
        make_usb(self.usb)
        self.assertEqual(s620_pad.detect_backend(self.sysfs, self.usb), "no-driver")

    def test_nothing_is_missing(self):
        self.assertEqual(s620_pad.detect_backend(self.sysfs, self.usb), "missing")
        # A leftover OTD virtual tablet without the USB device is not a tablet.
        make_otd_node(self.sysfs)
        self.assertEqual(s620_pad.detect_backend(self.sysfs, self.usb), "missing")


FAKE_OTD = """#!/bin/sh
# A fake `otd`: savesettings copies the store to $2, loadsettings copies
# $2 over the store. Anything else fails.
case "$1" in
  savesettings) cp "$FAKE_OTD_STORE" "$2" ;;
  loadsettings) cp "$2" "$FAKE_OTD_STORE" ;;
  *) exit 1 ;;
esac
"""


class OtdCommandsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.store = root / "store.json"
        self.store.write_text('{"Profiles": []}\n')
        self.otd = root / "otd"
        self.otd.write_text(FAKE_OTD)
        self.otd.chmod(0o755)
        self.env = dict(os.environ, FAKE_OTD_STORE=str(self.store))

    def tearDown(self):
        self.tmp.cleanup()

    def test_otd_read_returns_the_running_settings(self):
        self.assertEqual(s620_pad.otd_read(str(self.otd), self.env), '{"Profiles": []}\n')

    def test_otd_apply_loads_then_persists(self):
        target = Path(self.tmp.name) / "persisted" / "settings.json"
        s620_pad.otd_apply({"Profiles": [{"Tablet": "Gaomon S620"}]}, str(self.otd), target, self.env)
        self.assertEqual(json.loads(target.read_text()), {"Profiles": [{"Tablet": "Gaomon S620"}]})
        self.assertEqual(json.loads(self.store.read_text()), {"Profiles": [{"Tablet": "Gaomon S620"}]})

    def test_otd_apply_refuses_a_non_object(self):
        target = Path(self.tmp.name) / "settings.json"
        with self.assertRaises(ValueError):
            s620_pad.otd_apply([1, 2], str(self.otd), target, self.env)


def make_otd_pad(sysfs, name="event31"):
    # The virtual pad OTD 0.6.7 creates once a LinuxArtistModePadBinding is in
    # the settings: name only, vendor/product 0000, empty uniq.
    device = sysfs / name / "device"
    (device / "id").mkdir(parents=True)
    (device / "id" / "vendor").write_text("0000\n")
    (device / "id" / "product").write_text("0000\n")
    (device / "name").write_text("OpenTabletDriver Virtual Pad\n")
    (device / "uniq").write_text("\n")


class FindOtdPadTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sysfs = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_finds_the_virtual_pad(self):
        make_otd_pad(self.sysfs)
        self.assertEqual(s620_pad.find_otd_pad(self.sysfs), "/dev/input/event31")

    def test_absent_until_a_pad_binding_is_set(self):
        make_otd_node(self.sysfs)
        self.assertIsNone(s620_pad.find_otd_pad(self.sysfs))


class WatchStepTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.sysfs = root / "input"
        self.usb = root / "usb"
        self.sysfs.mkdir()
        self.usb.mkdir()
        self.watched = []
        self.error = None
        def fake(device, backend="kernel", root=s620_pad.SYSFS_INPUT,
                 usb_root=s620_pad.SYSFS_USB):
            self.watched.append((device, backend, usb_root))
            if self.error is not None:
                raise self.error
        self.real = s620_pad.watch_device
        s620_pad.watch_device = fake

    def tearDown(self):
        s620_pad.watch_device = self.real
        self.tmp.cleanup()

    def test_watches_the_kernel_pad(self):
        make_node(self.sysfs, "event23", "256c", "006d", "GAOMON Gaomon Tablet Pad")
        self.assertIsNone(s620_pad.watch_step(self.sysfs, self.usb))
        self.assertEqual(self.watched, [("/dev/input/event23", "kernel", self.usb)])

    def test_otd_without_the_pad_is_connected_anyway(self):
        # Before the plugin's bindings are applied the virtual pad is missing
        # for a moment; that is not "tablet disconnected".
        make_usb(self.usb)
        make_otd_node(self.sysfs)
        self.assertEqual(s620_pad.watch_step(self.sysfs, self.usb),
            {"ok": True, "event": "connected", "backend": "otd"})
        self.assertEqual(self.watched, [])

    def test_watches_the_otd_pad(self):
        make_usb(self.usb)
        make_otd_node(self.sysfs)
        make_otd_pad(self.sysfs)
        self.assertIsNone(s620_pad.watch_step(self.sysfs, self.usb))
        self.assertEqual(self.watched, [("/dev/input/event31", "otd", self.usb)])

    def test_access_denied_on_the_otd_pad_carries_the_backend(self):
        make_usb(self.usb)
        make_otd_node(self.sysfs)
        make_otd_pad(self.sysfs)
        self.error = PermissionError("denied")
        self.assertEqual(s620_pad.watch_step(self.sysfs, self.usb),
            {"ok": False, "error": "access-denied", "backend": "otd"})

    def test_access_denied_on_the_kernel_pad_carries_firmware_and_backend(self):
        make_node(self.sysfs, "event23", "256c", "006d", "GAOMON Gaomon Tablet Pad", "OEM02_T18e_200919")
        self.error = PermissionError("denied")
        self.assertEqual(s620_pad.watch_step(self.sysfs, self.usb),
            {"ok": False, "error": "access-denied", "firmware": "OEM02_T18e_200919", "backend": "kernel"})

    def test_missing_and_no_driver_have_no_backend(self):
        self.assertEqual(s620_pad.watch_step(self.sysfs, self.usb), {"ok": False, "error": "missing"})
        make_usb(self.usb)
        self.assertEqual(s620_pad.watch_step(self.sysfs, self.usb), {"ok": False, "error": "no-driver"})


class WatchDeviceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.sysfs = root / "input"
        self.usb = root / "usb"
        self.sysfs.mkdir()
        self.usb.mkdir()
        self.fifo = root / "fifo"
        os.mkfifo(self.fifo)
        # Held open so the descriptor never reads EOF nor raises: without a
        # backend check the loop would wait here forever.
        self.held = os.open(self.fifo, os.O_RDWR | os.O_NONBLOCK)

    def tearDown(self):
        os.close(self.held)
        self.tmp.cleanup()

    def test_returns_when_the_otd_backend_disappears(self):
        # The daemon keeps the virtual pad after the USB device is unplugged
        # (docs/re/opentabletdriver.md), so the read itself never ends; the
        # loop re-detects the backend (~1 s select timeout).
        with contextlib.redirect_stdout(io.StringIO()):
            s620_pad.watch_device(str(self.fifo), "otd", self.sysfs, self.usb)

    def test_returns_when_the_kernel_backend_disappears(self):
        make_node(self.sysfs, "event23", "256c", "006d", "GAOMON Gaomon Tablet Pad")
        (self.sysfs / "event23" / "device" / "id" / "vendor").write_text("gone\n")
        with contextlib.redirect_stdout(io.StringIO()):
            s620_pad.watch_device(str(self.fifo), "kernel", self.sysfs, self.usb)
