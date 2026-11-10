# RAM-Headroom API Research — iOS 26 / TCCC.ai StatusStrip Chip

Goal: a small live-updating chip near the time/battery showing how close the app is to the iOS jetsam ceiling. App will eventually carry Parakeet ASR + Qwen 3 1.7B, so the medic needs visibility before an OOM kill in the field.

## 1. The API surface

### `os_proc_available_memory()` — primary signal

- Header: `<os/proc.h>`. Signature `size_t os_proc_available_memory(void)`. Apple's own header annotates it `API_UNAVAILABLE(macos) API_AVAILABLE(ios(13.0), tvos(13.0), watchos(6.0))`. ([proc.h on iOS 13 SDK mirror](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS13.0.sdk/usr/include/os/proc.h))
- Semantics: "the number of bytes remaining, at the time of the call, before the current process will hit its current dirty memory limit." Returns 0 if the caller is not an app (e.g. an extension) or has already exceeded the limit.
- This is the **headroom** number — exactly what the chip should display.
- WWDC22 *Profile and optimize your game's memory* recommends it as the canonical foreground-app available-memory query and pairs it with `phys_footprint` for current usage. ([WWDC22 10106](https://developer.apple.com/videos/play/wwdc2022/10106/))
- Cost: a single `size_t` syscall — cheap. There is no public per-call benchmark from Apple, but it's a single ledger lookup; calling at 1 Hz from a SwiftUI Timer is *far* below any noticeable threshold. Apple's docs explicitly warn **not to cache** the result (limits change at runtime), which is a hint that re-querying frequently is the expected pattern.
- **Swift gotcha**: `os/proc.h` is *not* in the Darwin module map. It is not directly importable from Swift. You either (a) add a one-line bridging header `#import <os/proc.h>` (the easiest path) or (b) wrap it in a tiny `.h/.m` shim. ([Bugsnag issue #452](https://github.com/bugsnag/bugsnag-cocoa/issues/452), ravi6997 Medium piece.)

### `task_info(MACH_TASK_BASIC_INFO)` — older, not what you want

Returns `resident_size` and `virtual_size`. Apple DTS engineer "Quinn the Eskimo" explicitly says **don't use `resident_size`**: it doesn't move when memory is continuously allocated and doesn't match Xcode's gauge. ([Apple Forums thread 105088](https://developer.apple.com/forums/thread/105088))

### `task_info(TASK_VM_INFO)` → `phys_footprint` — the "current usage" number

- Same mechanism Apple's jetsam uses. Quinn (DTS) confirmed since iOS 12 that `task_vm_info_data_t.phys_footprint` matches the Xcode memory gauge exactly. ([Apple Forums thread 105088](https://developer.apple.com/forums/thread/105088))
- Composition (per `kern/task.c`): `(internal − alternate_accounting) + (internal_compressed − alternate_accounting_compressed) + iokit_mapped + purgeable_nonvolatile + purgeable_nonvolatile_compressed + page_table`. Includes compressed pages — which is why it tracks jetsam reasoning.
- Useful for showing **used MB** alongside the headroom, but for a single-chip display this is redundant — `os_proc_available_memory` already tells you what you need.

### `DispatchSource.makeMemoryPressureSource(eventMask:queue:)` — different question

- Fires on `.normal | .warning | .critical`. ([Apple docs](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)))
- This is **system-wide** pressure, not your app's footprint. It's complementary, not a substitute. Useful for lighting the chip red instead of yellow when iOS as a whole is under pressure even if your slice is fine.
- Strictly more granular than `applicationDidReceiveMemoryWarning(_:)`, which is a coarse single-state signal. Apple itself recommends DispatchSource for apps that want graduated response.

### `mach_task_self()` + `task_info`

The underlying primitive. Both `phys_footprint` and the basic info path use it. Mach APIs are documented as safe to call from any thread.

## 2. Best practice from Apple's own guidance

Apple's published recommendation, distilled from WWDC22 *Profile and optimize your game's memory* and WWDC18 *iOS Memory Deep Dive*, for a foreground app that wants to act on its own headroom:

1. Use **`os_proc_available_memory()`** as the actionable signal — it's the one that matches what jetsam will actually do to *you*.
2. Use **`phys_footprint`** when you want to mirror what Xcode shows (debugging/telemetry).
3. Subscribe to **DispatchSource memory pressure** as a coarse lifeline so you can flush caches before jetsam decides for you.
4. Don't cache. Don't predict. The limit is *not constant* — iOS varies it based on overall device pressure, foreground/background state, and the Increased-Memory-Limit entitlement.

WWDC22 doesn't pin a specific cadence. The community consensus (and what Bugsnag, Sentry, Firebase Crashlytics ship) is **1 Hz for live UI**, opportunistic just-before-large-allocation calls otherwise.

## 3. Display semantics — recommendation: show **headroom**, not %

The 12 GB iPhone 17 Pro foreground per-process limit is **not 6 GB** in any documented or stable way. iOS 18.3+ explicitly *reduced* maximum allocation on 16 GB iPad Pros from ~31 GB to ~16 GB, and added a new `vm-compressor-space-shortage` jetsam reason. ([Apple Forums thread 777370](https://developer.apple.com/forums/thread/777370)) The ceiling is dynamic by design.

Implications for the chip:

- **"Used: 78 %"** requires a known denominator. The denominator drifts. The chip will lie.
- **"Available: 1.2 GB"** is exactly what `os_proc_available_memory()` returns. It's what jetsam itself uses. If it says 200 MB, the medic's intuition ("don't load another model") is correct *regardless* of the device. Honest and self-calibrating.

Recommendation: display **"AVAIL 1.2 GB"** (or `MB` under 1024). Optionally co-display **`USED 740 MB`** from `phys_footprint` for situational awareness — but the headroom number is the load-bearing one. Color thresholds:

| Available | Color | Meaning |
| --- | --- | --- |
| > 1024 MB | green | safe — load another model if needed |
| 512–1024 MB | amber | working envelope — finish the encounter, don't load anything new |
| 256–512 MB | orange | flush caches, audio buffer, transcript history |
| < 256 MB | red | jetsam imminent |

These thresholds are calibrated for an app that's already running ASR + LLM and has perhaps 4–6 GB of weights + activations. Tune in field testing.

## 4. SwiftUI + actor sketch

Three files. ~70 lines total.

**`TCCC_IOS/Bridging/TCCC_IOS-Bridging-Header.h`** (or add to existing one):
```objc
#import <os/proc.h>
```

That single import exposes `os_proc_available_memory()` to Swift as `Darwin.os_proc_available_memory`. No `.m` shim needed.

**`Packages/TCCCKit/Sources/TCCCDesign/MemoryStat.swift`**:
```swift
import Foundation
import Combine
import Darwin
import Dispatch

@MainActor
public final class MemoryStat: ObservableObject {
    @Published public private(set) var availableBytes: UInt64 = 0
    @Published public private(set) var usedBytes: UInt64 = 0
    @Published public private(set) var systemPressure: Pressure = .normal

    public enum Pressure { case normal, warning, critical }

    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?

    public init() {}

    public func start() {
        sample()  // immediate first read so the chip isn't empty
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = src.data
            if mask.contains(.critical) { self.systemPressure = .critical }
            else if mask.contains(.warning) { self.systemPressure = .warning }
            else { self.systemPressure = .normal }
        }
        src.resume()
        pressureSource = src
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        pressureSource?.cancel(); pressureSource = nil
    }

    private func sample() {
        // headroom — the load-bearing number
        availableBytes = UInt64(os_proc_available_memory())

        // current footprint — same value Xcode's gauge shows
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { p in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), p, &count)
            }
        }
        if kr == KERN_SUCCESS { usedBytes = info.phys_footprint }
    }
}
```

**SwiftUI consumer (drop into `StatusStrip`)**:
```swift
struct MemoryChip: View {
    @StateObject var stat = MemoryStat()
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "memorychip")
            Text("AVAIL \(format(stat.availableBytes))")
                .font(.system(.caption, design: .monospaced))
        }
        .foregroundStyle(color(for: stat.availableBytes, pressure: stat.systemPressure))
        .onAppear { stat.start() }
        .onDisappear { stat.stop() }
    }
    private func format(_ b: UInt64) -> String {
        let mb = Double(b) / (1024 * 1024)
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024)
                          : String(format: "%.0f MB", mb)
    }
    private func color(for bytes: UInt64, pressure: MemoryStat.Pressure) -> Color {
        if pressure == .critical { return .red }
        let mb = bytes / (1024 * 1024)
        switch mb {
        case 1024...: return pressure == .warning ? .yellow : .green
        case 512..<1024: return .yellow
        case 256..<512: return .orange
        default: return .red
        }
    }
}
```

## 5. Pitfalls

- **Threading**: Mach APIs (`task_info`, `mach_task_self_`) and `os_proc_available_memory` are documented as safe from any thread. The Timer-driven `sample()` runs on the main runloop here, which is fine — the syscall is cheap. The only `@MainActor` requirement is the `@Published` write that drives SwiftUI binding.
- **Timer retain cycle**: `[weak self]` in the closure is mandatory; the `.common` runloop mode keeps it firing during scroll/pager drag.
- **Don't cache**: a single 1 Hz read is the right cadence. Don't average, don't smooth — when memory drops fast the chip should drop fast too.
- **Privacy manifest**: as of TN3183 (April 2024) the required-reason API categories are `UserDefaults`, `FileTimestamp`, `SystemBootTime`, `DiskSpace`, `ActiveKeyboard`. Neither `os_proc_available_memory` nor `task_info` nor `task_vm_info` is on the required-reason list. ([TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)) **No PrivacyInfo.xcprivacy update needed.** RF Ghost preserved.
- **Extension caveat**: `os_proc_available_memory` returns 0 from app extensions. TCCC.ai is a single app target, so this is moot — but if a Share Extension is ever added, that code path needs a different signal.
- **Increased-Memory-Limit entitlement**: this lifts the per-process ceiling. The chip's value will simply reflect the new (higher) ceiling — no code change required.

## 6. One-line recommendation

> Call **`os_proc_available_memory()`** at **1 Hz** from a `@MainActor`-isolated `MemoryStat` observable, display **"AVAIL n GB / MB"** with a four-band color scale, and subscribe to `DispatchSource.makeMemoryPressureSource([.warning, .critical])` as a coarse lifeline that overrides the color to red on critical.

## Sources

- [`os_proc_available_memory` — Apple Developer Documentation](https://developer.apple.com/documentation/os/3191911-os_proc_available_memory)
- [`os/proc.h` — iOS 13 SDK mirror (xybp888/iOS-SDKs)](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS13.0.sdk/usr/include/os/proc.h)
- [Identifying high-memory use with jetsam event reports — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)
- [Gathering information about memory use — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use)
- [`phys_footprint` — Apple Developer Documentation](https://developer.apple.com/documentation/kernel/task_vm_info_data_t/1553210-phys_footprint)
- [Apple Forums thread 105088 — How Xcode calculates memory (Quinn DTS)](https://developer.apple.com/forums/thread/105088)
- [Apple Forums thread 777370 — Increased Memory Limit, Extended Virtual Addressing (iOS 18 changes)](https://developer.apple.com/forums/thread/777370)
- [WWDC22 — Profile and optimize your game's memory (10106)](https://developer.apple.com/videos/play/wwdc2022/10106/)
- [WWDC18 — iOS Memory Deep Dive (416)](https://developer.apple.com/videos/play/wwdc2018/416/)
- [`DispatchSource.makeMemoryPressureSource` — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:))
- [Responding to memory warnings — Apple Developer Documentation](https://developer.apple.com/documentation/uikit/responding-to-memory-warnings)
- [TN3183 — Adding required reason API entries to your privacy manifest](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [Bugsnag issue #452 — Use iOS 13 `os_proc_available_memory`](https://github.com/bugsnag/bugsnag-cocoa/issues/452)
- [iOS Memory Pressure Signals Explained — ravi6997 / Medium](https://ravi6997.medium.com/memory-pressure-signals-in-ios-how-the-system-decides-to-terminate-your-app-c1b174c50214)
- [No pressure, Mon! — newosxbook (jetsam internals)](https://newosxbook.com/articles/MemoryPressure.html)
- [Uncovering iOS OOM — BestHub.dev](https://www.besthub.dev/articles/uncovering-ios-oom-from-kernel-mechanics-to-real-world-monitoring-solutions-e54e1fb1d13a)
