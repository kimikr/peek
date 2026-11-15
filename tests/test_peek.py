"""Tests for the peek dev server. Run with `python3 -m unittest discover tests`.

They need only Python and openssl; nothing here compiles Swift.
"""
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_loader = importlib.machinery.SourceFileLoader("peek", str(ROOT / "peek"))
_spec = importlib.util.spec_from_loader("peek", _loader)
peek = importlib.util.module_from_spec(_spec)
_loader.exec_module(peek)

TOKEN = "00112233445566778899aabbccddeeff"


class Trivia(unittest.TestCase):
    def mask(self, src):
        return peek.code_mask(src)

    def test_braces_in_strings_and_comments_are_ignored(self):
        src = 'let a = "{"; /* } */ // }\nfunc f() { g("}") }'
        open_ = src.index("{ g")
        self.assertEqual(peek.match_close(src, open_), len(src) - 1)

    def test_raw_strings(self):
        src = 'x(#"a "quoted" ) brace"#) y'
        self.assertEqual(peek.match_close(src, 1), src.index(") y"))

    def test_multiline_raw_string(self):
        src = 'x(#"""\n ) " \n"""#)'
        self.assertEqual(peek.match_close(src, 1), len(src) - 1)

    def test_interpolation_with_strings_inside(self):
        src = 'x("a \\(d["k"] ?? "}") b") z'
        self.assertEqual(peek.match_close(src, 1), src.index(") z"))

    def test_nested_block_comments(self):
        src = "f(/* a /* b ) */ c ) */ 1)"
        self.assertEqual(peek.match_close(src, 1), len(src) - 1)

    def test_mask_keeps_length_and_newlines(self):
        src = 'a "x\ny" /* \n */ b'
        masked = self.mask(src)
        self.assertEqual(len(masked), len(src))
        self.assertEqual(masked.count("\n"), src.count("\n"))


class Rewrite(unittest.TestCase):
    def check_lines(self, src):
        new, roots, app = peek.rewrite_source(src, "t")
        self.assertEqual(new.count("\n"), src.count("\n"), "line numbers must not move")
        return new, roots, app

    def test_preview_becomes_struct(self):
        new, roots, _ = self.check_lines('#Preview("Hello") {\n    Text("hi")\n}\n')
        self.assertEqual(roots, [("__PeekRoot_t_0", "Hello")])
        self.assertIn("struct __PeekRoot_t_0: SwiftUI.View", new)
        self.assertIn("__peekPreview {", new)

    def test_untitled_and_traits(self):
        _, roots, _ = self.check_lines("#Preview(traits: .landscapeLeft) { A() }\n#Preview { B() }\n")
        self.assertEqual([t for _, t in roots], [None, None])

    def test_multiline_previewable(self):
        src = '#Preview {\n    @Previewable @State var items = [\n        1,\n        2,\n    ]\n    List(items) { Text("\\($0)") }\n}\n'
        new, roots, _ = self.check_lines(src)
        self.assertEqual(len(roots), 1)
        self.assertIn("     @State var items = [", new)
        body = new.index("var body")
        self.assertLess(new.index("    ]"), body)
        self.assertIn("var body: some SwiftUI.View { __peekPreview {     List(items)", new)

    def test_preview_inside_string_is_ignored(self):
        _, roots, _ = self.check_lines('let s = "#Preview { X() }"\n')
        self.assertEqual(roots, [])

    def test_app_becomes_view(self):
        src = (
            "@main\nstruct MyApp: App {\n"
            "    @UIApplicationDelegateAdaptor(D.self) var delegate\n"
            "    var body: some Scene {\n"
            '        WindowGroup("Main", id: "m") {\n            ContentView()\n        }\n'
            "        .commands { }\n"
            '        WindowGroup(id: "x", for: String.self) { $v in\n            Detail(v)\n        }\n'
            "        Settings { Prefs() }\n"
            "    }\n}\n")
        new, _, app = self.check_lines(src)
        self.assertEqual(app, "MyApp")
        self.assertIn("struct MyApp: SwiftUI.View", new)
        self.assertIn("@__PeekDelegateAdaptor(D.self)", new)
        self.assertIn("var body: some SwiftUI.View", new)
        self.assertIn("SwiftUI.Group {", new)
        self.assertEqual(new.count("SwiftUI.EmptyView()"), 2)
        self.assertNotIn("Detail(v)", new)
        self.assertIn("ContentView()", new)

    def test_scene_names_inside_content_are_left_alone(self):
        src = "@main struct A: App {\n    var body: some Scene {\n        WindowGroup { Settings() }\n    }\n}\n"
        new, _, _ = self.check_lines(src)
        self.assertIn("Settings()", new)
        self.assertNotIn("EmptyView", new)

    def test_document_group_gets_a_stand_in(self):
        src = "@main struct A: App {\n    var body: some Scene {\n        DocumentGroup(newDocument: D()) { f in V(f) }\n    }\n}\n"
        new, _, _ = self.check_lines(src)
        self.assertIn("__PeekDocumentGroup(newDocument: D()) { f in V(f) }", new)


class Crypto(unittest.TestCase):
    def test_round_trip(self):
        for size in (0, 1, 31, 32, 33, 100_000):
            data = os.urandom(size)
            self.assertEqual(peek.unseal(TOKEN, peek.seal(TOKEN, data)), data)

    def test_tamper_is_detected(self):
        blob = bytearray(peek.seal(TOKEN, b"hello world"))
        blob[20] ^= 1
        with self.assertRaises(ValueError):
            peek.unseal(TOKEN, bytes(blob))

    def test_wrong_key(self):
        with self.assertRaises(ValueError):
            peek.unseal("ff" * 16, peek.seal(TOKEN, b"x"))

    def test_ctr_matches_openssl_vector(self):
        # NIST SP 800-38A F.5.5 (CTR-AES256.Encrypt), first block.
        key = bytes.fromhex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
        nonce = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
        plain = bytes.fromhex("6bc1bee22e409f96e93d7e117393172a")
        self.assertEqual(peek._aes_ctr(key, nonce, plain).hex(), "601ec313775789a5b7a7f504bbf3d228")

    def test_auth_covers_bundle_header(self):
        a = peek.auth_message("GET", "/v1/state", 1, b"", "com.a", "phone")
        b = peek.auth_message("GET", "/v1/state", 1, b"", "com.b", "phone")
        self.assertNotEqual(a, b)


class Hardening(unittest.TestCase):
    def test_control_characters_are_removed(self):
        self.assertEqual(peek.printable("a\x1b[2Jb\x07c\td"), "a[2Jbc\td")

    def test_private_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "secret"
            old = os.umask(0)
            try:
                peek.write_private(path, b"x")
            finally:
                os.umask(old)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_settings_with_odd_shapes_are_skipped(self):
        package = peek.Package.__new__(peek.Package)
        package.root, package.tc = Path("/nonexistent"), None
        # settings() reads `swift package dump-package`; feed it through a fake subprocess.
        manifest = {"toolsVersion": {"_version": "6.0.0"}, "targets": [{"name": "T", "settings": [
            {"tool": "swift", "kind": {"define": {"_0": "FLAG"}}},
            {"tool": "swift", "kind": {"a": 1, "b": 2}},
            {"tool": "swift", "kind": "weird"},
            {"tool": "swift", "kind": {"define": {"_0": "MAC"}}, "condition": {"platformNames": ["macos"]}},
            {"tool": "linker", "kind": {"unsafeFlags": {"_0": ["-Xlinker", "-x"]}}},
        ]}]}
        real = peek.subprocess.run
        peek.subprocess.run = lambda *a, **k: subprocess.CompletedProcess(a, 0, json.dumps(manifest), "")
        package.tc = type("TC", (), {"swift_env": lambda self: {}})()
        try:
            package.settings(Path("swift"), "T")
        finally:
            peek.subprocess.run = real
        self.assertEqual(package.language_mode, "6")
        self.assertEqual(package.swift_flags, ["-D", "FLAG"])
        self.assertEqual(package.link_flags, ["-Xlinker", "-x"])


class Versions(unittest.TestCase):
    """The app and the script must agree, or a release ships a pair that cannot talk."""

    def test_app_matches_script(self):
        swift = (ROOT / "host/Sources/Peek/Session.swift").read_text()
        plist = (ROOT / "host/Peek-Info.plist").read_text()
        self.assertIn(f'static let app = "{peek.VERSION}"', swift)
        self.assertIn(f"static let proto = {peek.PROTOCOL}", swift)
        self.assertRegex(plist, rf"CFBundleShortVersionString</key>\s*<string>{re.escape(peek.VERSION)}</string>")


class HotPatch(unittest.TestCase):
    BASE = (
        "import SwiftUI\n\n"
        "struct ContentView: View {\n"
        "    @State private var count = 0\n"
        "    let title = \"Hi\"\n"
        "    var body: some View {\n"
        "        Button(\"\\(count)\") { count += 1 }\n"
        "    }\n"
        "    private func label(for value: Int, _ suffix: String = \"!\") -> String { String(value) + suffix }\n"
        "}\n\n"
        "extension ContentView where Self: Sendable {\n"
        "    func extra() async throws -> Int { 2 }\n"
        "}\n")

    def patch(self, new):
        return peek.patch_sources(self.BASE, new, "abc_ContentView.swift", 7)

    def test_body_edit_becomes_replacement(self):
        source, count = self.patch(self.BASE.replace("count += 1", "count += 2"))
        self.assertEqual(count, 1)
        self.assertIn('@_private(sourceFile: "abc_ContentView.swift") import PeekPreview', source)
        self.assertIn("import SwiftUI", source)
        self.assertIn("@_dynamicReplacement(for: body)", source)
        self.assertIn("@SwiftUI.ViewBuilder", source)
        self.assertIn("count += 2", source)

    def test_function_selector_and_defaults(self):
        source, _ = self.patch(self.BASE.replace("String(value) + suffix", "suffix + String(value)"))
        self.assertIn("@_dynamicReplacement(for: label(for:_:))", source)
        self.assertIn("private func __peekr7_label(for value: Int, _ suffix: String) -> String", source)

    def test_constrained_extension_keeps_where(self):
        source, _ = self.patch(self.BASE.replace("{ 2 }", "{ 3 }"))
        self.assertIn("extension ContentView where Self: Sendable {", source)
        self.assertIn("async throws -> Int", source)

    def test_structural_edits_need_a_full_build(self):
        self.assertIsNone(self.patch(self.BASE.replace('title = "Hi"', 'title = "Ho"')))
        self.assertIsNone(self.patch(self.BASE.replace("    let title", "    var other = 1\n    let title")))
        self.assertIsNone(self.patch(self.BASE.replace("func label(for value", "func label(at value")))

    def test_comment_only_edit_outside_bodies_changes_nothing(self):
        source, count = self.patch(self.BASE.replace("struct ContentView", "// hello\nstruct ContentView"))
        self.assertEqual(count, 0)

    def test_stored_property_right_before_body(self):
        src = ("struct V: View {\n    @Environment(Player.self) private var player: Player\n"
               "    @ViewBuilder private var extra: some View { Text(\"a\") }\n"
               "    var body: some View { Text(\"x\") }\n}\n")
        _, members = peek.swift_members(src)
        self.assertEqual([(m["name"], m["prefix"]) for m in members], [("extra", "@ViewBuilder private"), ("body", "")])
        source, count = peek.patch_sources(src, src.replace('Text("x")', 'Text("y")'), "f.swift", 1)
        self.assertEqual(count, 1)
        self.assertIn("@_dynamicReplacement(for: body)", source)
        self.assertNotIn("player", source)

    def test_views_read_the_generation(self):
        new, _, _ = peek.rewrite_source("struct A: View {\n var body: some View { Text(\"a\") }\n}\n"
                                        "struct B: View, Equatable {\n var body: some View { Text(\"b\") }\n}\n")
        self.assertIn("struct A: View { @SwiftUI.Environment(\\.__peekGeneration)", new)
        self.assertNotIn("Equatable { @SwiftUI.Environment", new)


class Assets(unittest.TestCase):
    def test_colour_sets(self):
        with tempfile.TemporaryDirectory() as tmp:
            colorset = Path(tmp) / "A.xcassets" / "Brand.colorset"
            colorset.mkdir(parents=True)
            (colorset / "Contents.json").write_text(json.dumps({"colors": [
                {"idiom": "universal", "color": {"color-space": "srgb",
                 "components": {"red": "0xFF", "green": "128", "blue": "0.250", "alpha": "1.000"}}},
                {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}],
                 "color": {"platform": "ios", "reference": "systemBlueColor"}},
                {"idiom": "universal", "appearances": [{"appearance": "contrast", "value": "high"}],
                 "color": {"components": {"red": "0", "green": "0", "blue": "0", "alpha": "1"}}}]}))
            colors = peek.asset_colors([Path(tmp) / "A.xcassets"])
        self.assertEqual(colors["Brand"]["any"], ("srgb", 1.0, 128 / 255, 0.25, 1.0))
        self.assertEqual(colors["Brand"]["dark"], ("system", "systemBlueColor"))
        source = peek.colors_source(colors)
        self.assertIn('case "Brand": return UIColor { $0.userInterfaceStyle == .dark ?', source)

    def test_lookups_by_name_are_rewritten(self):
        src = ('Image("Logo"); Color("Brand"); Color("Brand", bundle: .main); UIColor(named: "Brand")\n'
               'Image("Other"); Color("Nope") // Image("Logo")\nlet s = "Color(\\"Brand\\")"\n')
        out = peek.use_assets(src, {"Logo"}, {"Brand": {}})
        self.assertIn('Image("Logo", bundle: .module); __peekColor("Brand"); __peekColor("Brand"); __peekUIColor("Brand")', out)
        self.assertIn('Image("Other"); Color("Nope") // Image("Logo")', out)
        self.assertIn('let s = "Color(\\"Brand\\")"', out)


class PackageEdits(unittest.TestCase):
    def test_only_dependency_sources(self):
        package = peek.Package.__new__(peek.Package)
        package.dep_dirs = [Path("/p/Sources/Shared"), Path("/p/Packages/Forecast")]
        only = package.only_dependency_sources
        self.assertTrue(only([Path("/p/Sources/Shared/Models.swift")]))
        self.assertTrue(only([Path("/p/Packages/Forecast/Sources/Forecast/A.swift")]))
        self.assertFalse(only([Path("/p/Package.swift")]))
        self.assertFalse(only([Path("/p/Sources/Shared/Resources/a.png")]))
        self.assertFalse(only([Path("/p/Sources/Shared/Models.swift"), Path("/p/Package.resolved")]))
        self.assertFalse(only([]))


class Archive(unittest.TestCase):
    def test_unpack_bsd_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)

            def member(name, body):
                long = name.encode()
                header = f"#1/{len(long)}".ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) \
                    + "644".ljust(8) + str(len(long) + len(body)).ljust(10) + "`\n"
                data = header.encode() + long + body
                return data + (b"\n" if len(data) % 2 else b"")

            archive = tmp / "Mod.o"
            archive.write_bytes(b"!<arch>\n" + member("__.SYMDEF SORTED", b"xx") + member("Mod.o", b"\xcf\xfa\xed\xfeABC"))
            out = tmp / "out"
            out.mkdir()
            found = peek.unpack_object(archive, out)
            self.assertEqual(len(found), 1)
            self.assertEqual(found[0].read_bytes(), b"\xcf\xfa\xed\xfeABC")

    def test_unpack_gnu_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)

            def member(name, body):
                header = name.ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) + "644".ljust(8) \
                    + str(len(body)).ljust(10) + "`\n"
                data = header.encode() + body
                return data + (b"\n" if len(data) % 2 else b"")

            long_name = "a_rather_long_object_name.o"
            archive = tmp / "libX.a"
            archive.write_bytes(b"!<arch>\n" + member("/", b"\0\0\0\0") + member("//", long_name.encode() + b"/\n")
                                + member("/0", b"LONG") + member("short.o/", b"SHORT"))
            out = tmp / "out"
            out.mkdir()
            found = peek.unpack_object(archive, out)
            self.assertEqual(sorted(p.read_bytes() for p in found), [b"LONG", b"SHORT"])
            self.assertTrue(any(long_name in p.name for p in found))

    def test_plain_object_is_returned_as_is(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.o"
            path.write_bytes(b"\xcf\xfa\xed\xfe")
            self.assertEqual(peek.unpack_object(path, Path(tmp)), [path])


class QR(unittest.TestCase):
    def test_sizes(self):
        self.assertEqual(len(peek.qr_matrix("hi")), 21)
        link = "peek://connect?h=192.168.1.20:8765&h=100.101.102.103:8765&k=" + "a" * 32
        self.assertEqual(len(peek.qr_matrix(link)) % 4, 1)

    @unittest.skipUnless(shutil.which("zbarimg"), "zbarimg not installed")
    def test_decodes(self):
        text = "peek://connect?h=10.0.0.2:8765&k=" + "b" * 32
        grid = peek.qr_matrix(text)
        scale, margin = 8, 4
        size = (len(grid) + 2 * margin) * scale
        rows = []
        for y in range(size):
            row = bytearray()
            for x in range(size):
                gx, gy = x // scale - margin, y // scale - margin
                dark = 0 <= gx < len(grid) and 0 <= gy < len(grid) and grid[gy][gx]
                row.append(0 if dark else 255)
            rows.append(bytes(row))
        with tempfile.NamedTemporaryFile(suffix=".pgm") as f:
            f.write(f"P5 {size} {size} 255\n".encode() + b"".join(rows))
            f.flush()
            out = subprocess.run(["zbarimg", "-q", "--raw", f.name], capture_output=True, text=True).stdout.strip()
        self.assertEqual(out, text)


class FakeSigner:
    ready, info, identifier = True, {"team": "TEAM123456", "name": "test"}, None

    def key(self):
        return "k"

    def adopt(self, identifier):
        changed = identifier and identifier != self.identifier
        self.identifier = identifier or self.identifier
        return bool(changed)

    def sign(self, path):
        return path


class FakeBuilder:
    name = "Fake"
    hot, base, force_full, patch_error = True, None, False, None

    def __init__(self, folder):
        self.folder = folder
        self.builds = 0

    def build(self, version, sign_key=""):
        self.builds += 1
        dylib = self.folder / f"peek_{version}.dylib"
        dylib.write_bytes(b"dylib %d" % version)
        deps = self.folder / "PeekDeps-abc.dylib"
        deps.write_bytes(b"deps")
        return {"ok": True, "dylib": dylib, "roots": ["A"], "seconds": 0.1, "resources": [],
                "deps": ("abc", deps)}


class Server(unittest.TestCase):
    """Talks to the HTTP handler the way the phone does."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        folder = Path(self.tmp.name)
        self.state_dir, peek.STATE_DIR = peek.STATE_DIR, folder  # keep the real ~/.peek out of tests
        (folder / "PeekDeps-abc.signed.dylib").write_bytes(b"signed deps")
        peek.log = lambda *a, **k: None
        self.hub = peek.Hub(FakeBuilder(folder), FakeSigner(), TOKEN)
        self.hub.rebuild()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), peek.make_handler(self.hub))
        self.server.daemon_threads = True
        self.server.handle_error = lambda *a: None
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        peek.STATE_DIR = self.state_dir
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def call(self, method, path, body=b"", bundle="com.example.host", device="phone", tamper=None, extra=None):
        headers = {"X-Peek-Auth": peek.auth_header(TOKEN, method, path, body, bundle, device),
                   "X-Peek-Bundle": tamper or bundle, "X-Peek-Device": device,
                   "X-Peek-App": peek.VERSION, "X-Peek-Protocol": str(peek.PROTOCOL), **(extra or {})}
        request = urllib.request.Request(self.base + path, data=body if method == "POST" else None,
                                         method=method, headers=headers)
        with urllib.request.urlopen(request, timeout=10) as response:
            data = response.read()
            if response.headers["Content-Type"] == peek.SEALED_TYPE:
                data = peek.unseal(TOKEN, data)
            return data

    def test_state_is_sealed_and_has_deps(self):
        state = json.loads(self.call("GET", "/v1/state?after=-1&wait=0"))
        self.assertEqual(state["status"], "ready")
        self.assertEqual(state["deps"]["id"], "abc")
        self.assertEqual(self.call("GET", "/v1/deps/abc"), b"signed deps")
        self.assertEqual(self.call("GET", f"/v1/dylib/{state['version']}"), b"dylib %d" % state["version"])

    def test_unauthenticated_requests_fail(self):
        with self.assertRaises(urllib.error.HTTPError) as e:
            urllib.request.urlopen(self.base + "/v1/state", timeout=5)
        self.assertEqual(e.exception.code, 401)

    def test_bundle_header_cannot_be_swapped(self):
        with self.assertRaises(urllib.error.HTTPError) as e:
            self.call("GET", "/v1/state?after=-1&wait=0", tamper="com.attacker")
        self.assertEqual(e.exception.code, 401)

    def test_new_bundle_identifier_triggers_a_rebuild(self):
        before = self.hub.builder.builds
        self.call("GET", "/v1/state?after=-1&wait=0", bundle="com.other")
        self.assertEqual(self.hub.signer.identifier, "com.other")
        self.assertEqual(self.hub.builder.builds, before + 1)

    def test_long_poll_wakes_on_new_build(self):
        state = json.loads(self.call("GET", "/v1/state?after=-1&wait=0"))
        threading.Timer(0.3, self.hub.rebuild).start()
        started = time.time()
        newer = json.loads(self.call("GET", f"/v1/state?after={state['version']}&wait=10"))
        self.assertGreater(newer["version"], state["version"])
        self.assertLess(time.time() - started, 5)

    def test_screenshot_round_trip(self):
        state = json.loads(self.call("GET", "/v1/state?after=-1&wait=0"))
        png = b"\x89PNG fake"

        def phone():
            # Long-polls like the app and answers the request it sees.
            seen = json.loads(self.call("GET", f"/v1/state?after={state['version']}&shot={state['shot']}&wait=10"))
            self.call("POST", f"/v1/shot?n={seen['shot']}", body=peek.seal(TOKEN, png))

        threading.Thread(target=phone, daemon=True).start()
        self.assertEqual(self.call("POST", "/v1/shot-request", device="peek-cli", bundle=""), png)

    def test_bad_content_length_is_refused_without_reading(self):
        import socket
        for value in (b"-1", b"abc", str(1 << 30).encode()):
            with socket.create_connection(self.server.server_address, timeout=5) as sock:
                sock.sendall(b"POST /v1/log HTTP/1.1\r\nHost: x\r\nContent-Length: " + value + b"\r\n\r\n")
                self.assertRegex(sock.recv(100), rb"HTTP/1\.[01] (400|413)")

    def test_vanished_build_is_reported_stale(self):
        state = json.loads(self.call("GET", "/v1/state?after=-1&wait=0"))
        self.hub.dylib.unlink()
        with self.assertRaises(urllib.error.HTTPError) as e:
            self.call("GET", f"/v1/dylib/{state['version']}")
        self.assertEqual(e.exception.code, 404)

    def test_crashing_build_is_published_as_an_error(self):
        def boom(version, sign_key=""):
            raise FileNotFoundError("gone")
        self.hub.builder.build = boom
        self.hub.rebuild()
        state = json.loads(self.call("GET", "/v1/state?after=-1&wait=0"))
        self.assertEqual(state["status"], "error")
        self.assertIn("gone", state["diagnostics"])

    def test_versions(self):
        state = json.loads(self.call("GET", "/v1/state?after=-1&wait=0"))
        self.assertEqual((state["protocol"], state["peek"]), (peek.PROTOCOL, peek.VERSION))
        # Other protocol numbers, including 0.1.x apps that send none (protocol 1), get a clear refusal.
        for headers in ({"X-Peek-App": "9.0", "X-Peek-Protocol": "9"}, {"X-Peek-App": "0.1.0", "X-Peek-Protocol": "1"}):
            with self.assertRaises(urllib.error.HTTPError) as e:
                self.call("GET", "/v1/state?after=-1&wait=0", extra=headers)
            self.assertEqual(e.exception.code, 426)
            self.assertEqual(json.loads(e.exception.read())["peek"], peek.VERSION)

    def test_phone_without_the_base_build_gets_a_full_build(self):
        self.call("GET", "/v1/state?after=-1&wait=0")  # the server learns the bundle identifier (one rebuild)
        self.hub.publish({"status": "ready", "roots": ["A"], "file": "peek_x_2.dylib",
                          "patch": {"base": 1, "baseFile": "peek_x_1.dylib"}}, self.hub.dylib, self.hub.deps)
        before = self.hub.builder.builds
        self.call("GET", "/v1/state?after=-1&wait=0", extra={"X-Peek-Base": "peek_x_1.dylib"})
        time.sleep(0.3)
        self.assertEqual(self.hub.builder.builds, before)
        self.call("GET", "/v1/state?after=-1&wait=0", extra={"X-Peek-Base": ""})
        for _ in range(20):
            if self.hub.builder.builds > before:
                break
            time.sleep(0.1)
        self.assertEqual(self.hub.builder.builds, before + 1)
        self.assertNotIn("patch", self.hub.state)

    def test_output_is_accepted(self):
        body = json.dumps({"level": "print", "output": "hello\nworld\n"}).encode()
        self.assertEqual(json.loads(self.call("POST", "/v1/log", body=body)), {})


if __name__ == "__main__":
    unittest.main()
