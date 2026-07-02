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
