#!/usr/bin/env python3
"""Exercise the current iOS journal implementation on macOS with invented data.

Run from app/: python3 tool/check_ai1_native_store.py
Requires macOS and an installed Swift compiler, but no Python packages. The
production class is extracted at runtime; its sole Application Support lookup
is replaced with a compile-time, guarded TemporaryDirectory. Neither the app
nor its ordinary storage is opened. Every request uses an independent process.

This checks host behavior, not iOS Data Protection, crash recovery, or power-loss
durability. The temporary compiler cache, binary, and invented journals are
deleted on completion. No input-file or storage-root option is accepted.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time


MAXIMUM_BYTES = 4 * 1024 * 1024
SOURCE = Path(__file__).resolve().parents[1] / "ios/Runner/AppDelegate.swift"
ROOT_LOOKUP = """    guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw StoreError.persistence
    }"""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def extract_store() -> tuple[str, str]:
    text = SOURCE.read_text(encoding="utf-8")
    marker = "private final class Ai1CaptureFileStore {"
    require(text.count(marker) == 1, "Expected one production journal class")
    # The current class is the last declaration. Fail closed when this layout
    # changes; never silently compile a different implementation or more code.
    source = text[text.index(marker):].strip()
    require(source.endswith("}"), "Journal class boundary changed")
    require(source.count(ROOT_LOOKUP) == 1, "Application Support lookup changed")
    # Braces in current string interpolation balance too. Comments are removed
    # before this conservative boundary check; no trailing declaration is allowed.
    depth = 0
    uncommented = re.sub(r"//[^\n]*", "", source)
    for index, char in enumerate(uncommented):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            require(depth >= 0, "Unbalanced extracted class")
            if depth == 0:
                tail = uncommented[index + 1:]
                require(not tail.strip(), "Unexpected code after journal class")
    require(depth == 0, "Unbalanced extracted class")
    digest = hashlib.sha256(source.encode()).hexdigest()
    source = source.replace(ROOT_LOOKUP, "    let support = try HarnessPaths.applicationSupport()")
    for forbidden in (
        "applicationSupportDirectory", "userDomainMask", "homeDirectory",
        "NSHomeDirectory", "NSApplicationSupportDirectory", "ProcessInfo",
        "URL(fileURLWithPath:", "FileManager(", "NSTemporaryDirectory",
    ):
        require(forbidden not in source, f"Unexpected storage escape API: {forbidden}")
    return source, digest


def swift_program(store: str, root: Path) -> str:
    # JSON quoting is valid for this ASCII, generated path in a Swift string.
    root_literal = json.dumps(str(root))
    return r'''
import Foundation
import CryptoKit
import Darwin

typealias FlutterResult = (Any?) -> Void
struct FlutterMethodCall { let method: String; let arguments: Any? }
struct FlutterError { let code: String; let message: String?; let details: Any? }
private struct MethodNotImplemented {}
private let FlutterMethodNotImplemented = MethodNotImplemented()

private enum HarnessPaths {
  static let root = URL(fileURLWithPath: ROOT_LITERAL, isDirectory: true)
  static func expectedCanonicalPath(_ url: URL) -> Bool {
    // Foundation on macOS may spell /private/tmp as /tmp. Permit only this
    // known system alias; the lstat-style attribute check still rejects links
    // at the fresh root and every application-storage component below it.
    let alias = "/tmp/" + url.path.dropFirst("/private/tmp/".count)
    return [url.path, alias].contains(url.resolvingSymlinksInPath().path)
  }
  static func applicationSupport() throws -> URL {
    // The root cannot be selected through arguments or environment variables.
    // Every pre-existing component is checked before production code can act.
    guard root.path.hasPrefix("/private/tmp/tonyo-ai1-native-"),
          root.deletingLastPathComponent().path == "/private/tmp",
          expectedCanonicalPath(root) else { throw GuardError.path("root") }
    let files = FileManager.default
    let marker = root.appendingPathComponent(".synthetic-only")
    guard try String(contentsOf: marker, encoding: .utf8) == root.path else { throw GuardError.path("marker") }
    var current = root
    for component in ["", "data", "Library", "ApplicationSupport", "tonyo-ai1-history"] {
      if !component.isEmpty { current.appendPathComponent(component, isDirectory: true) }
      if files.fileExists(atPath: current.path) || (try? files.destinationOfSymbolicLink(atPath: current.path)) != nil {
        let attributes = try files.attributesOfItem(atPath: current.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              expectedCanonicalPath(current) else { throw GuardError.path("component") }
      }
    }
    return root.appendingPathComponent("data/Library/ApplicationSupport", isDirectory: true)
  }
  enum GuardError: Error { case path(String) }
}
'''.replace("ROOT_LITERAL", root_literal) + "\n" + store + r'''

let input = FileHandle.standardInput.readDataToEndOfFile()
let request = try JSONSerialization.jsonObject(with: input) as! [String: Any]
var response: [String: Any]?
if request["method"] as? String == "__guardCheck" {
  do {
    _ = try HarnessPaths.applicationSupport()
    response = ["value": true]
  } catch { response = ["error": String(describing: error)] }
} else if request["method"] as? String == "__hostAttributes" {
  let directory = try HarnessPaths.applicationSupport().appendingPathComponent("tonyo-ai1-history")
  let backup = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
  let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
  var probe = HarnessPaths.root.appendingPathComponent("backup-attribute-probe", isDirectory: true)
  try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: false)
  var probeValues = URLResourceValues()
  probeValues.isExcludedFromBackup = true
  try probe.setResourceValues(probeValues)
  let probeBackup = try probe.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
  let owner = request["owner"] as! String
  let name = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
  let fileAttributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
  response = ["backupExcluded": backup as Any? ?? NSNull(),
              "backupExclusionHostProbe": probeBackup as Any? ?? NSNull(),
              "directoryProtection": attributes[.protectionKey].map { String(describing: $0) } ?? NSNull(),
              "fileProtection": fileAttributes[.protectionKey].map { String(describing: $0) } ?? NSNull()]
} else {
  let store = Ai1CaptureFileStore()
  store.handle(FlutterMethodCall(method: request["method"] as! String, arguments: request["arguments"])) { value in
    if let error = value as? FlutterError {
      response = ["error": error.code]
    } else if value is MethodNotImplemented {
      response = ["notImplemented": true]
    } else {
      response = ["value": value ?? NSNull()]
    }
  }
  let deadline = Date().addingTimeInterval(15)
  while response == nil && Date() < deadline {
    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
  }
}
guard let response = response else { fatalError("Journal callback timed out") }
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]))
'''


def run_checks(root: Path, binary: Path) -> tuple[list[str], dict]:
    checks: list[str] = []
    journal = root / "data/Library/ApplicationSupport/tonyo-ai1-history"

    def request(method: str, owner=None, value=None, **extra) -> dict:
        arguments = {}
        if owner is not None:
            arguments["owner"] = owner
        if value is not None:
            arguments["value"] = value
        payload = {"method": method, "arguments": arguments, **extra}
        process = subprocess.run(
            [str(binary)], input=json.dumps(payload).encode(), capture_output=True,
            timeout=25, check=True,
        )
        return json.loads(process.stdout)

    def path(owner: str) -> Path:
        return journal / (hashlib.sha256(owner.encode()).hexdigest() + ".json")

    def write(owner: str, value: str) -> str:
        before = time.time()
        response = request("write", owner, value)
        after = time.time()
        receipt = response.get("value")
        require(isinstance(receipt, str), f"Write failed: {response}")
        require(re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z", receipt) is not None,
                "Receipt must preserve canonical millisecond UTC precision")
        parsed = dt.datetime.fromisoformat(receipt.replace("Z", "+00:00"))
        require(before <= parsed.timestamp() <= after + .0011, "Receipt outside save bounds")
        require(parsed.isoformat(timespec="milliseconds").replace("+00:00", "Z") == receipt,
                "Receipt did not round-trip")
        return receipt

    a, b = "invented-owner-A", "invented-owner-B"
    first = '{"synthetic":true,"revision":1,"label":"invented 😀"}'
    second = '{"synthetic":true,"revision":2}'
    guard_check = request("__guardCheck")
    require(guard_check == {"value": True}, f"Temporary root guard failed: {guard_check}")
    require(request("available") == {"value": True}, "Availability failed")
    require(request("unknown") == {"notImplemented": True}, "Unknown method not rejected")
    fresh = request("read", a)
    require(fresh == {"value": None}, f"Fresh store was not empty: {fresh}")
    write(a, first)
    write(b, second)
    require(request("read", a) == {"value": first}, "Independent-process read failed")
    require(request("read", b) == {"value": second}, "Owner isolation failed")
    require(set(p.name for p in journal.iterdir()) == {path(a).name, path(b).name}, "Unexpected filenames")
    checks += ["independent_process_persistence", "owner_isolation", "receipt_utc_millisecond_roundtrip"]

    # The native metadata branch expects a top-level owner; keep it separate
    # from the production method-channel shape.
    attributes = json.loads(subprocess.run(
        [str(binary)], input=json.dumps({"method": "__hostAttributes", "owner": a}).encode(),
        capture_output=True, timeout=25, check=True,
    ).stdout)
    if attributes["backupExclusionHostProbe"] is True:
        require(attributes["backupExcluded"] is True, "Backup exclusion missing on supporting host")
    attributes["backupExclusionVerified"] = attributes["backupExclusionHostProbe"] is True
    for key in ("directoryProtection", "fileProtection"):
        if attributes[key] is not None:
            require("CompleteUntilFirstUserAuthentication" in attributes[key], "Unexpected protection attribute")
    checks.append("host_metadata_inspection")

    for owner in ("", " \n", "x" * 201, "😀" * 101, 42):
        require(request("write", owner, "{}") == {"error": "capture_invalid_arguments"}, "Invalid owner accepted")
    require(request("write", a, 42) == {"error": "capture_invalid_arguments"}, "Nonstring payload accepted")
    for value in ("[1]", "null", "false", "{", '"text"'):
        require(request("write", a, value) == {"error": "capture_invalid_data"}, "Nonobject JSON accepted")
    require(request("read", a) == {"value": first}, "Rejected write changed old journal")
    boundary = '{"v":"' + "x" * (MAXIMUM_BYTES - 8) + '"}'
    require(len(boundary.encode()) == MAXIMUM_BYTES, "Boundary fixture size error")
    write(a, boundary)
    require(request("read", a) == {"value": boundary}, "Exact size limit failed")
    require(request("write", a, boundary + " ") == {"error": "capture_too_large"}, "Oversize accepted")
    utf8_large = '{"v":"' + "😀" * (MAXIMUM_BYTES // 4) + '"}'
    require(request("write", a, utf8_large) == {"error": "capture_too_large"}, "UTF-8 bound failed")
    require(request("read", a) == {"value": boundary}, "Oversize changed old journal")
    path(a).write_text("[]")
    require(request("read", a) == {"error": "capture_invalid_data"}, "Corrupt disk JSON accepted")
    path(a).write_bytes(b" " * (MAXIMUM_BYTES + 1))
    require(request("read", a) == {"error": "capture_too_large"}, "Oversize disk payload accepted")
    write(a, first)
    checks += ["invalid_owner_and_json_rejected", "exact_four_mib_boundary", "utf8_byte_bound", "bounded_disk_read"]

    pending_a = journal / (path(a).name + ".pending-invented.tmp")
    pending_b = journal / (path(b).name + ".pending-invented.tmp")
    pending_a.write_text("partial")
    pending_b.write_text("partial")
    write(a, first)
    require(not pending_a.exists() and pending_b.exists(), "Pending write cleanup crossed owners")
    pending_a.write_text("partial")
    require(request("clear", a) == {"value": None}, "Clear failed")
    require(not path(a).exists() and not pending_a.exists(), "Clear retained owner bytes")
    require(path(b).exists() and pending_b.exists(), "Clear crossed owners")
    require(request("clear", a) == {"value": None}, "Repeated clear failed")
    require(request("read", a) == {"value": None}, "Deleted owner returned data")
    checks.append("owner_delete_and_pending_cleanup")

    old = json.dumps({"synthetic": True, "value": "A" * 100_000})
    new = json.dumps({"synthetic": True, "value": "B" * 100_000})
    write(a, old)
    accepted = {old.encode(), new.encode()}
    stop = threading.Event()
    errors: list[str] = []
    observations = [0]

    def reader() -> None:
        while not stop.is_set():
            try:
                data = path(a).read_bytes()
                if data not in accepted:
                    errors.append("Reader observed a partial or unexpected snapshot")
                    return
                observations[0] += 1
            except Exception as error:
                errors.append(type(error).__name__)
                return
            time.sleep(.0005)

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    try:
        for index in range(8):
            write(a, new if index % 2 == 0 else old)
    finally:
        stop.set()
        thread.join(timeout=5)
    require(not errors and observations[0] > 0 and not thread.is_alive(), f"Atomic replacement failed: {errors}")
    require(not list(journal.glob(path(a).name + ".pending-*.tmp")), "Successful writes left pending files")
    checks.append("concurrent_reader_observes_complete_replacements")

    require(request("clearAll") == {"value": None}, "Clear-all failed")
    require(not journal.exists(), "Clear-all retained journal directory")
    require(request("clearAll") == {"value": None}, "Repeated clear-all failed")
    require(request("read", a) == request("read", b) == {"value": None}, "Clear-all retained owner data")
    checks.append("delete_all_and_retry")

    # Prove the injected path guard refuses a symlink before production I/O.
    sibling = root / "guard-target"
    sibling.mkdir()
    sentinel = sibling / "unchanged"
    sentinel.write_text("invented sentinel")
    journal.symlink_to(sibling, target_is_directory=True)
    try:
        require(request("write", a, first) == {"error": "capture_storage_failed"}, "Symlink guard bypassed")
        require(request("clearAll") == {"error": "capture_storage_failed"}, "Clear-all symlink guard bypassed")
        require(list(sibling.iterdir()) == [sentinel], "Guard target was modified")
    finally:
        journal.unlink()
    checks.append("temporary_root_and_symlink_guard")
    attributes["atomicReaderObservations"] = observations[0]
    return checks, attributes


def main() -> int:
    require(len(sys.argv) == 1, "No options or external input paths are accepted")
    require(sys.platform == "darwin", "This host smoke test requires macOS")
    compiler = shutil.which("swiftc")
    require(compiler is not None, "swiftc is required")
    compiler_version = subprocess.run(
        [compiler, "--version"], capture_output=True, text=True, timeout=10, check=True,
    ).stdout.strip()
    store, digest = extract_store()
    with tempfile.TemporaryDirectory(prefix="tonyo-ai1-native-", dir="/private/tmp") as temporary:
        root = Path(temporary).resolve()
        require(root.parent == Path("/private/tmp") and not Path(temporary).is_symlink(), "Unsafe temporary root")
        root.chmod(0o700)
        (root / ".synthetic-only").write_text(str(root), encoding="utf-8")
        source = root / "main.swift"
        source.write_text(swift_program(store, root), encoding="utf-8")
        binary = root / "journal-smoke"
        cache = root / "module-cache"
        environment = {**os.environ, "CLANG_MODULE_CACHE_PATH": str(cache), "SWIFT_MODULECACHE_PATH": str(cache)}
        compile_result = subprocess.run(
            [compiler, "-swift-version", "5", "-module-cache-path", str(cache), str(source), "-o", str(binary)],
            capture_output=True, text=True, env=environment, timeout=120,
        )
        require(compile_result.returncode == 0, "Swift compilation failed:\n" + compile_result.stderr)
        checks, attributes = run_checks(root, binary)
        report = {
            "status": "passed", "evidenceKind": "synthetic_host_smoke_test",
            "swiftVersion": compiler_version,
            "hostPlatform": {"system": platform.system(), "version": platform.mac_ver()[0], "machine": platform.machine()},
            "iosDataProtectionVerified": False,
            "productionSource": "ios/Runner/AppDelegate.swift::Ai1CaptureFileStore",
            "productionClassSha256": digest, "rootInjection": "exact lookup replacement; fresh guarded temporary directory",
            "checks": checks, "checkCount": len(checks), "hostAttributes": attributes,
            "limitations": ["macOS host, not an iOS device", "No power-loss or crash-recovery guarantee",
                            "Host protection metadata does not establish iOS Data Protection",
                            "No app installation, private data, or production storage accessed"],
        }
    require(not root.exists(), "Temporary harness storage was not removed")
    report["temporaryStorageRemoved"] = True
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.SubprocessError) as error:
        print(f"Native journal smoke test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
