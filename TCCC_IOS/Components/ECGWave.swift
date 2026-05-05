import SwiftUI
import TCCCDesign

// PLAYGROUND HOOK — see superplayground.md.
// This component is the canonical example of why the playground exists:
// it's a synthetic waveform presented with clinical-grade calibration,
// in an app whose user (a Role 1 medic) does not carry continuous ECG
// hardware. The visibility hook lets you delete it without touching
// the surrounding screen layout.

/// Synthetic ECG Lead II waveform with a 20pt graticule.
///
/// Renders a recognisable PQRST cycle scrolling right-to-left at a fixed paper
/// speed. Not physiologically accurate — visually convincing only. The wave is
/// drawn into a `Canvas` driven by `TimelineView(.animation)` so it scrolls
/// smoothly at ~30 fps without owning state.
///
/// PQRST cycle (one beat):
///   - P: small upward bump (atrial depolarisation)
///   - PR segment: flat baseline
///   - QRS: small down (Q) → tall up spike (R) → small down (S)
///   - ST segment: flat baseline (slightly elevated)
///   - T: medium upward bump (ventricular repolarisation)
///   - baseline pause
///
/// Cycle period default: 750 ms (~80 BPM, visually pleasant).
struct ECGWave: View {
    /// One full beat in seconds. 0.75s → 80 BPM.
    let beatPeriod: Double

    /// Paper speed in pt/sec. Higher = wave scrolls faster.
    let paperSpeed: CGFloat

    /// Graticule grid spacing in pt.
    let gridSpacing: CGFloat

    @Environment(\.palette) private var palette

    init(beatPeriod: Double = 0.75, paperSpeed: CGFloat = 80, gridSpacing: CGFloat = 20) {
        self.beatPeriod = beatPeriod
        self.paperSpeed = paperSpeed
        self.gridSpacing = gridSpacing
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas(rendersAsynchronously: false) { context, size in
                    drawGraticule(context: context, size: size)
                    drawWaveform(context: context, size: size, time: t)
                }
            }

            // Top-right calibration overlay
            VStack(alignment: .trailing, spacing: 2) {
                Text("25 mm/s")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg3)
                Text("10 mm/mV")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg3)
            }
            .padding(.top, 4)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .playgroundEditable(
            ElementID(screen: .vitals, category: .ecg, slot: "wave"),
            hint: ElementHint(
                label: "ECG synthetic waveform",
                supports: [.visibility, .frame]
            )
        )
    }

    // MARK: - Graticule

    private func drawGraticule(context: GraphicsContext, size: CGSize) {
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += gridSpacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += gridSpacing
        }
        context.stroke(path, with: .color(palette.grid), lineWidth: 0.5)
    }

    // MARK: - Waveform

    private func drawWaveform(context: GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 0, size.height > 0 else { return }

        let baseline = size.height * 0.55       // baseline a bit below middle
        let amplitude = size.height * 0.35      // R-spike full-scale amplitude
        let phase = (time.truncatingRemainder(dividingBy: beatPeriod)) / beatPeriod
        let pixelsPerBeat = paperSpeed * CGFloat(beatPeriod)

        // Anchor: where the "now" beat-cycle origin sits along x. We compute
        // the world-x of the most recent beat origin so the wave always lines
        // up across cycles.
        let scrollOffset = CGFloat(phase) * pixelsPerBeat
        // Build samples from right to left, walking back in cycle-fraction.
        var path = Path()
        let sampleStep: CGFloat = 1.0
        var firstPoint = true

        var x: CGFloat = 0
        while x <= size.width {
            // worldX: distance to the right of the right edge that this sample
            // represents (we scroll right-to-left, so the right edge is the
            // newest).
            let worldX = size.width - x
            // Add scrollOffset so the cycle slides smoothly.
            let cycleX = (worldX + scrollOffset).truncatingRemainder(dividingBy: pixelsPerBeat)
            let u = cycleX / pixelsPerBeat   // 0..1 within the beat
            let yOffset = sampleY(u: Double(u))
            let y = baseline - CGFloat(yOffset) * amplitude

            let point = CGPoint(x: x, y: y)
            if firstPoint {
                path.move(to: point)
                firstPoint = false
            } else {
                path.addLine(to: point)
            }
            x += sampleStep
        }

        context.stroke(
            path,
            with: .color(palette.accent),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
        )
    }

    /// Returns a normalized amplitude in roughly -0.3..1.0 for a single PQRST
    /// cycle parameterised by `u` in 0..1. Tuned by eye, not by physiology.
    private func sampleY(u: Double) -> Double {
        // Phase boundaries within the cycle (sum = 1.0):
        //   P bump          0.00 .. 0.10
        //   PR baseline     0.10 .. 0.18
        //   Q dip           0.18 .. 0.21
        //   R spike up      0.21 .. 0.25
        //   R spike down    0.25 .. 0.29
        //   S dip           0.29 .. 0.32
        //   ST baseline     0.32 .. 0.45
        //   T bump          0.45 .. 0.62
        //   TP baseline     0.62 .. 1.00
        switch u {
        case 0.00..<0.10:
            // P: gentle half-sine, peak amplitude 0.12
            let local = (u - 0.00) / 0.10
            return 0.12 * sin(local * .pi)
        case 0.10..<0.18:
            return 0.0
        case 0.18..<0.21:
            // Q: dip to -0.10
            let local = (u - 0.18) / 0.03
            return -0.10 * sin(local * .pi)
        case 0.21..<0.25:
            // R upstroke: 0 -> 1.0
            let local = (u - 0.21) / 0.04
            return local
        case 0.25..<0.29:
            // R downstroke: 1.0 -> -0.18
            let local = (u - 0.25) / 0.04
            return 1.0 - local * 1.18
        case 0.29..<0.32:
            // S recovery: -0.18 -> 0
            let local = (u - 0.29) / 0.03
            return -0.18 * (1.0 - local)
        case 0.32..<0.45:
            // ST segment slight elevation
            return 0.02
        case 0.45..<0.62:
            // T: half-sine, peak 0.22
            let local = (u - 0.45) / 0.17
            return 0.22 * sin(local * .pi)
        default:
            return 0.0
        }
    }
}
