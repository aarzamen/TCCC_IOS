import Foundation
import MLX

/// Small public wrapper around MLX memory counters so the app target can
/// sample MLX active/cache/peak bytes without importing MLX directly.
public enum MLXMemoryProbe {
    public struct Reading: Codable, Sendable, Equatable {
        public let activeBytes: Int
        public let cacheBytes: Int
        public let peakBytes: Int

        public init(activeBytes: Int, cacheBytes: Int, peakBytes: Int) {
            self.activeBytes = activeBytes
            self.cacheBytes = cacheBytes
            self.peakBytes = peakBytes
        }
    }

    public static func reading() -> Reading {
        let snapshot = Memory.snapshot()
        return Reading(
            activeBytes: snapshot.activeMemory,
            cacheBytes: snapshot.cacheMemory,
            peakBytes: snapshot.peakMemory
        )
    }

    public static func clearCache() {
        Memory.clearCache()
    }

    public static func resetPeak() {
        Memory.peakMemory = 0
    }

    public static func setCacheLimit(bytes: Int) {
        Memory.cacheLimit = bytes
    }
}

public struct MLXArraySliceProbeResult: Codable, Sendable, Equatable {
    public struct Step: Codable, Sendable, Equatable {
        public let label: String
        public let activeBytes: Int
        public let cacheBytes: Int
        public let peakBytes: Int
    }

    public let elementCount: Int
    public let sliceCount: Int
    public let steps: [Step]

    public init(elementCount: Int, sliceCount: Int, steps: [Step]) {
        self.elementCount = elementCount
        self.sliceCount = sliceCount
        self.steps = steps
    }
}

/// Device-side probe for the open MLX slice question. It deliberately uses
/// MLX counters only; process `phys_footprint` is sampled by the app harness.
public enum MLXArraySliceProbe {
    public static func run(
        elementCount: Int = 1_600_000,
        sliceCount: Int = 160_000
    ) -> MLXArraySliceProbeResult {
        var steps: [MLXArraySliceProbeResult.Step] = []

        func capture(_ label: String) {
            let reading = MLXMemoryProbe.reading()
            steps.append(.init(
                label: label,
                activeBytes: reading.activeBytes,
                cacheBytes: reading.cacheBytes,
                peakBytes: reading.peakBytes
            ))
        }

        MLXMemoryProbe.clearCache()
        MLXMemoryProbe.resetPeak()
        capture("start")

        let base = MLXArray.zeros([elementCount])
        eval(base)
        capture("after_base_eval")

        let slice = base[..<sliceCount]
        capture("after_slice_construct")

        eval(slice)
        capture("after_slice_eval")

        _ = slice.shape
        MLXMemoryProbe.clearCache()
        capture("after_clear_cache")

        return MLXArraySliceProbeResult(
            elementCount: elementCount,
            sliceCount: sliceCount,
            steps: steps
        )
    }
}
