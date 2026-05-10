// Re-export the mlx-audio-swift modules consumed by the app target.
// Consumers `import TCCCAudio` and get MLXAudioCore + MLXAudioSTT
// surface area as if they had imported them directly.
//
// G1 adds GraniteSpeechBookmarkStore, GraniteSpeechModelResolver, and
// GraniteSpeechRuntime alongside this re-export. G0 lands only the
// SwiftPM scaffolding so the package builds cleanly.
@_exported import MLXAudioCore
@_exported import MLXAudioSTT
