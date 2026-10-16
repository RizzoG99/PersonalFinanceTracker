// Offline reader for the native VM Tracker archive in an Xcode 27 saved trace.
// This is a macOS analysis tool, outside the app target. It does not record or launch apps.
// Xcode's own archive decoder and XRVMState getters define the counters; do not infer
// physical footprint from resident/dirty/virtual-size values.
import Foundation
import ObjectiveC
import Darwin

let arguments = CommandLine.arguments
if arguments.count < 3 || arguments.count > 4 {
    fputs("Usage: swift perf301_vmtracker_extract.swift INPUT_ARCHIVE OUTPUT_JSON [XCODE_CONTENTS]\n", stderr)
    exit(2)
}
let xcodeContents = arguments.count == 4 ? arguments[3] : "/Applications/Xcode.app/Contents"
let binaries = [
    "SharedFrameworks/DVTInstrumentsFoundation.framework/Versions/A/DVTInstrumentsFoundation",
    "Applications/Instruments.app/Contents/PlugIns/MemoryPlugin.xrplugin/Contents/MacOS/MemoryPlugin"
]
for binary in binaries {
    guard dlopen(xcodeContents + "/" + binary, RTLD_NOW | RTLD_GLOBAL) != nil else {
        fputs("Cannot load Xcode archive decoder: \(String(cString: dlerror()))\n", stderr)
        exit(1)
    }
}
let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
// VM Tracker still saves a legacy NSArchiver stream, not a keyed archive.
guard let root = NSUnarchiver.unarchiveObject(with: data) as? NSObject,
      NSStringFromClass(type(of: root)) == "XRVMRun",
      let states = root.value(forKey: "fullVMStates") as? [NSObject], !states.isEmpty
else { fatalError("Expected a nonempty XRVMRun archive") }
var rows: [[String: Any]] = []
for (index, state) in states.enumerated() {
    guard NSStringFromClass(type(of: state)) == "XRVMState" else { fatalError("Unexpected VM state class") }
    var row: [String: Any] = ["index": index]
    for key in ["machAbsolute", "residentSize", "swapSize", "dirtySize", "totalSize"] {
        guard let value = state.value(forKey: key) as? NSNumber else { fatalError("Missing \(key)") }
        row[key] = value.uint64Value
    }
    if let regions = state.value(forKey: "regions") as? NSArray { row["regionCount"] = regions.count }
    rows.append(row)
}
let json = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
print("Extracted \(rows.count) native VM Tracker snapshots")
