# Phase 0+1: Build Stamp + Transcription Benchmark Harness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the build-identity stamp (Phase 0) and the transcription benchmark harness with a committed Apple-Speech baseline on the Valdez Alley fixture (Phase 1) — Workstreams 0 and 1 of `docs/superpowers/specs/2026-07-02-transcription-and-fm-harness-sprint-design.md`.

**Architecture:** Pure scoring logic (token normalizer, WER, keyword recall, extraction scorer) goes in a new `TCCCBench` module inside the existing `Packages/TCCCKit` SPM package, fully unit-tested with `swift test`. The app target gains a DevTools benchmark runner (mirroring the existing `GraniteAudioBenchmarkView` launch-arg pattern) that feeds fixture audio files through a re-arming on-device `SFSpeechRecognizer` loop built from a new shared `SpeechRequestFactory` (single source of request config — later vocabulary work lands there once and reaches both production and bench). Build identity is stamped into the product Info.plist by a post-build script and surfaced in Settings.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Speech.framework (`SFSpeechRecognizer`, on-device), AVFoundation (`AVAudioFile`), XcodeGen, XCTest.

## Global Constraints

- Deployment target **iOS 26.0** (`project.yml:5`); Swift 6 strict concurrency everywhere.
- **Never hand-edit `TCCC_IOS.xcodeproj`** — edit `project.yml`, then run `xcodegen generate`.
- **No logic in the app target** beyond views/plumbing — scorers live in TCCCKit (`TCCCBench`); the runner/mapper are DevTools plumbing (precedent: `GraniteAudioBenchmarkRunner`).
- **RF Ghost:** no network calls anywhere in this plan. `requiresOnDeviceRecognition = true` stays mandatory.
- CLI builds need `-skipMacroValidation`. Package tests: `cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test`.
- Commit messages: `feat(...)`/`fix(...)`/`docs(...)` style, ending with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` (plus the session trailer used earlier in this sprint).
- Working directory for all commands: `/Users/ama/TCCC_IOS` unless stated.

## File Structure (locked by this plan)

```
project.yml                                        # modify: sandbox off, post-build stamp script, TCCCBench dep, TCCCExtractor test dep
Packages/TCCCKit/Package.swift                     # modify: add TCCCBench library + test target
Packages/TCCCKit/Sources/TCCCBench/
  TokenNormalizer.swift                            # create
  WERScorer.swift                                  # create
  KeywordRecallScorer.swift                        # create
  ExtractionScorer.swift                           # create
Packages/TCCCKit/Tests/TCCCBenchTests/
  TokenNormalizerTests.swift                       # create
  WERScorerTests.swift                             # create
  ScorerTests.swift                                # create
TCCC_IOS/App/BuildStamp.swift                      # create
TCCC_IOS/Components/SettingsOverlay.swift          # modify: About/build row in systemSection
TCCC_IOS/Audio/SpeechRecognizer.swift              # modify: docstring fix, use SpeechRequestFactory
TCCC_IOS/Audio/SpeechRequestFactory.swift          # create
TCCC_IOS/DevTools/TranscriptionBenchmark/
  TranscriptionBenchmarkView.swift                 # create (launch-arg gated screen)
  AppleSpeechFileTranscriber.swift                 # create (re-arming file-feed loop)
  BenchStateMapper.swift                           # create (PatientState → [String:String])
  BenchmarkReference.swift                         # create (loads reference txt + sidecar json)
TCCC_IOS/DevTools/Fixtures/
  valdez_alley.txt                                 # create (reference transcript)
  valdez_alley.json                                # create (keywords/folds/field expectations)
TCCC_IOS/TCCC_IOSApp.swift                         # modify: mount TranscriptionBenchmarkView
TCCC_IOSTests/BuildStampTests.swift                # create
TCCC_IOSTests/BenchStateMapperTests.swift          # create
docs/research/<run-date>-transcription-baseline.md # create in Task 9 (use the actual date of the run)
```

---

### Task 1: Build-identity stamp (Phase 0)

**Files:**
- Modify: `project.yml` (settings block at lines 35–40; app target block at lines 42–95)
- Create: `TCCC_IOS/App/BuildStamp.swift`
- Modify: `TCCC_IOS/Components/SettingsOverlay.swift` (systemSection, after the four `ToggleRow`s, ~line 540)
- Create: `TCCC_IOSTests/BuildStampTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `struct BuildStamp { let version, build, gitSHA, gitBranch, buildDate: String; static let current: BuildStamp; var display: String }` — later phases show `display` anywhere they need revision identity.

- [ ] **Step 1: project.yml — disable script sandboxing and add the stamp script**

In `settings.base` (line 40) change `ENABLE_USER_SCRIPT_SANDBOXING: YES` → `NO`, with this comment above it:

```yaml
    # Xcode 15 user-script sandboxing blocks the git reads the build-stamp
    # post-build script needs (.git/HEAD, refs, index). Offline local
    # project; scripts are ours; determinism > sandbox here.
    ENABLE_USER_SCRIPT_SANDBOXING: NO
```

In the `TCCC_IOS` target (after the `settings:` block, same indent level as `sources:`/`dependencies:`), add:

```yaml
    postBuildScripts:
      - name: "Stamp build identity"
        basedOnDependencyAnalysis: false
        shell: /bin/bash
        script: |
          set -euo pipefail
          PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
          if [ ! -f "$PLIST" ]; then exit 0; fi
          GIT_SHA=$(git -C "${SRCROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)
          GIT_BRANCH=$(git -C "${SRCROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
          if [ -n "$(git -C "${SRCROOT}" status --porcelain 2>/dev/null)" ]; then GIT_SHA="${GIT_SHA}+"; fi
          BUILD_DATE=$(date "+%Y-%m-%d %H:%M")
          for KEY in TCCCGitSHA TCCCGitBranch TCCCBuildDate; do
            /usr/libexec/PlistBuddy -c "Delete :${KEY}" "$PLIST" 2>/dev/null || true
          done
          /usr/libexec/PlistBuddy -c "Add :TCCCGitSHA string ${GIT_SHA}" "$PLIST"
          /usr/libexec/PlistBuddy -c "Add :TCCCGitBranch string ${GIT_BRANCH}" "$PLIST"
          /usr/libexec/PlistBuddy -c "Add :TCCCBuildDate string ${BUILD_DATE}" "$PLIST"
```

(Post-build script phases run before code signing, so the stamped plist is inside the signature seal. The `+` suffix marks a dirty working tree.)

- [ ] **Step 2: Create `TCCC_IOS/App/BuildStamp.swift`**

```swift
import Foundation

/// Build-identity stamp injected into the product Info.plist by the
/// "Stamp build identity" post-build script in project.yml. Standing
/// rule: every installed revision must be visually identifiable
/// in-app (version + git SHA + branch + build date).
struct BuildStamp {
    let version: String
    let build: String
    let gitSHA: String
    let gitBranch: String
    let buildDate: String

    static let current: BuildStamp = {
        let info = Bundle.main.infoDictionary ?? [:]
        return BuildStamp(
            version: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            gitSHA: info["TCCCGitSHA"] as? String ?? "dev",
            gitBranch: info["TCCCGitBranch"] as? String ?? "dev",
            buildDate: info["TCCCBuildDate"] as? String ?? "—"
        )
    }()

    /// e.g. "v1.0 (48b4ac2) main · 2026-07-02 14:31"
    var display: String {
        "v\(version) (\(gitSHA)) \(gitBranch) · \(buildDate)"
    }
}
```

- [ ] **Step 3: SettingsOverlay — add the Build row**

In `systemSection` (Components/SettingsOverlay.swift, currently ending after the fourth `ToggleRow` around line 540), append below the last `ToggleRow`:

```swift
            HStack {
                Text("Build")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.fg)
                Spacer()
                Text(BuildStamp.current.display)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.fg.opacity(0.7))
                    .textSelection(.enabled)
            }
            .padding(.vertical, 10)
```

- [ ] **Step 4: Write the failing-ish test** — `TCCC_IOSTests/BuildStampTests.swift`

```swift
import XCTest
@testable import TCCC_IOS

final class BuildStampTests: XCTestCase {
    func testStampDisplayIsWellFormed() {
        let s = BuildStamp.current
        XCTAssertFalse(s.version.isEmpty)
        XCTAssertTrue(s.display.contains(s.gitSHA))
    }

    func testProductPlistCarriesGitStamp() {
        // The post-build script must have stamped the test-host app bundle.
        let sha = Bundle.main.infoDictionary?["TCCCGitSHA"] as? String
        XCTAssertNotNil(sha, "TCCCGitSHA missing — postBuildScripts stamp did not run")
        XCTAssertNotEqual(sha, "unknown")
    }
}
```

- [ ] **Step 5: Regenerate + build + run app tests**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation \
  -only-testing:TCCC_IOSTests/BuildStampTests
```
Expected: `** TEST SUCCEEDED **` (2 tests). If `testProductPlistCarriesGitStamp` fails with nil, the script phase didn't run — check `xcodegen generate` output listed "Stamp build identity" and that the script block indentation sits inside the `TCCC_IOS:` target.

- [ ] **Step 6: Verify the stamped plist directly**

```bash
BUILT=$(xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings -skipMacroValidation 2>/dev/null \
  | awk '/ TARGET_BUILD_DIR =/{print $3}' | head -1)
/usr/libexec/PlistBuddy -c "Print :TCCCGitSHA" "$BUILT/TCCC_IOS.app/Info.plist"
```
Expected: a 7-char SHA (possibly with `+`).

- [ ] **Step 7: Commit**

```bash
git add project.yml TCCC_IOS/App/BuildStamp.swift TCCC_IOS/Components/SettingsOverlay.swift TCCC_IOSTests/BuildStampTests.swift
git commit -m "feat(app): build-identity stamp — post-build git SHA/branch/date into Info.plist + Settings Build row"
```

---

### Task 2: Docstring fix (Phase 0 hygiene)

**Files:**
- Modify: `TCCC_IOS/Audio/SpeechRecognizer.swift:48`

**Interfaces:** none.

- [ ] **Step 1: Fix the stale comment**

Line 48 currently reads `// MARK: - Pre-roll ring buffer (last ~10s of PCM)`. Change to:

```swift
    // MARK: - Pre-roll ring buffer (last 30s of PCM — see leadDuration)
```

- [ ] **Step 2: Build check + commit**

```bash
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO -skipMacroValidation | tail -2
git add TCCC_IOS/Audio/SpeechRecognizer.swift
git commit -m "fix(audio): correct stale 10s ring-buffer comment (leadDuration is 30s)"
```
Expected: `** BUILD SUCCEEDED **`.

---

### Task 3: TCCCBench module + TokenNormalizer (TDD)

**Files:**
- Modify: `Packages/TCCCKit/Package.swift`
- Create: `Packages/TCCCKit/Sources/TCCCBench/TokenNormalizer.swift`
- Create: `Packages/TCCCKit/Tests/TCCCBenchTests/TokenNormalizerTests.swift`

**Interfaces:**
- Produces: `public enum TokenNormalizer { public static func tokens(_ text: String, extraFolds: [[String]] = []) -> [String] }`. An `extraFold` is `["t","x","a","txa"]` — the last element replaces a run of the preceding elements. Tasks 4/5/8 consume `tokens(_:extraFolds:)`.

- [ ] **Step 1: Add the TCCCBench targets to `Packages/TCCCKit/Package.swift`**

In `products:` (after line 13):
```swift
        .library(name: "TCCCBench", targets: ["TCCCBench"]),
```
In `targets:` (after the `TCCCDesign` target, before the test targets):
```swift
        .target(
            name: "TCCCBench",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
```
And with the test targets:
```swift
        .testTarget(
            name: "TCCCBenchTests",
            dependencies: ["TCCCBench"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
```

- [ ] **Step 2: Write the failing tests** — `Packages/TCCCKit/Tests/TCCCBenchTests/TokenNormalizerTests.swift`

```swift
import XCTest
@testable import TCCCBench

final class TokenNormalizerTests: XCTestCase {
    func testLowercasesAndStripsPunctuation() {
        XCTAssertEqual(
            TokenNormalizer.tokens("SpO2 is dropping, we're at 88%."),
            ["spo2", "is", "dropping", "were", "at", "88"]
        )
    }

    func testNumberWordsFoldToDigits() {
        XCTAssertEqual(
            TokenNormalizer.tokens("Eight-Seven-Three-Four, Niner-One-Two-Zero"),
            ["8", "7", "3", "4", "9", "1", "2", "0"]
        )
    }

    func testLongDigitStringsSplitToSingleDigits() {
        // "8734 9120" spoken as digits vs recognized as one number must align.
        XCTAssertEqual(TokenNormalizer.tokens("8734 9120"), ["8", "7", "3", "4", "9", "1", "2", "0"])
        XCTAssertEqual(TokenNormalizer.tokens("135"), ["1", "3", "5"])
        XCTAssertEqual(TokenNormalizer.tokens("88 over 60"), ["88", "over", "60"])
    }

    func testTensUnitsCombine() {
        // "thirty two" ≡ "32"
        XCTAssertEqual(TokenNormalizer.tokens("maybe thirty two a minute"), ["maybe", "32", "a", "minute"])
        XCTAssertEqual(TokenNormalizer.tokens("maybe 32 a minute"), ["maybe", "32", "a", "minute"])
    }

    func testExtraFoldsMergeRuns() {
        XCTAssertEqual(
            TokenNormalizer.tokens("gave one gram of T X A now", extraFolds: [["t", "x", "a", "txa"]]),
            ["gave", "1", "gram", "of", "txa", "now"]
        )
    }

    func testDecimalNumbersSurviveAsDigitRuns() {
        // "44.50" — dot is stripped; both ref and hyp normalize identically.
        XCTAssertEqual(TokenNormalizer.tokens("Frequency is 44.50"), ["frequency", "is", "4", "4", "5", "0"])
    }
}
```

- [ ] **Step 3: Run to verify failure**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test --filter TCCCBenchTests 2>&1 | tail -5
```
Expected: compile error — `TokenNormalizer` not found.

- [ ] **Step 4: Implement** — `Packages/TCCCKit/Sources/TCCCBench/TokenNormalizer.swift`

```swift
import Foundation

/// Deterministic token normalization so a reference transcript and an ASR
/// hypothesis compare fairly: lowercase, punctuation stripped, number words
/// folded to digits, digit strings ≥3 chars split to single digits (grid
/// coordinates are spoken digit-by-digit), tens+units combined ("thirty
/// two" → "32"), and caller-supplied fold runs merged ("t x a" → "txa").
public enum TokenNormalizer {
    static let numberWords: [String: String] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3",
        "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
        "nine": "9", "niner": "9", "ten": "10", "eleven": "11",
        "twelve": "12", "thirteen": "13", "fourteen": "14", "fifteen": "15",
        "sixteen": "16", "seventeen": "17", "eighteen": "18", "nineteen": "19",
        "twenty": "20", "thirty": "30", "forty": "40", "fifty": "50",
        "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90",
    ]

    public static func tokens(_ text: String, extraFolds: [[String]] = []) -> [String] {
        // 1. Lowercase; hyphens/slashes become spaces; drop everything that
        //    is not a letter, digit, or space (apostrophes vanish: we're→were).
        let lowered = text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
        var cleaned = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                cleaned.unicodeScalars.append(scalar)
            }
        }
        var toks = cleaned.split(separator: " ").map(String.init)

        // 2. Number words → digits.
        toks = toks.map { numberWords[$0] ?? $0 }

        // 3. Combine tens + unit ("30","2" → "32").
        var combined: [String] = []
        var i = 0
        while i < toks.count {
            if i + 1 < toks.count,
               let tens = Int(toks[i]), tens % 10 == 0, (20...90).contains(tens),
               let unit = Int(toks[i + 1]), (1...9).contains(unit) {
                combined.append(String(tens + unit))
                i += 2
            } else {
                combined.append(toks[i])
                i += 1
            }
        }
        toks = combined

        // 4. Split pure-digit tokens of length ≥3 into single digits.
        toks = toks.flatMap { tok -> [String] in
            if tok.count >= 3, tok.allSatisfy(\.isNumber) {
                return tok.map(String.init)
            }
            return [tok]
        }

        // 5. Apply fold runs (["t","x","a","txa"]: run of prefix → last).
        for fold in extraFolds where fold.count >= 2 {
            let run = fold.dropLast().map { $0.lowercased() }
            let replacement = fold.last!.lowercased()
            var out: [String] = []
            var j = 0
            while j < toks.count {
                if j + run.count <= toks.count,
                   Array(toks[j..<(j + run.count)]) == run {
                    out.append(replacement)
                    j += run.count
                } else {
                    out.append(toks[j])
                    j += 1
                }
            }
            toks = out
        }
        return toks
    }
}
```

- [ ] **Step 5: Run tests to verify pass**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test --filter TokenNormalizerTests 2>&1 | tail -3
```
Expected: `Test Suite 'TokenNormalizerTests' passed` (6 tests). Note: `testExtraFoldsMergeRuns` expects `"one"` → `"1"` — that comes from step 2's number folding, not the fold list.

- [ ] **Step 6: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add Packages/TCCCKit/Package.swift Packages/TCCCKit/Sources/TCCCBench/ Packages/TCCCKit/Tests/TCCCBenchTests/
git commit -m "feat(bench): TCCCBench module + deterministic TokenNormalizer (TDD)"
```

---

### Task 4: WERScorer (TDD)

**Files:**
- Create: `Packages/TCCCKit/Sources/TCCCBench/WERScorer.swift`
- Create: `Packages/TCCCKit/Tests/TCCCBenchTests/WERScorerTests.swift`

**Interfaces:**
- Consumes: token arrays from `TokenNormalizer.tokens(_:extraFolds:)`.
- Produces:
  `public struct WERResult: Sendable, Codable, Equatable { public let substitutions: Int; public let insertions: Int; public let deletions: Int; public let referenceCount: Int; public var errorCount: Int; public var wer: Double }`
  `public enum WERScorer { public static func score(reference: [String], hypothesis: [String]) -> WERResult }`

- [ ] **Step 1: Write the failing tests** — `Packages/TCCCKit/Tests/TCCCBenchTests/WERScorerTests.swift`

```swift
import XCTest
@testable import TCCCBench

final class WERScorerTests: XCTestCase {
    func testIdenticalIsZero() {
        let r = WERScorer.score(reference: ["a", "b", "c"], hypothesis: ["a", "b", "c"])
        XCTAssertEqual(r.errorCount, 0)
        XCTAssertEqual(r.wer, 0.0)
    }

    func testSingleSubstitution() {
        let r = WERScorer.score(reference: ["a", "b", "c"], hypothesis: ["a", "x", "c"])
        XCTAssertEqual(r.substitutions, 1)
        XCTAssertEqual(r.insertions, 0)
        XCTAssertEqual(r.deletions, 0)
        XCTAssertEqual(r.wer, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testInsertionAndDeletion() {
        XCTAssertEqual(WERScorer.score(reference: ["a", "b"], hypothesis: ["a", "x", "b"]).insertions, 1)
        XCTAssertEqual(WERScorer.score(reference: ["a", "b", "c"], hypothesis: ["a", "c"]).deletions, 1)
    }

    func testEmptyHypothesisIsAllDeletions() {
        let r = WERScorer.score(reference: ["a", "b", "c"], hypothesis: [])
        XCTAssertEqual(r.deletions, 3)
        XCTAssertEqual(r.wer, 1.0)
    }

    func testEmptyReferenceCountsInsertionsWithWerOneWhenHypNonEmpty() {
        let r = WERScorer.score(reference: [], hypothesis: ["a"])
        XCTAssertEqual(r.insertions, 1)
        XCTAssertEqual(r.wer, 1.0)
        XCTAssertEqual(WERScorer.score(reference: [], hypothesis: []).wer, 0.0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test --filter WERScorerTests 2>&1 | tail -3
```
Expected: compile error — `WERScorer` not found.

- [ ] **Step 3: Implement** — `Packages/TCCCKit/Sources/TCCCBench/WERScorer.swift`

```swift
import Foundation

public struct WERResult: Sendable, Codable, Equatable {
    public let substitutions: Int
    public let insertions: Int
    public let deletions: Int
    public let referenceCount: Int

    public var errorCount: Int { substitutions + insertions + deletions }
    /// Convention: empty reference + non-empty hypothesis = 1.0.
    public var wer: Double {
        if referenceCount == 0 { return errorCount == 0 ? 0.0 : 1.0 }
        return Double(errorCount) / Double(referenceCount)
    }

    public init(substitutions: Int, insertions: Int, deletions: Int, referenceCount: Int) {
        self.substitutions = substitutions
        self.insertions = insertions
        self.deletions = deletions
        self.referenceCount = referenceCount
    }
}

/// Classic Levenshtein alignment with backtrace so S/I/D are reported
/// separately (WER = (S+I+D)/N over the reference).
public enum WERScorer {
    public static func score(reference: [String], hypothesis: [String]) -> WERResult {
        let n = reference.count, m = hypothesis.count
        // dp[i][j] = edit distance between ref[0..<i] and hyp[0..<j]
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let subCost = reference[i - 1] == hypothesis[j - 1] ? 0 : 1
                    dp[i][j] = min(
                        dp[i - 1][j - 1] + subCost, // match/substitute
                        dp[i - 1][j] + 1,           // deletion (ref word dropped)
                        dp[i][j - 1] + 1            // insertion (extra hyp word)
                    )
                }
            }
        }
        // Backtrace.
        var s = 0, ins = 0, del = 0
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0,
               dp[i][j] == dp[i - 1][j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1) {
                if reference[i - 1] != hypothesis[j - 1] { s += 1 }
                i -= 1; j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                del += 1; i -= 1
            } else {
                ins += 1; j -= 1
            }
        }
        return WERResult(substitutions: s, insertions: ins, deletions: del, referenceCount: n)
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test --filter WERScorerTests 2>&1 | tail -3
```
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add Packages/TCCCKit/Sources/TCCCBench/WERScorer.swift Packages/TCCCKit/Tests/TCCCBenchTests/WERScorerTests.swift
git commit -m "feat(bench): WERScorer — Levenshtein alignment with S/I/D backtrace (TDD)"
```

---

### Task 5: KeywordRecallScorer + ExtractionScorer (TDD)

**Files:**
- Create: `Packages/TCCCKit/Sources/TCCCBench/KeywordRecallScorer.swift`
- Create: `Packages/TCCCKit/Sources/TCCCBench/ExtractionScorer.swift`
- Create: `Packages/TCCCKit/Tests/TCCCBenchTests/ScorerTests.swift`

**Interfaces:**
- Consumes: `TokenNormalizer.tokens(_:extraFolds:)`.
- Produces:
  `public struct KeywordRecall: Sendable, Codable, Equatable { public let hits: [String]; public let misses: [String]; public var recall: Double }`
  `public enum KeywordRecallScorer { public static func score(keywords: [String], transcriptTokens: [String], extraFolds: [[String]] = []) -> KeywordRecall }`
  `public struct FieldExpectation: Sendable, Codable, Equatable { public enum Mode: String, Codable, Sendable { case exact, contains }; public let key: String; public let expected: String; public let mode: Mode }`
  `public struct ExtractionScore: Sendable, Codable, Equatable { public struct FieldResult: Sendable, Codable, Equatable { public let key: String; public let expected: String; public let actual: String?; public let passed: Bool }; public let fields: [FieldResult]; public var passedCount: Int; public var recall: Double }`
  `public enum ExtractionScorer { public static func score(expectations: [FieldExpectation], actual: [String: String]) -> ExtractionScore }`

- [ ] **Step 1: Write the failing tests** — `Packages/TCCCKit/Tests/TCCCBenchTests/ScorerTests.swift`

```swift
import XCTest
@testable import TCCCBench

final class ScorerTests: XCTestCase {
    func testKeywordRecallMultiTokenPhrase() {
        let tokens = TokenNormalizer.tokens("moving to a needle decompression right side")
        let r = KeywordRecallScorer.score(
            keywords: ["needle decompression", "chest seal"],
            transcriptTokens: tokens
        )
        XCTAssertEqual(r.hits, ["needle decompression"])
        XCTAssertEqual(r.misses, ["chest seal"])
        XCTAssertEqual(r.recall, 0.5, accuracy: 1e-9)
    }

    func testKeywordRecallNormalizesKeywordsToo() {
        // Keyword "8734" ≡ spoken "eight seven three four".
        let tokens = TokenNormalizer.tokens("grid eight seven three four confirmed")
        let r = KeywordRecallScorer.score(keywords: ["8734"], transcriptTokens: tokens)
        XCTAssertEqual(r.hits, ["8734"])
    }

    func testExtractionScorerModes() {
        let expectations = [
            FieldExpectation(key: "hr", expected: "135", mode: .exact),
            FieldExpectation(key: "interventions", expected: "chest seal", mode: .contains),
            FieldExpectation(key: "rr", expected: "32", mode: .exact),
        ]
        let actual = ["hr": "135", "interventions": "vented chest seal; needle decompression"]
        let score = ExtractionScorer.score(expectations: expectations, actual: actual)
        XCTAssertEqual(score.passedCount, 2)
        XCTAssertEqual(score.recall, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(score.fields.first(where: { $0.key == "rr" })?.passed, false)
        XCTAssertNil(score.fields.first(where: { $0.key == "rr" })?.actual)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test --filter ScorerTests 2>&1 | tail -3
```
Expected: compile error.

- [ ] **Step 3: Implement both scorers**

`Packages/TCCCKit/Sources/TCCCBench/KeywordRecallScorer.swift`:

```swift
import Foundation

public struct KeywordRecall: Sendable, Codable, Equatable {
    public let hits: [String]
    public let misses: [String]
    public var recall: Double {
        let total = hits.count + misses.count
        return total == 0 ? 0.0 : Double(hits.count) / Double(total)
    }

    public init(hits: [String], misses: [String]) {
        self.hits = hits
        self.misses = misses
    }
}

/// Secondary metric (the fixture keyword list is fixture-overfitted — see
/// spec §4.1). A keyword matches when its normalized tokens appear as a
/// contiguous subsequence of the normalized transcript tokens.
public enum KeywordRecallScorer {
    public static func score(
        keywords: [String],
        transcriptTokens: [String],
        extraFolds: [[String]] = []
    ) -> KeywordRecall {
        var hits: [String] = []
        var misses: [String] = []
        for keyword in keywords {
            let needle = TokenNormalizer.tokens(keyword, extraFolds: extraFolds)
            if needle.isEmpty { continue }
            if containsSubsequence(haystack: transcriptTokens, needle: needle) {
                hits.append(keyword)
            } else {
                misses.append(keyword)
            }
        }
        return KeywordRecall(hits: hits, misses: misses)
    }

    private static func containsSubsequence(haystack: [String], needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }
}
```

`Packages/TCCCKit/Sources/TCCCBench/ExtractionScorer.swift`:

```swift
import Foundation

public struct FieldExpectation: Sendable, Codable, Equatable {
    public enum Mode: String, Codable, Sendable {
        case exact
        case contains
    }

    public let key: String
    public let expected: String
    public let mode: Mode

    public init(key: String, expected: String, mode: Mode) {
        self.key = key
        self.expected = expected
        self.mode = mode
    }
}

public struct ExtractionScore: Sendable, Codable, Equatable {
    public struct FieldResult: Sendable, Codable, Equatable {
        public let key: String
        public let expected: String
        public let actual: String?
        public let passed: Bool
    }

    public let fields: [FieldResult]
    public var passedCount: Int { fields.filter(\.passed).count }
    public var recall: Double {
        fields.isEmpty ? 0.0 : Double(passedCount) / Double(fields.count)
    }

    public init(fields: [FieldResult]) {
        self.fields = fields
    }
}

/// Ties ASR quality to the deliverable: after the engine ingests the
/// hypothesis transcript, did the DD1380-bound fields come out right?
/// Case-insensitive; `contains` = actual contains expected.
public enum ExtractionScorer {
    public static func score(
        expectations: [FieldExpectation],
        actual: [String: String]
    ) -> ExtractionScore {
        let fields = expectations.map { exp -> ExtractionScore.FieldResult in
            let actualValue = actual[exp.key]
            let passed: Bool
            switch (actualValue, exp.mode) {
            case (nil, _):
                passed = false
            case (let value?, .exact):
                passed = value.lowercased() == exp.expected.lowercased()
            case (let value?, .contains):
                passed = value.lowercased().contains(exp.expected.lowercased())
            }
            return .init(key: exp.key, expected: exp.expected, actual: actualValue, passed: passed)
        }
        return ExtractionScore(fields: fields)
    }
}
```

- [ ] **Step 4: Run the full TCCCBench suite**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test --filter TCCCBenchTests 2>&1 | tail -3
```
Expected: all TokenNormalizer + WERScorer + Scorer tests pass (14 total).

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add Packages/TCCCKit/Sources/TCCCBench/ Packages/TCCCKit/Tests/TCCCBenchTests/ScorerTests.swift
git commit -m "feat(bench): KeywordRecallScorer + ExtractionScorer (TDD)"
```

---

### Task 6: Reference fixture resources

**Files:**
- Create: `TCCC_IOS/DevTools/Fixtures/valdez_alley.txt`
- Create: `TCCC_IOS/DevTools/Fixtures/valdez_alley.json`

**Interfaces:**
- Produces: bundled resources keyed by fixture slug (`"Valdez Alley.m4a"` → slug `valdez_alley`). Task 8's `BenchmarkReference.load(slug:)` reads both. JSON decodes into `BenchmarkSidecar` (defined in Task 8) whose `fieldExpectations` decode as `[FieldExpectation]` (Task 5).

- [ ] **Step 1: Create `valdez_alley.txt`** — verbatim from `docs/specs/v1_initial_greenfield.md:400-408`, timestamps stripped, one paragraph per line:

```text
BREAK, BREAK! This is Medic Kilo-6. I have a MEDEVAC request! Grid coordinate Eight-Seven-Three-Four, Niner-One-Two-Zero. I repeat: 8734 9120. Frequency is 44.50, Call-sign Reaper. We have one Urgent Surgical, GSW to the chest. Over!
Casualty is US Military, Battle Roster Romeo-Delta-Six-Niner-Four-Two. Name is Dawson, Robert. Last four is 6942. Dawson, stay with me! He's got NKDA, no allergies. Mechanism was Small Arms Fire, single GSW to the upper right chest. Time of injury was 14:02 Local.
Check his pulse. Radial is weak, barely there. He's breathing fast, maybe 32 a minute. SpO2 is dropping, we're at 88%. AVPU is P, he's only responding to pain. He's unstable. Mark the DD1380: Vitals taken at 14:10. Heart rate 135, BP is 88 over 60.
I'm applying a vented chest seal to that exit wound now. Breathing is still labored. I'm moving to a Needle Decompression, right side, second intercostal space. Okay, air hiss noted. SpO2 coming back up to 93%. I'm initiating a saline lock. Giving one gram of TXA over ten minutes. Also starting 500mL of Hextend since the radial pulse is still weak.
Pickup site is secure, no enemy in the area. Marking with green smoke. Casualty is US Military. HLZ is a flat clear-cut, no obstacles. Medic Kilo-6, out!
```

- [ ] **Step 2: Create `valdez_alley.json`**

```json
{
  "keywords": ["8734", "9120", "44.50", "Reaper", "urgent surgical", "GSW", "chest", "AVPU", "pain", "SpO2", "88", "93", "TXA", "Hextend", "chest seal", "needle decompression", "NKDA", "Dawson", "6942"],
  "keywordCaveat": "Fixture-overfitted list (contains proper nouns). Secondary metric only — WER and extraction recall are primary.",
  "knownDefects": ["TTS voice garbles 'TXA' on the med line — report TXA-related errors separately; do not tune the normalizer to hide them."],
  "extraFolds": [["t", "x", "a", "txa"], ["spo", "2", "spo2"], ["dd", "1380", "dd1380"]],
  "fieldExpectations": [
    { "key": "moi", "expected": "gsw", "mode": "contains" },
    { "key": "hr", "expected": "135", "mode": "exact" },
    { "key": "bp", "expected": "88/60", "mode": "exact" },
    { "key": "rr", "expected": "32", "mode": "exact" },
    { "key": "spo2", "expected": "93", "mode": "exact" },
    { "key": "classification", "expected": "unstable", "mode": "contains" },
    { "key": "interventions", "expected": "chest seal", "mode": "contains" },
    { "key": "interventions", "expected": "decompression", "mode": "contains" },
    { "key": "interventions", "expected": "txa", "mode": "contains" }
  ]
}
```

(`spo2` expects the final value 93 because `PatientState.vitals` holds the latest reading. If baseline shows the engine records TXA under a different wording, adjust the expectation to match the engine's actual serialization — the expectation targets engine output, not raw ASR.)

- [ ] **Step 3: Verify xcodegen bundles them as resources**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate && \
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO -skipMacroValidation | tail -2 && \
BUILT=$(xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings -skipMacroValidation 2>/dev/null \
  | awk '/ TARGET_BUILD_DIR =/{print $3}' | head -1) && \
ls "$BUILT/TCCC_IOS.app/" | grep valdez
```
Expected: `valdez_alley.txt` and `valdez_alley.json` inside the app bundle (xcodegen treats non-source files under `sources:` as resources — same mechanism that bundles the Granite runner's `test_5min.wav`).

- [ ] **Step 4: Commit**

```bash
git add TCCC_IOS/DevTools/Fixtures/
git commit -m "feat(bench): Valdez Alley reference transcript + scoring sidecar (fixture)"
```

---

### Task 7: SpeechRequestFactory (single source of recognizer config)

**Files:**
- Create: `TCCC_IOS/Audio/SpeechRequestFactory.swift`
- Modify: `TCCC_IOS/Audio/SpeechRecognizer.swift:189-192` and `:328-331` (both request-creation sites)

**Interfaces:**
- Produces: `enum SpeechRequestFactory { static func makeBufferRequest() -> SFSpeechAudioBufferRecognitionRequest }`. Task 8 consumes it; Phase 3 (WS-3 vocabulary work) will add `contextualStrings`/`customizedLanguageModel`/`taskHint` here exactly once.

- [ ] **Step 1: Create `TCCC_IOS/Audio/SpeechRequestFactory.swift`**

```swift
import Speech

/// Single source of SFSpeechRecognizer request configuration. Production
/// capture (SpeechRecognizer) and the DevTools transcription benchmark
/// build requests here, so a config change (vocabulary biasing, task
/// hints, custom LM — sprint WS-3) lands in one place and both lanes
/// measure the same recognizer the app ships.
enum SpeechRequestFactory {
    static func makeBufferRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // RF Ghost hard constraint — cloud transcription is forbidden.
        req.requiresOnDeviceRecognition = true
        return req
    }
}
```

- [ ] **Step 2: Replace both creation sites in `SpeechRecognizer.swift`**

At `:189-192` replace:
```swift
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        self.request = req
```
with:
```swift
        let req = SpeechRequestFactory.makeBufferRequest()
        self.request = req
```
At `:328-331` (inside `handleFinalResult`) replace the identical four lines with the identical two lines.

- [ ] **Step 3: Build + run existing app tests (regression gate)**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation 2>&1 | tail -3
```
Expected: `** TEST SUCCEEDED **` (existing 92 app tests + Task 1's 2).

- [ ] **Step 4: Commit**

```bash
git add TCCC_IOS/Audio/SpeechRequestFactory.swift TCCC_IOS/Audio/SpeechRecognizer.swift
git commit -m "refactor(audio): extract SpeechRequestFactory — one config source for production + bench"
```

---

### Task 8: TranscriptionBenchmark runner, view, and app mount

**Files:**
- Create: `TCCC_IOS/DevTools/TranscriptionBenchmark/AppleSpeechFileTranscriber.swift`
- Create: `TCCC_IOS/DevTools/TranscriptionBenchmark/BenchmarkReference.swift`
- Create: `TCCC_IOS/DevTools/TranscriptionBenchmark/BenchStateMapper.swift`
- Create: `TCCC_IOS/DevTools/TranscriptionBenchmark/TranscriptionBenchmarkView.swift`
- Modify: `TCCC_IOS/TCCC_IOSApp.swift` (mount)
- Modify: `project.yml` (app target gains `TCCCBench` product; `TCCC_IOSTests` gains `TCCCExtractor`)
- Create: `TCCC_IOSTests/BenchStateMapperTests.swift`

**Interfaces:**
- Consumes: `SpeechRequestFactory.makeBufferRequest()` (Task 7); `TokenNormalizer`/`WERScorer`/`KeywordRecallScorer`/`ExtractionScorer`/`FieldExpectation` (Tasks 3–5); bundled `valdez_alley.txt/.json` (Task 6); `PatientStateEngine` actor (`processTranscript(_:timestamp:)`, `snapshot() -> [String: PatientState]` — TCCCExtractor); `PatientState` (`mechanismOfInjury: String?`, `vitals.hr/rr/spo2: Int?`, `vitals.bp: BloodPressure?` with `systolic/diastolic: Int`, `classification: Classification?`, `interventions: [Intervention]` with `kind`/`description`).
- Produces: `--transcription-benchmark` launch flow writing `Documents/TranscriptionBenchmark/results/<slug>-<timestamp>.json` + `summary.md`; consumed by Task 9 and every later phase's before/after runs.

- [ ] **Step 1: project.yml dependency edits**

In the `TCCC_IOS` target `dependencies:` add (with the other TCCCKit products):
```yaml
      - package: TCCCKit
        product: TCCCBench
```
In the `TCCC_IOSTests` target `dependencies:` add:
```yaml
      - package: TCCCKit
        product: TCCCExtractor
```

- [ ] **Step 2: Create `AppleSpeechFileTranscriber.swift`** — the re-arming file-feed loop (mirrors production `handleFinalResult` re-arm semantics):

```swift
import Foundation
import Speech
import AVFoundation

/// Feeds an audio file through the on-device SFSpeechRecognizer using the
/// SAME request configuration as production capture (SpeechRequestFactory),
/// re-arming a fresh request whenever the recognizer finalizes mid-file —
/// mirroring SpeechRecognizer.handleFinalResult's continuous-narration
/// behavior. File-ingestion mode: deterministic input, no mic, no DSP.
actor AppleSpeechFileTranscriber {
    struct Output: Sendable {
        let finals: [String]
        let firstPartialLatencySec: Double?
        let wallTimeSec: Double
    }

    enum BenchError: Error, LocalizedError {
        case recognizerUnavailable
        case onDeviceUnavailable
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: "SFSpeechRecognizer unavailable"
            case .onDeviceUnavailable: "On-device recognition unsupported here"
            }
        }
    }

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finals: [String] = []
    private var firstPartialAt: Date?
    private var lastResultAt: Date = .distantPast
    private var sawError = false
    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    func transcribe(fileURL: URL) async throws -> Output {
        guard let recognizer, recognizer.isAvailable else { throw BenchError.recognizerUnavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw BenchError.onDeviceUnavailable }

        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let started = Date()
        armRequest()

        // Feed the whole file (faster than real time — model comparison
        // mode; latency figures here are ingest-relative, not real-time).
        let chunkFrames: AVAudioFrameCount = 4096
        while file.framePosition < file.length {
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { break }
            try file.read(into: buf, frameCount: chunkFrames)
            if buf.frameLength == 0 { break }
            request?.append(buf)
            // Yield so recognition callbacks interleave with feeding.
            await Task.yield()
        }
        request?.endAudio()

        // Wait for the recognizer to drain: done when no new result has
        // arrived for 3s after end-of-audio, or 60s hard cap.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if sawError { break }
            if lastResultAt != .distantPast, Date().timeIntervalSince(lastResultAt) > 3.0 { break }
            if lastResultAt == .distantPast, Date().timeIntervalSince(started) > 30 { break }
        }
        task?.cancel()
        task = nil
        request = nil

        return Output(
            finals: finals,
            firstPartialLatencySec: firstPartialAt.map { $0.timeIntervalSince(started) },
            wallTimeSec: Date().timeIntervalSince(started)
        )
    }

    // NOTE: the recognition callback must NOT capture the (non-Sendable)
    // SFSpeechRecognizer — strict concurrency. It reaches it back through
    // the actor property inside handle().
    private func armRequest() {
        guard let recognizer else { return }
        let req = SpeechRequestFactory.makeBufferRequest()
        self.request = req
        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { await self.handle(text: text, isFinal: isFinal) }
            } else if error != nil {
                Task { await self.noteError() }
            }
        }
    }

    private func handle(text: String, isFinal: Bool) {
        lastResultAt = Date()
        if firstPartialAt == nil { firstPartialAt = Date() }
        if isFinal {
            if !text.isEmpty { finals.append(text) }
            // Mid-file finalization: re-arm so the rest of the audio lands
            // in a fresh request (production parity).
            if request != nil {
                request?.endAudio()
                armRequest()
            }
        }
    }

    private func noteError() {
        sawError = true
    }
}
```

**Known sharp edge for the implementer:** after a mid-file re-arm, subsequent `request?.append(buf)` calls in the feed loop hit the NEW request because `request` is re-assigned inside the actor — the feed loop and `handle` both run on the actor, so there is no torn state. If recognition never emits (simulator without on-device assets), the 30 s no-result guard exits and `finals` is empty — the view must surface that as a failure, not a 100 % WER success.

- [ ] **Step 3: Create `BenchmarkReference.swift`**

```swift
import Foundation
import TCCCBench

/// Loads the bundled reference transcript + scoring sidecar for a fixture.
/// Slug rule: fixture file name, lowercased, spaces → underscores, extension
/// dropped ("Valdez Alley.m4a" → "valdez_alley").
struct BenchmarkSidecar: Codable {
    var keywords: [String] = []
    var keywordCaveat: String?
    var knownDefects: [String] = []
    var extraFolds: [[String]] = []
    var fieldExpectations: [FieldExpectation] = []
}

enum BenchmarkReference {
    static func slug(forFixture url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    static func load(slug: String) -> (referenceText: String, sidecar: BenchmarkSidecar)? {
        guard let txtURL = Bundle.main.url(forResource: slug, withExtension: "txt"),
              let text = try? String(contentsOf: txtURL, encoding: .utf8) else { return nil }
        var sidecar = BenchmarkSidecar()
        if let jsonURL = Bundle.main.url(forResource: slug, withExtension: "json"),
           let data = try? Data(contentsOf: jsonURL),
           let decoded = try? JSONDecoder().decode(BenchmarkSidecar.self, from: data) {
            sidecar = decoded
        }
        return (text, sidecar)
    }
}
```

- [ ] **Step 4: Create `BenchStateMapper.swift`**

```swift
import Foundation
import TCCCDomain

/// Renders the engine's PatientState into the flat [String: String] the
/// ExtractionScorer expects. Keys must match valdez_alley.json's
/// fieldExpectations.
enum BenchStateMapper {
    static func map(_ state: PatientState?) -> [String: String] {
        guard let state else { return [:] }
        var out: [String: String] = [:]
        if let moi = state.mechanismOfInjury { out["moi"] = moi.lowercased() }
        if let hr = state.vitals.hr { out["hr"] = String(hr) }
        if let bp = state.vitals.bp { out["bp"] = "\(bp.systolic)/\(bp.diastolic)" }
        if let rr = state.vitals.rr { out["rr"] = String(rr) }
        if let spo2 = state.vitals.spo2 { out["spo2"] = String(spo2) }
        if let classification = state.classification {
            out["classification"] = String(describing: classification).lowercased()
        }
        if !state.interventions.isEmpty {
            out["interventions"] = state.interventions
                .map { "\(String(describing: $0.kind)) \($0.description)" }
                .joined(separator: "; ")
                .lowercased()
        }
        return out
    }
}
```

- [ ] **Step 5: Create `TranscriptionBenchmarkView.swift`** — mirrors `GraniteAudioBenchmarkView`'s shape (status text + `.task`), plus result writing:

```swift
import SwiftUI
import TCCCBench
import TCCCExtractor

/// Launch-arg-gated benchmark screen (`--transcription-benchmark`).
/// File-ingestion mode: for every audio file in
/// Documents/TranscriptionBenchmark/fixtures/, run the on-device Apple
/// Speech lane (production request config via SpeechRequestFactory),
/// score against the bundled reference, and write JSON + markdown results
/// to Documents/TranscriptionBenchmark/results/.
struct TranscriptionBenchmarkView: View {
    @State private var status = "Starting transcription benchmark…"
    @State private var summary = ""

    static var shouldRun: Bool {
        ProcessInfo.processInfo.arguments.contains("--transcription-benchmark")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("TRANSCRIPTION BENCHMARK").font(.headline)
                Text(status).font(.system(.body, design: .monospaced))
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.black)
        .foregroundStyle(Color.white)
        .task { await run() }
    }

    private func run() async {
        do {
            let fm = FileManager.default
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let fixturesDir = docs.appendingPathComponent("TranscriptionBenchmark/fixtures", isDirectory: true)
            let resultsDir = docs.appendingPathComponent("TranscriptionBenchmark/results", isDirectory: true)
            try fm.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: resultsDir, withIntermediateDirectories: true)

            let audioExtensions = Set(["m4a", "wav", "caf", "aif", "aiff"])
            let fixtures = try fm.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
                .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !fixtures.isEmpty else {
                status = "No fixtures. Copy audio into Documents/TranscriptionBenchmark/fixtures/ (devicectl copy) and relaunch."
                return
            }

            // Speech permission (first run on a fresh install).
            let auth: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            guard auth == .authorized else {
                status = "Speech recognition not authorized."
                return
            }

            var lines: [String] = []
            for fixture in fixtures {
                let slug = BenchmarkReference.slug(forFixture: fixture)
                status = "Transcribing \(fixture.lastPathComponent)…"
                let memBefore = MemoryStat.availableBytes().map { Double($0) / 1_048_576.0 }
                let transcriber = AppleSpeechFileTranscriber()
                let output = try await transcriber.transcribe(fileURL: fixture)
                let memAfter = MemoryStat.availableBytes().map { Double($0) / 1_048_576.0 }
                guard !output.finals.isEmpty else {
                    lines.append("\(slug): FAILED — recognizer produced no finals")
                    continue
                }
                let hypothesis = output.finals.joined(separator: " ")

                guard let ref = BenchmarkReference.load(slug: slug) else {
                    lines.append("\(slug): no bundled reference (\(slug).txt) — transcript captured, not scored")
                    continue
                }
                status = "Scoring \(slug)…"
                let folds = ref.sidecar.extraFolds
                let refTokens = TokenNormalizer.tokens(ref.referenceText, extraFolds: folds)
                let hypTokens = TokenNormalizer.tokens(hypothesis, extraFolds: folds)
                let wer = WERScorer.score(reference: refTokens, hypothesis: hypTokens)
                let recall = KeywordRecallScorer.score(
                    keywords: ref.sidecar.keywords, transcriptTokens: hypTokens, extraFolds: folds)

                // Extraction: feed finals through a fresh engine, then map.
                let engine = PatientStateEngine()
                var ts = Date(timeIntervalSince1970: 0)
                for final in output.finals {
                    await engine.processTranscript(final, timestamp: ts)
                    ts.addTimeInterval(5)
                }
                let snapshot = await engine.snapshot()
                let actual = BenchStateMapper.map(snapshot["PATIENT_1"])
                let extraction = ExtractionScorer.score(
                    expectations: ref.sidecar.fieldExpectations, actual: actual)

                let result = BenchmarkRunResult(
                    backend: "appleSpeech",
                    mode: "file",
                    fixture: fixture.lastPathComponent,
                    startedAt: ISO8601DateFormatter().string(from: Date()),
                    wer: wer,
                    keywordRecall: recall,
                    extraction: extraction,
                    firstPartialLatencySec: output.firstPartialLatencySec,
                    wallTimeSec: output.wallTimeSec,
                    availableMemoryBeforeMB: memBefore,
                    availableMemoryAfterMB: memAfter,
                    hypothesis: hypothesis
                )
                let stamp = Int(Date().timeIntervalSince1970)
                let outURL = resultsDir.appendingPathComponent("\(slug)-\(stamp).json")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(result).write(to: outURL)

                lines.append(String(
                    format: "%@: WER %.1f%% (S%d I%d D%d / N%d) · keywords %.0f%% (missed: %@) · extraction %d/%d · first partial %.2fs · wall %.1fs",
                    slug, wer.wer * 100, wer.substitutions, wer.insertions, wer.deletions,
                    wer.referenceCount, recall.recall * 100,
                    recall.misses.isEmpty ? "none" : recall.misses.joined(separator: ", "),
                    extraction.passedCount, extraction.fields.count,
                    output.firstPartialLatencySec ?? -1, output.wallTimeSec
                ))
            }
            let report = lines.joined(separator: "\n")
            try report.write(
                to: resultsDir.appendingPathComponent("summary.md"),
                atomically: true, encoding: .utf8)
            summary = report
            status = "Done. Pull Documents/TranscriptionBenchmark/results/."
        } catch {
            status = "Benchmark failed: \(error.localizedDescription)"
        }
    }
}

struct BenchmarkRunResult: Codable {
    let backend: String
    let mode: String
    let fixture: String
    let startedAt: String
    let wer: WERResult
    let keywordRecall: KeywordRecall
    let extraction: ExtractionScore
    let firstPartialLatencySec: Double?
    let wallTimeSec: Double
    let availableMemoryBeforeMB: Double?
    let availableMemoryAfterMB: Double?
    let hypothesis: String
}
```

**Memory fields:** the spec asks for memory telemetry per run. The Apple lane loads no in-process model (speech assets are system-managed), so a phys-footprint probe adds nothing here — record jetsam headroom instead via the existing `MemoryStat.availableBytes()` (`TCCC_IOS/App/MemoryStat.swift`), sampled immediately before and after `transcriber.transcribe(...)` and converted to MB. It returns `nil` on simulator — fine, the baseline runs on device.

- [ ] **Step 6: Mount in `TCCC_IOS/TCCC_IOSApp.swift`**

Replace the body with:

```swift
import SwiftUI

@main
struct TCCC_IOSApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            if GraniteAudioBenchmarkView.shouldRun {
                GraniteAudioBenchmarkView(state: state)
            } else if TranscriptionBenchmarkView.shouldRun {
                TranscriptionBenchmarkView()
            } else {
                ContentView(state: state)
                    .task { await state.load() }
            }
        }
    }
}
```

- [ ] **Step 7: Write the mapper test** — `TCCC_IOSTests/BenchStateMapperTests.swift` (integration through the real engine, so it survives PatientState init changes):

```swift
import XCTest
import TCCCExtractor
@testable import TCCC_IOS

final class BenchStateMapperTests: XCTestCase {
    func testMapperReadsVitalsFromEngine() async {
        let engine = PatientStateEngine()
        await engine.processTranscript("BP is 88 over 60. Heart rate 135. Respiratory rate 32.", timestamp: Date())
        let snapshot = await engine.snapshot()
        let actual = BenchStateMapper.map(snapshot["PATIENT_1"])
        XCTAssertEqual(actual["bp"], "88/60")
        XCTAssertEqual(actual["hr"], "135")
        XCTAssertEqual(actual["rr"], "32")
    }

    func testMapperEmptyStateIsEmpty() {
        XCTAssertTrue(BenchStateMapper.map(nil).isEmpty)
    }
}
```

- [ ] **Step 8: Regenerate, build, run tests**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation 2>&1 | tail -3
```
Expected: `** TEST SUCCEEDED **`. If the RR phrasing in `testMapperReadsVitalsFromEngine` doesn't extract (extractor vocabulary differs), check `Packages/TCCCKit/Tests/TCCCExtractorTests/` for the phrasing its vitals tests use and adopt that exact phrasing — the test verifies the MAPPER, not the extractor.

- [ ] **Step 9: Commit**

```bash
git add TCCC_IOS/DevTools/TranscriptionBenchmark/ TCCC_IOS/TCCC_IOSApp.swift project.yml TCCC_IOSTests/BenchStateMapperTests.swift
git commit -m "feat(bench): transcription benchmark runner — file-ingestion Apple Speech lane, WER/recall/extraction scoring, --transcription-benchmark gate"
```

---

### Task 9: Device baseline run + committed before-picture

**Files:**
- Create: `docs/research/<run-date>-transcription-baseline.md` (use the actual date, e.g. `2026-07-02-transcription-baseline.md`)

**Interfaces:**
- Consumes: everything above, plus the fixture audio at `/Users/ama/Desktop/recent tccc.ai media/Valdez Alley.m4a`.
- Produces: the sprint's baseline numbers. **Phase 2/3 A/Bs are meaningless without this — do not skip.**

- [ ] **Step 1: Build + install on the iPhone 17 Pro**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'generic/platform=iOS' \
  -configuration Debug -skipMacroValidation -allowProvisioningUpdates \
  -derivedDataPath /tmp/tccc-device-dd build | tail -2
DEV=4FC3C1DC-B809-552A-B60F-B1723ADB45B8
xcrun devicectl device install app --device "$DEV" \
  /tmp/tccc-device-dd/Build/Products/Debug-iphoneos/TCCC_IOS.app
```
Expected: `** BUILD SUCCEEDED **`, install completes ("No provider" warnings are harmless).

- [ ] **Step 2: Copy the fixture audio into the app container**

```bash
xcrun devicectl device copy to --device "$DEV" \
  --domain-type appDataContainer --domain-identifier com.aarzamen.TCCCai \
  --source "/Users/ama/Desktop/recent tccc.ai media/Valdez Alley.m4a" \
  --destination Documents/TranscriptionBenchmark/fixtures/"Valdez Alley.m4a"
```
If the destination directory doesn't exist yet, launch the app once with the benchmark arg (step 3) — it creates the tree — then re-copy and relaunch.

- [ ] **Step 3: Launch with the benchmark argument**

```bash
xcrun devicectl device process launch --device "$DEV" \
  --terminate-existing com.aarzamen.TCCCai --transcription-benchmark
```
Watch the phone screen: status line should progress Transcribing → Scoring → Done. (First run will prompt for Speech permission — approve it on-device, then relaunch.)

- [ ] **Step 4: Pull the results**

```bash
xcrun devicectl device copy from --device "$DEV" \
  --domain-type appDataContainer --domain-identifier com.aarzamen.TCCCai \
  --source Documents/TranscriptionBenchmark/results --destination /tmp/tccc-bench-results
cat /tmp/tccc-bench-results/results/summary.md
```
Expected: one summary line for `valdez_alley` with WER/keywords/extraction/latency numbers.

- [ ] **Step 5: Write the baseline doc** — `docs/research/<run-date>-transcription-baseline.md` containing: (a) the summary line + full JSON numbers, (b) the exact build SHA (from Settings → Build row on-device — Phase 0 pays off immediately), (c) TXA-line errors reported separately per the known-defect note, (d) this **acoustic replay procedure** section verbatim for Phase 2's use:

```markdown
## Acoustic replay procedure (Phase 2 DSP A/B — mic-path runs)

1. Quiet room. iPhone flat on desk, screen up, bottom edge (primary mic)
   facing the Mac, 50 cm from the MacBook speakers. Mac volume 60%.
2. Launch the app normally (no benchmark arg). Start capture on Live
   Capture. Play "Valdez Alley.m4a" on the Mac
   (`afplay "/Users/ama/Desktop/recent tccc.ai media/Valdez Alley.m4a"`).
3. Stop capture ≥10 s after playback ends. Export/pull the transcript;
   score with the same reference via the file-mode scorer pathway.
4. Three runs per configuration arm; report per-run WER and the median.
   Tag results `mode: acoustic`. Only compare acoustic vs acoustic.
```

- [ ] **Step 6: Commit + phase gate**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test 2>&1 | tail -2   # full TCCCKit suite green
cd /Users/ama/TCCC_IOS
git add docs/research/
git commit -m "docs(bench): Apple Speech baseline on Valdez Alley fixture (file mode) + acoustic replay procedure"
```
Expected: full TCCCKit suite passes (768 existing + ~14 new); baseline doc committed. **Phase 1 exit criteria met: harness exists, baseline numbers are in git.**

---

## Self-review notes (already applied)

- Task 8's transcriber deliberately reuses `SpeechRequestFactory` (Task 7) so WS-3 vocabulary changes propagate to the bench automatically — that is the plan's load-bearing DRY joint.
- The spec's "push buffers through the same ingest path the mic uses" is implemented as *same request configuration + same re-arm semantics* rather than literally routing through `SpeechRecognizer.ingestBuffer` — the mic path's ring buffer/AAC/tail machinery is irrelevant to file scoring and would need bench-only hooks in the production actor. The shared factory keeps the comparison honest; acoustic mode covers the full pipeline.
- `spo2` expectation is the final value (93) because `PatientState.vitals` is latest-wins.
- All new TCCCKit code is `Sendable`-clean value types under strict concurrency; the two app-side actors isolate their mutable state.
```
