import SwiftUI
import AtmoraCore

/// Optional atmosphere layers for the Living Desktop. They are deliberately
/// separate from `SceneArtwork` so they can be switched off or softened
/// without changing the room itself.
struct DesktopEffectsOverlay: View {
    let environment: EnvironmentID
    let effects: DesktopEffects

    private var intensity: CGFloat { CGFloat(effects.intensity) }

    var body: some View {
        ZStack {
            if effects.bloomEnabled {
                bloomLayer
            }
            if effects.particlesEnabled && effects.motionEnabled {
                particleLayer
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Bloom

    private var bloomLayer: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let tint = Color.environmentAccent(environment)
            let strength = 0.12 + 0.30 * intensity

            for spec in bloomSpecs {
                let center = CGPoint(x: w * spec.x, y: h * spec.y)
                let radius = max(w, h) * spec.radius
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            tint.opacity(strength * spec.opacity),
                            tint.opacity(strength * spec.opacity * 0.35),
                            .clear
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
        .blendMode(.plusLighter)
        .opacity(0.55 + 0.45 * Double(intensity))
    }

    private var bloomSpecs: [(x: CGFloat, y: CGFloat, radius: CGFloat, opacity: Double)] {
        switch environment {
        case .rainyCabin:
            return [(0.84, 0.22, 0.46, 0.85), (0.42, 0.58, 0.36, 0.35)]
        case .train:
            return [(0.62, 0.30, 0.34, 0.55), (0.50, 0.80, 0.24, 0.28)]
        case .sakuraNight:
            return [(0.70, 0.36, 0.42, 0.70), (0.30, 0.72, 0.34, 0.42)]
        case .cloudLibrary:
            return [(0.24, 0.30, 0.44, 0.55), (0.76, 0.64, 0.40, 0.42)]
        case .sunsetDrive:
            return [(0.72, 0.30, 0.48, 0.78), (0.28, 0.68, 0.38, 0.42)]
        case .seasideRecords:
            return [(0.74, 0.26, 0.46, 0.60), (0.30, 0.68, 0.34, 0.34)]
        }
    }

    // MARK: - Particles

    private var particleLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawParticles(&context, size: size, time: time)
            }
        }
        .opacity(0.35 + 0.65 * Double(intensity))
        .blendMode(.screen)
    }

    private func drawParticles(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let w = size.width
        let h = size.height
        let count = 28 + Int(34 * intensity)

        for index in 0..<count {
            let seed = hash(index, 1201)
            let speed = 0.018 + 0.040 * Double(hash(index, 1203))
            let progress = (Double(seed) + time * speed).truncatingRemainder(dividingBy: 1.0)
            let sway = CGFloat(sin(time * (0.5 + Double(hash(index, 1207))) + Double(index))) * w * 0.018
            let baseX = w * CGFloat(hash(index, 1209))
            let x = (baseX + sway).truncatingRemainder(dividingBy: w)
            let y = h * CGFloat(progress)
            let flicker = 0.45 + 0.55 * abs(sin(time * (0.8 + Double(hash(index, 1211))) + Double(index)))

            switch environment {
            case .rainyCabin:
                var streak = Path()
                streak.move(to: CGPoint(x: x, y: y))
                streak.addLine(to: CGPoint(x: x - w * 0.004, y: y + h * 0.028))
                context.stroke(streak, with: .color(.white.opacity(0.10 * flicker)), lineWidth: 0.8)

            case .train:
                let radius = w * (0.0007 + 0.0014 * hash(index, 1213))
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(Color(red: 0.72, green: 0.82, blue: 0.94).opacity(0.30 * flicker))
                )

            case .sakuraNight:
                if index % 5 == 0 {
                    let radius = w * 0.0016
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(Color(red: 1.0, green: 0.88, blue: 0.62).opacity(0.65 * flicker))
                    )
                } else {
                    let petalWidth = w * (0.005 + 0.006 * hash(index, 1213))
                    let petalHeight = petalWidth * 0.55
                    var petal = Path()
                    petal.addEllipse(in: CGRect(x: x - petalWidth * 0.5, y: y - petalHeight * 0.5, width: petalWidth, height: petalHeight))
                    context.fill(
                        petal,
                        with: .color(Color(red: 1.0, green: 0.72, blue: 0.80).opacity(0.42 * flicker))
                    )
                }

            case .cloudLibrary:
                let radius = w * (0.0010 + 0.0018 * hash(index, 1213))
                let warm = index % 4 == 0
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(
                        warm
                            ? Color(red: 1.0, green: 0.84, blue: 0.58).opacity(0.50 * flicker)
                            : Color(red: 0.88, green: 0.92, blue: 1.0).opacity(0.28 * flicker)
                    )
                )

            case .sunsetDrive:
                let radius = w * (0.0007 + 0.0015 * hash(index, 1213))
                let warm = index % 4 == 0
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(
                        warm
                            ? Color(red: 1.0, green: 0.84, blue: 0.54).opacity(0.52 * flicker)
                            : Color(red: 1.0, green: 0.68, blue: 0.50).opacity(0.28 * flicker)
                    )
                )

            case .seasideRecords:
                let radius = w * (0.0007 + 0.0015 * hash(index, 1213))
                let warm = index % 3 == 0
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(
                        warm
                            ? Color(red: 1.0, green: 0.86, blue: 0.62).opacity(0.46 * flicker)
                            : Color(red: 0.76, green: 0.90, blue: 0.96).opacity(0.26 * flicker)
                    )
                )
            }
        }
    }

    private func hash(_ value: Int, _ salt: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64(value &* 374_761_393 &+ salt &* 668_265_263))
        x ^= x >> 13
        x = x &* 1_274_126_177
        x ^= x >> 16
        return CGFloat(x % 10_000) / 10_000.0
    }
}
