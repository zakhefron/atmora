import SwiftUI
import AtmoraCore

/// Every environment illustration is drawn with Canvas rather than shipped as
/// a bitmap. It stays sharp at any window size, weighs nothing, and lets the
/// app animate the entire scene — not just an overlay — while sound is playing.
///
/// The visual language is deliberately anime-inspired: saturated skies, crisp
/// cel-shaded bands, luminous rim light, stylised clouds, and drifting
/// particles. Nothing is a static photograph; every scene breathes.
struct SceneArtwork: View {
    let environment: EnvironmentID
    var animated: Bool = false
    var playing: Bool = false
    /// Used by the Living Desktop preview, which animates even while audio is
    /// paused.
    var alwaysAnimates: Bool = false
    var frameInterval: TimeInterval = 1.0 / 20.0
    var motionOpacity: Double = 1.0
    /// Optional bloom and drifting-particle layers used by the Living Desktop.
    /// The main window and menu-bar thumbnail leave them off.
    var effects: DesktopEffects = DesktopEffects(
        motionEnabled: true,
        bloomEnabled: false,
        particlesEnabled: false,
        intensity: 0
    )

    private var isAnimating: Bool {
        animated && (playing || alwaysAnimates)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.2))

            if isAnimating {
                TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
                    Canvas { context, size in
                        SceneRenderer.draw(
                            environment,
                            context: &context,
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate
                        )
                    }
                }
                .opacity(motionOpacity)
                .allowsHitTesting(false)
            } else {
                Canvas { context, size in
                    SceneRenderer.draw(
                        environment,
                        context: &context,
                        size: size,
                        time: 0
                    )
                }
            }

            if effects.bloomEnabled || effects.particlesEnabled {
                DesktopEffectsOverlay(environment: environment, effects: effects)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Renderer

private enum SceneRenderer {
    // MARK: Entry point

    static func draw(
        _ environment: EnvironmentID,
        context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        switch environment {
        case .rainyCabin: rainyCabin(&context, size: size, time: time)
        case .train: train(&context, size: size, time: time)
        case .sakuraNight: sakuraNight(&context, size: size, time: time)
        case .cloudLibrary: cloudLibrary(&context, size: size, time: time)
        case .sunsetDrive: sunsetDrive(&context, size: size, time: time)
        case .seasideRecords: seasideRecords(&context, size: size, time: time)
        }
    }

    // MARK: - Rainy Cabin ("Amber Rain")

    private static func rainyCabin(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let w = size.width
        let h = size.height

        // Deep indigo room, warmed from the right by a hanging lamp.
        gradientFill(
            &context,
            Path(CGRect(origin: .zero, size: size)),
            [
                Color(red: 0.10, green: 0.11, blue: 0.20),
                Color(red: 0.07, green: 0.07, blue: 0.13),
                Color(red: 0.045, green: 0.040, blue: 0.070)
            ],
            CGPoint(x: w * 0.1, y: 0),
            CGPoint(x: w * 0.9, y: h)
        )

        let lampCenter = CGPoint(x: w * 0.845, y: h * 0.215)
        let lampSwing = wave(time, 0.55) * w * 0.010
        let lampPivot = CGPoint(x: lampCenter.x + lampSwing, y: lampCenter.y)

        // Warm bloom on the wall.
        let bloom = 0.78 + 0.10 * wave(time, 1.7) + 0.04 * wave(time, 4.3, 1.2)
        glow(&context, center: lampPivot, radius: w * 0.52, color: Color(red: 1.0, green: 0.70, blue: 0.38), opacity: 0.42 * bloom)

        // Wall panelling, barely visible.
        for index in 0..<8 {
            let x = w * (0.70 + CGFloat(index) * 0.043)
            var board = Path()
            board.move(to: CGPoint(x: x, y: 0))
            board.addLine(to: CGPoint(x: x, y: h * 0.80))
            context.stroke(board, with: .color(.black.opacity(0.12)), lineWidth: 1)
        }

        // Window frame.
        let frame = CGRect(x: w * 0.055, y: h * 0.075, width: w * 0.60, height: h * 0.615)
        let corner = w * 0.020
        let framePath = Path(roundedRect: frame, cornerRadius: corner)
        gradientFill(
            &context,
            framePath,
            [
                Color(red: 0.30, green: 0.20, blue: 0.14),
                Color(red: 0.16, green: 0.11, blue: 0.08)
            ],
            CGPoint(x: 0, y: frame.minY),
            CGPoint(x: 0, y: frame.maxY)
        )
        context.stroke(framePath, with: .color(Color(red: 0.42, green: 0.29, blue: 0.19).opacity(0.55)), lineWidth: 1)

        let glass = frame.insetBy(dx: w * 0.014, dy: w * 0.014)
        let glassPath = Path(roundedRect: glass, cornerRadius: corner * 0.55)

        // Night beyond the glass.
        context.drawLayer { layer in
            layer.clip(to: glassPath)

            gradientFill(
                &layer,
                Path(glass),
                [
                    Color(red: 0.10, green: 0.18, blue: 0.32),
                    Color(red: 0.055, green: 0.11, blue: 0.21),
                    Color(red: 0.02, green: 0.045, blue: 0.09)
                ],
                CGPoint(x: glass.minX, y: glass.minY),
                CGPoint(x: glass.maxX, y: glass.maxY)
            )

            // Anime clouds drifting slowly, wrapping off-screen.
            let cloudSpecs: [(phase: CGFloat, y: CGFloat, width: CGFloat)] = [
                (0.10, 0.335, 0.42),
                (0.46, 0.450, 0.30),
                (0.78, 0.300, 0.35)
            ]
            for (index, spec) in cloudSpecs.enumerated() {
                let speed = 0.010 + 0.004 * Double(index)
                let travel = (Double(spec.phase) + time * speed).truncatingRemainder(dividingBy: 1.0)
                let cx = glass.minX - glass.width * 0.25 + glass.width * 1.50 * CGFloat(travel)
                let cy = glass.minY + glass.height * spec.y
                drawCloud(
                    &layer,
                    center: CGPoint(x: cx, y: cy),
                    width: glass.width * spec.width,
                    height: glass.height * 0.15,
                    seed: 120 + index,
                    body: [Color(red: 0.26, green: 0.34, blue: 0.50).opacity(0.80), Color(red: 0.12, green: 0.18, blue: 0.30).opacity(0.88)],
                    highlight: Color(red: 0.62, green: 0.74, blue: 0.92).opacity(0.38)
                )
            }

            // Moon, clear of the cloud line.
            let moon = CGPoint(x: glass.minX + glass.width * 0.72, y: glass.minY + glass.height * 0.20)
            let moonRadius = w * 0.036
            let moonPulse = 0.86 + 0.10 * wave(time, 0.8)
            glow(&layer, center: moon, radius: moonRadius * 3.2, color: Color(red: 0.78, green: 0.88, blue: 1.0), opacity: 0.30 * moonPulse)
            layer.fill(
                Path(ellipseIn: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)),
                with: .color(Color(red: 0.93, green: 0.96, blue: 1.0).opacity(0.92))
            )
            layer.fill(
                Path(ellipseIn: CGRect(x: moon.x - moonRadius * 0.30, y: moon.y - moonRadius * 0.20, width: moonRadius * 0.42, height: moonRadius * 0.42)),
                with: .color(Color(red: 0.78, green: 0.84, blue: 0.94).opacity(0.35))
            )

            // Pine ridge.
            var hill = Path()
            hill.move(to: CGPoint(x: glass.minX, y: glass.maxY))
            hill.addLine(to: CGPoint(x: glass.minX, y: glass.maxY - glass.height * 0.20))
            hill.addQuadCurve(
                to: CGPoint(x: glass.maxX, y: glass.maxY - glass.height * 0.26),
                control: CGPoint(x: glass.midX, y: glass.maxY - glass.height * 0.38)
            )
            hill.addLine(to: CGPoint(x: glass.maxX, y: glass.maxY))
            hill.closeSubpath()
            layer.fill(hill, with: .color(Color(red: 0.020, green: 0.055, blue: 0.070).opacity(0.92)))

            for index in 0..<16 {
                let x = glass.minX + glass.width * hash(index, 31)
                let baseY = glass.maxY - glass.height * 0.18
                let treeHeight = glass.height * (0.08 + 0.13 * hash(index, 37))
                let treeWidth = treeHeight * 0.30
                var pine = Path()
                pine.move(to: CGPoint(x: x, y: baseY - treeHeight))
                pine.addLine(to: CGPoint(x: x - treeWidth, y: baseY))
                pine.addLine(to: CGPoint(x: x + treeWidth, y: baseY))
                pine.closeSubpath()
                layer.fill(pine, with: .color(Color(red: 0.012, green: 0.040, blue: 0.050).opacity(0.95)))
            }

            // Rain, falling and slightly wind-blown.
            for index in 0..<58 {
                let speed = 0.30 + 0.35 * Double(hash(index, 41))
                let progress = (Double(hash(index, 43)) + time * speed).truncatingRemainder(dividingBy: 1.0)
                let x = glass.minX + glass.width * hash(index, 47)
                let y = glass.minY + glass.height * CGFloat(progress)
                let length = glass.height * (0.020 + 0.055 * hash(index, 53))
                var streak = Path()
                streak.move(to: CGPoint(x: x, y: y))
                streak.addLine(to: CGPoint(x: x - length * 0.22, y: y + length))
                layer.stroke(
                    streak,
                    with: .color(.white.opacity(0.10 + 0.14 * Double(hash(index, 59)))),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
                )
            }

            // Beads of water clinging to the glass.
            for index in 0..<24 {
                let x = glass.minX + glass.width * hash(index, 63)
                let slide = (Double(hash(index, 67)) + time * (0.010 + 0.020 * Double(hash(index, 69)))).truncatingRemainder(dividingBy: 1.0)
                let y = glass.minY + glass.height * CGFloat(slide)
                let radius = w * (0.0018 + 0.0028 * hash(index, 71))
                layer.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.10 + 0.12 * Double(hash(index, 73))))
                )
                layer.fill(
                    Path(ellipseIn: CGRect(x: x - radius * 0.45, y: y - radius * 0.55, width: radius * 0.9, height: radius * 0.9)),
                    with: .color(.white.opacity(0.30))
                )
            }

            // Occasional lightning flash.
            let cycle = time.truncatingRemainder(dividingBy: 12.0)
            if cycle < 0.5 {
                let flash = 1 - cycle / 0.5
                layer.fill(Path(glass), with: .color(Color(red: 0.75, green: 0.85, blue: 1.0).opacity(0.30 * flash)))
            }

            // Glass reflection.
            var reflection = Path()
            reflection.move(to: CGPoint(x: glass.minX + glass.width * 0.04, y: glass.maxY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.50, y: glass.minY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.62, y: glass.minY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.16, y: glass.maxY))
            reflection.closeSubpath()
            layer.fill(reflection, with: .color(.white.opacity(0.045)))
        }

        // Mullions.
        let mullion = Color(red: 0.17, green: 0.115, blue: 0.085)
        context.fill(
            Path(CGRect(x: frame.midX - w * 0.004, y: frame.minY, width: w * 0.008, height: frame.height)),
            with: .color(mullion)
        )
        context.fill(
            Path(CGRect(x: frame.minX, y: frame.minY + frame.height * 0.52, width: frame.width, height: w * 0.006)),
            with: .color(mullion)
        )

        // Windowsill.
        let sill = CGRect(x: w * 0.030, y: frame.maxY - h * 0.006, width: w * 0.65, height: h * 0.034)
        gradientFill(
            &context,
            Path(roundedRect: sill, cornerRadius: 2),
            [Color(red: 0.34, green: 0.23, blue: 0.15), Color(red: 0.14, green: 0.10, blue: 0.075)],
            CGPoint(x: 0, y: sill.minY),
            CGPoint(x: 0, y: sill.maxY)
        )
        var sillLight = Path()
        sillLight.move(to: CGPoint(x: sill.minX, y: sill.minY))
        sillLight.addLine(to: CGPoint(x: sill.maxX, y: sill.minY))
        context.stroke(sillLight, with: .color(.white.opacity(0.12)), lineWidth: 1)

        // A cushioned window seat.
        let cushion = CGRect(x: w * 0.085, y: sill.minY - h * 0.030, width: w * 0.36, height: h * 0.030)
        gradientFill(
            &context,
            Path(roundedRect: cushion, cornerRadius: h * 0.012),
            [Color(red: 0.44, green: 0.22, blue: 0.19), Color(red: 0.24, green: 0.12, blue: 0.11)],
            CGPoint(x: 0, y: cushion.minY),
            CGPoint(x: 0, y: cushion.maxY)
        )
        context.stroke(
            Path(roundedRect: cushion, cornerRadius: h * 0.012),
            with: .color(.white.opacity(0.08)),
            lineWidth: 1
        )

        // Wall shelf with a few books.
        let shelfY = h * 0.535
        context.fill(
            Path(roundedRect: CGRect(x: w * 0.715, y: shelfY, width: w * 0.235, height: h * 0.012), cornerRadius: 2),
            with: .color(Color(red: 0.30, green: 0.19, blue: 0.13))
        )
        let bookColors: [Color] = [
            Color(red: 0.55, green: 0.24, blue: 0.22),
            Color(red: 0.30, green: 0.40, blue: 0.44),
            Color(red: 0.62, green: 0.46, blue: 0.26),
            Color(red: 0.34, green: 0.30, blue: 0.44)
        ]
        for index in 0..<4 {
            let bookWidth = w * (0.014 + 0.004 * hash(index, 107))
            let bookHeight = h * (0.052 + 0.018 * hash(index, 109))
            let x = w * 0.735 + CGFloat(index) * w * 0.032
            context.fill(
                Path(roundedRect: CGRect(x: x, y: shelfY - bookHeight, width: bookWidth, height: bookHeight), cornerRadius: 1.5),
                with: .color(bookColors[index])
            )
            context.fill(
                Path(CGRect(x: x + bookWidth * 0.2, y: shelfY - bookHeight * 0.78, width: bookWidth * 0.6, height: 1)),
                with: .color(.white.opacity(0.20))
            )
        }

        // A small framed print above the shelf.
        let art = CGRect(x: w * 0.745, y: h * 0.345, width: w * 0.145, height: h * 0.115)
        context.fill(Path(roundedRect: art, cornerRadius: 2), with: .color(Color(red: 0.26, green: 0.17, blue: 0.12)))
        let artInner = art.insetBy(dx: w * 0.008, dy: h * 0.008)
        gradientFill(
            &context,
            Path(artInner),
            [Color(red: 0.24, green: 0.38, blue: 0.46), Color(red: 0.10, green: 0.18, blue: 0.24)],
            CGPoint(x: artInner.minX, y: artInner.minY),
            CGPoint(x: artInner.maxX, y: artInner.maxY)
        )
        var moonInArt = Path()
        moonInArt.addEllipse(in: CGRect(x: artInner.midX - w * 0.012, y: artInner.minY + h * 0.018, width: w * 0.024, height: w * 0.024))
        context.fill(moonInArt, with: .color(Color(red: 0.92, green: 0.90, blue: 0.74).opacity(0.85)))
        var artHill = Path()
        artHill.move(to: CGPoint(x: artInner.minX, y: artInner.maxY))
        artHill.addLine(to: CGPoint(x: artInner.minX, y: artInner.maxY - h * 0.025))
        artHill.addQuadCurve(
            to: CGPoint(x: artInner.maxX, y: artInner.maxY - h * 0.018),
            control: CGPoint(x: artInner.midX, y: artInner.maxY - h * 0.050)
        )
        artHill.addLine(to: CGPoint(x: artInner.maxX, y: artInner.maxY))
        artHill.closeSubpath()
        context.fill(artHill, with: .color(Color(red: 0.05, green: 0.10, blue: 0.12).opacity(0.9)))

        // A rug to warm the floor.
        let rug = CGRect(x: w * 0.05, y: h * 0.885, width: w * 0.54, height: h * 0.085)
        context.fill(
            Path(ellipseIn: rug),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.34, green: 0.16, blue: 0.15).opacity(0.75), Color(red: 0.16, green: 0.08, blue: 0.08).opacity(0.55)]),
                startPoint: CGPoint(x: rug.midX, y: rug.minY),
                endPoint: CGPoint(x: rug.midX, y: rug.maxY)
            )
        )
        for index in 0..<3 {
            let inset = CGFloat(index) * w * 0.035
            var stripe = Path()
            stripe.addEllipse(in: rug.insetBy(dx: inset, dy: inset * 0.55))
            context.stroke(stripe, with: .color(Color(red: 0.62, green: 0.40, blue: 0.30).opacity(0.18)), lineWidth: 1)
        }

        // Hanging lamp (sways).
        var cord = Path()
        cord.move(to: CGPoint(x: lampPivot.x, y: 0))
        cord.addLine(to: CGPoint(x: lampPivot.x, y: lampPivot.y - h * 0.040))
        context.stroke(cord, with: .color(.black.opacity(0.55)), lineWidth: 1.2)

        let shade = CGRect(
            x: lampPivot.x - w * 0.050,
            y: lampPivot.y - h * 0.040,
            width: w * 0.100,
            height: h * 0.062
        )
        var shadePath = Path()
        shadePath.move(to: CGPoint(x: shade.minX, y: shade.minY))
        shadePath.addQuadCurve(to: CGPoint(x: shade.maxX, y: shade.minY), control: CGPoint(x: shade.midX, y: shade.minY - h * 0.020))
        shadePath.addLine(to: CGPoint(x: shade.maxX - w * 0.009, y: shade.maxY))
        shadePath.addQuadCurve(to: CGPoint(x: shade.minX + w * 0.009, y: shade.maxY), control: CGPoint(x: shade.midX, y: shade.maxY + h * 0.013))
        shadePath.closeSubpath()
        gradientFill(
            &context,
            shadePath,
            [Color(red: 0.36, green: 0.24, blue: 0.16), Color(red: 0.15, green: 0.10, blue: 0.07)],
            CGPoint(x: shade.minX, y: shade.minY),
            CGPoint(x: shade.maxX, y: shade.maxY)
        )

        let bulb = CGRect(x: lampPivot.x - w * 0.015, y: shade.maxY - h * 0.006, width: w * 0.030, height: h * 0.024)
        context.fill(Path(ellipseIn: bulb), with: .radialGradient(
            Gradient(colors: [
                Color(red: 1.0, green: 0.97, blue: 0.86),
                Color(red: 1.0, green: 0.78, blue: 0.42),
                Color(red: 0.92, green: 0.52, blue: 0.18).opacity(0.2)
            ]),
            center: CGPoint(x: bulb.midX, y: bulb.midY),
            startRadius: 0,
            endRadius: w * 0.024
        ))

        // Soft rays spilling from the lamp, feathered by stacking narrow cones.
        for index in 0..<3 {
            let spread = 1.0 - CGFloat(index) * 0.26
            let topHalf = w * 0.042 * spread
            let bottomLeft = w * 0.310 * spread
            let bottomRight = w * 0.105 * spread
            var beam = Path()
            beam.move(to: CGPoint(x: lampPivot.x - topHalf, y: lampPivot.y))
            beam.addLine(to: CGPoint(x: lampPivot.x - bottomLeft, y: h))
            beam.addLine(to: CGPoint(x: lampPivot.x + bottomRight, y: h))
            beam.addLine(to: CGPoint(x: lampPivot.x + topHalf, y: lampPivot.y))
            beam.closeSubpath()
            context.fill(beam, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.80, blue: 0.50).opacity(0.035),
                    Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.012),
                    .clear
                ]),
                startPoint: CGPoint(x: lampPivot.x, y: lampPivot.y),
                endPoint: CGPoint(x: lampPivot.x, y: h)
            ))
        }

        // Potted plant, leaves swaying.
        let potCenter = CGPoint(x: w * 0.855, y: h * 0.905)
        var pot = Path()
        pot.move(to: CGPoint(x: potCenter.x - w * 0.055, y: potCenter.y - h * 0.10))
        pot.addLine(to: CGPoint(x: potCenter.x + w * 0.055, y: potCenter.y - h * 0.10))
        pot.addLine(to: CGPoint(x: potCenter.x + w * 0.038, y: potCenter.y))
        pot.addLine(to: CGPoint(x: potCenter.x - w * 0.038, y: potCenter.y))
        pot.closeSubpath()
        gradientFill(
            &context,
            pot,
            [Color(red: 0.38, green: 0.22, blue: 0.16), Color(red: 0.18, green: 0.10, blue: 0.08)],
            CGPoint(x: potCenter.x - w * 0.055, y: 0),
            CGPoint(x: potCenter.x + w * 0.055, y: 0)
        )
        for index in 0..<7 {
            let phase = Double(index) * 1.3
            let sway = wave(time, 0.9, phase) * w * 0.012
            let tip = CGPoint(
                x: potCenter.x + (hash(index, 61) - 0.5) * w * 0.16 + sway,
                y: potCenter.y - h * (0.12 + 0.16 * hash(index, 67))
            )
            var stem = Path()
            stem.move(to: CGPoint(x: potCenter.x, y: potCenter.y - h * 0.10))
            stem.addQuadCurve(
                to: tip,
                control: CGPoint(x: potCenter.x + (tip.x - potCenter.x) * 0.3, y: potCenter.y - h * 0.20)
            )
            context.stroke(stem, with: .color(Color(red: 0.16, green: 0.36, blue: 0.26)), lineWidth: 1.6)
            let leafSize = w * (0.022 + 0.016 * hash(index, 71))
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - leafSize, y: tip.y - leafSize * 0.55, width: leafSize * 2, height: leafSize * 1.1)),
                with: .color(Color(red: 0.17, green: 0.37, blue: 0.27).opacity(0.92))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - leafSize * 0.7, y: tip.y - leafSize * 0.5, width: leafSize * 0.8, height: leafSize * 0.5)),
                with: .color(Color(red: 0.34, green: 0.58, blue: 0.41).opacity(0.42))
            )
        }

        // A cat asleep on the cushion, breathing.
        drawCat(&context, at: CGPoint(x: w * 0.21, y: sill.minY - h * 0.030), scale: w * 0.0010, time: time)

        // A small stack of books on the sill.
        for index in 0..<2 {
            let width = w * (0.058 - CGFloat(index) * 0.008)
            let height = h * 0.012
            let x = w * 0.470 + CGFloat(index) * w * 0.004
            let y = sill.minY - h * 0.012 - CGFloat(index) * height
            context.fill(
                Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: 1.5),
                with: .color(index == 0 ? Color(red: 0.42, green: 0.24, blue: 0.22) : Color(red: 0.30, green: 0.34, blue: 0.38))
            )
        }

        // A mug of something warm.
        let mug = CGPoint(x: w * 0.600, y: sill.minY - h * 0.002)
        context.fill(
            Path(roundedRect: CGRect(x: mug.x - w * 0.021, y: mug.y - h * 0.040, width: w * 0.042, height: h * 0.040), cornerRadius: w * 0.006),
            with: .color(Color(red: 0.86, green: 0.78, blue: 0.65).opacity(0.92))
        )
        var handle = Path()
        handle.addArc(center: CGPoint(x: mug.x + w * 0.023, y: mug.y - h * 0.022), radius: w * 0.011, startAngle: .degrees(-70), endAngle: .degrees(70), clockwise: false)
        context.stroke(handle, with: .color(Color(red: 0.80, green: 0.71, blue: 0.58).opacity(0.9)), lineWidth: 1.8)
        context.fill(
            Path(ellipseIn: CGRect(x: mug.x - w * 0.021, y: mug.y - h * 0.044, width: w * 0.042, height: h * 0.009)),
            with: .color(Color(red: 0.30, green: 0.19, blue: 0.12).opacity(0.9))
        )
        for index in 0..<3 {
            let phase = time * 0.55 + Double(index) * 2.1
            let baseX = mug.x - w * 0.008 + CGFloat(index) * w * 0.008
            let sway = CGFloat(sin(phase)) * w * 0.010
            var steam = Path()
            steam.move(to: CGPoint(x: baseX, y: mug.y - h * 0.048))
            steam.addCurve(
                to: CGPoint(x: baseX + sway, y: mug.y - h * 0.048 - h * 0.080),
                control1: CGPoint(x: baseX - w * 0.011, y: mug.y - h * 0.070),
                control2: CGPoint(x: baseX + w * 0.012 + sway, y: mug.y - h * 0.092)
            )
            let opacity = 0.06 + 0.05 * (0.5 + 0.5 * sin(phase + 1.1))
            context.stroke(steam, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }

        // Dust motes in the lamplight.
        for index in 0..<18 {
            let phase = Double(hash(index, 81)) * 6.28
            let x = w * (0.62 + 0.34 * hash(index, 83)) + CGFloat(sin(time * 0.22 + phase)) * w * 0.018
            let y = h * (0.16 + 0.60 * hash(index, 89)) + CGFloat(cos(time * 0.18 + phase)) * h * 0.014
            let radius = w * (0.0012 + 0.0020 * hash(index, 97))
            let twinkle = 0.5 + 0.5 * sin(time * (0.5 + Double(hash(index, 101))) + phase)
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 1.0, green: 0.86, blue: 0.60).opacity(0.10 + 0.35 * twinkle))
            )
        }

        vignette(&context, size: size, top: 0.28, bottom: 0.52)
    }

    // MARK: - Train Compartment ("Night Train")

    private static func train(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let w = size.width
        let h = size.height

        // Warm carriage interior.
        gradientFill(
            &context,
            Path(CGRect(origin: .zero, size: size)),
            [
                Color(red: 0.20, green: 0.13, blue: 0.09),
                Color(red: 0.10, green: 0.065, blue: 0.050),
                Color(red: 0.035, green: 0.028, blue: 0.026)
            ],
            CGPoint(x: w * 0.2, y: 0),
            CGPoint(x: w * 0.8, y: h)
        )

        // Wood panelling and a warm trim rail above the window.
        for index in 0..<14 {
            let x = w * (0.015 + 0.076 * CGFloat(index))
            var seam = Path()
            seam.move(to: CGPoint(x: x, y: 0))
            seam.addLine(to: CGPoint(x: x, y: h * 0.72))
            context.stroke(seam, with: .color(.black.opacity(0.10)), lineWidth: 1)
        }
        context.fill(
            Path(CGRect(x: 0, y: h * 0.070, width: w, height: h * 0.007)),
            with: .color(Color(red: 0.34, green: 0.21, blue: 0.14))
        )
        context.fill(
            Path(CGRect(x: 0, y: h * 0.070, width: w, height: h * 0.002)),
            with: .color(.white.opacity(0.10))
        )

        // Overhead reading light (sways with the carriage).
        let lampSwing = wave(time, 0.8) * w * 0.006
        let lampCenter = CGPoint(x: w * 0.50 + lampSwing, y: h * 0.045)
        let lampGlow = w * 0.34
        glow(&context, center: lampCenter, radius: lampGlow, color: Color(red: 1.0, green: 0.80, blue: 0.50), opacity: 0.30)
        context.fill(
            Path(roundedRect: CGRect(x: lampCenter.x - w * 0.070, y: lampCenter.y - h * 0.004, width: w * 0.140, height: h * 0.020), cornerRadius: h * 0.010),
            with: .color(Color(red: 0.94, green: 0.82, blue: 0.64).opacity(0.72))
        )

        // Window.
        let windowRect = CGRect(x: w * 0.075, y: h * 0.095, width: w * 0.85, height: h * 0.535)
        let corner = w * 0.028
        let framePath = Path(roundedRect: windowRect, cornerRadius: corner)
        gradientFill(
            &context,
            framePath,
            [Color(red: 0.30, green: 0.20, blue: 0.14), Color(red: 0.14, green: 0.09, blue: 0.07)],
            CGPoint(x: 0, y: windowRect.minY),
            CGPoint(x: 0, y: windowRect.maxY)
        )

        let glass = windowRect.insetBy(dx: w * 0.016, dy: w * 0.016)
        let glassPath = Path(roundedRect: glass, cornerRadius: w * 0.018)

        context.drawLayer { layer in
            layer.clip(to: glassPath)

            gradientFill(
                &layer,
                Path(glass),
                [
                    Color(red: 0.045, green: 0.085, blue: 0.160),
                    Color(red: 0.020, green: 0.040, blue: 0.090),
                    Color(red: 0.008, green: 0.014, blue: 0.034)
                ],
                CGPoint(x: glass.minX, y: glass.minY),
                CGPoint(x: glass.maxX, y: glass.maxY)
            )

            // Moon.
            let moon = CGPoint(x: glass.minX + glass.width * 0.22, y: glass.minY + glass.height * 0.24)
            let moonRadius = w * 0.034
            glow(&layer, center: moon, radius: moonRadius * 3.0, color: Color(red: 0.86, green: 0.92, blue: 1.0), opacity: 0.22)
            layer.fill(
                Path(ellipseIn: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)),
                with: .color(Color(red: 0.94, green: 0.95, blue: 0.92).opacity(0.90))
            )

            // Stars.
            for index in 0..<70 {
                let x = glass.minX + glass.width * hash(index, 901)
                let y = glass.minY + glass.height * 0.70 * hash(index, 903)
                let radius = 0.3 + 1.0 * pow(hash(index, 907), 3)
                let twinkle = 0.5 + 0.5 * sin(time * (0.4 + 0.8 * Double(hash(index, 909))) + Double(hash(index, 911)) * 6.28)
                layer.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.12 + 0.50 * twinkle))
                )
            }

            // Moonlit hills, scrolling in three parallax layers. Each layer is
            // a smooth silhouette with a cool rim on its crest, so the landscape
            // reads as depth rather than a flat black mass.
            struct RidgeLayer {
                let speed: Double
                let base: CGFloat
                let amplitude: CGFloat
                let color: Color
                let rim: Color
                let seed: Int
            }
            let ridges: [RidgeLayer] = [
                RidgeLayer(
                    speed: 0.012, base: 0.24, amplitude: 0.055,
                    color: Color(red: 0.075, green: 0.115, blue: 0.180).opacity(0.80),
                    rim: Color(red: 0.55, green: 0.70, blue: 0.92).opacity(0.16),
                    seed: 913
                ),
                RidgeLayer(
                    speed: 0.024, base: 0.16, amplitude: 0.085,
                    color: Color(red: 0.040, green: 0.070, blue: 0.105).opacity(0.90),
                    rim: Color(red: 0.42, green: 0.58, blue: 0.80).opacity(0.14),
                    seed: 947
                ),
                RidgeLayer(
                    speed: 0.048, base: 0.075, amplitude: 0.070,
                    color: Color(red: 0.014, green: 0.028, blue: 0.044).opacity(0.96),
                    rim: Color(red: 0.30, green: 0.44, blue: 0.62).opacity(0.10),
                    seed: 971
                )
            ]

            for (ridgeIndex, ridge) in ridges.enumerated() {
                let scroll = CGFloat((time * ridge.speed).truncatingRemainder(dividingBy: 1.0))
                for repeatIndex in 0..<2 {
                    let offset = glass.width * (scroll + CGFloat(repeatIndex))
                    let span = glass.width
                    let segments = 6
                    var crest = Path()
                    var silhouette = Path()
                    let startX = glass.minX - offset
                    let startY = glass.maxY - glass.height * ridge.base
                    crest.move(to: CGPoint(x: startX, y: startY))
                    for step in 1...segments {
                        let t = CGFloat(step) / CGFloat(segments)
                        let x = startX + span * t
                        let lift = glass.height * ridge.amplitude * (0.45 + 0.55 * hash(step + repeatIndex * 11, ridge.seed))
                        let y = startY - lift
                        let controlLift = glass.height * ridge.amplitude * (0.55 + 0.60 * hash(step + repeatIndex * 11, ridge.seed + 1))
                        crest.addQuadCurve(
                            to: CGPoint(x: x, y: y),
                            control: CGPoint(x: x - span / CGFloat(segments) * 0.5, y: y - controlLift)
                        )
                    }
                    silhouette.addPath(crest)
                    silhouette.addLine(to: CGPoint(x: startX + span, y: glass.maxY))
                    silhouette.addLine(to: CGPoint(x: startX, y: glass.maxY))
                    silhouette.closeSubpath()

                    layer.fill(silhouette, with: .color(ridge.color))
                    layer.stroke(crest, with: .color(ridge.rim), style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                }

                // Village lights nestled in the valley, drawn after the mid
                // ridge but before the near embankment so they are occluded
                // naturally instead of floating over the hillside.
                if ridgeIndex == 1 {
                    for index in 0..<12 {
                        let speed = 0.030 + 0.028 * Double(hash(index, 917))
                        let progress = (Double(hash(index, 919)) + time * speed).truncatingRemainder(dividingBy: 1.0)
                        let x = glass.minX + glass.width * CGFloat(progress)
                        let y = glass.maxY - glass.height * (0.145 + 0.070 * hash(index, 921))
                        let radius = w * (0.0020 + 0.0026 * hash(index, 923))
                        let flicker = 0.7 + 0.3 * sin(time * 2.0 + Double(index))
                        layer.fill(
                            Path(ellipseIn: CGRect(x: x - radius * 3.2, y: y - radius * 3.2, width: radius * 6.4, height: radius * 6.4)),
                            with: .radialGradient(
                                Gradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.42).opacity(0.30 * flicker), .clear]),
                                center: CGPoint(x: x, y: y),
                                startRadius: 0,
                                endRadius: radius * 3.2
                            )
                        )
                        layer.fill(
                            Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(Color(red: 1.0, green: 0.86, blue: 0.56).opacity(0.75 * flicker))
                        )
                    }
                }
            }

            // Telegraph poles, near and fast.
            for index in 0..<5 {
                let speed = 0.18 + 0.05 * Double(hash(index, 927))
                let progress = (Double(hash(index, 929)) + time * speed).truncatingRemainder(dividingBy: 1.0)
                let x = glass.minX + glass.width * CGFloat(progress)
                let poleHeight = glass.height * (0.30 + 0.10 * hash(index, 931))
                var pole = Path()
                pole.move(to: CGPoint(x: x, y: glass.maxY))
                pole.addLine(to: CGPoint(x: x, y: glass.maxY - poleHeight))
                layer.stroke(pole, with: .color(Color(red: 0.015, green: 0.025, blue: 0.035).opacity(0.9)), lineWidth: 1.6)
                var cross = Path()
                cross.move(to: CGPoint(x: x - w * 0.010, y: glass.maxY - poleHeight * 0.82))
                cross.addLine(to: CGPoint(x: x + w * 0.010, y: glass.maxY - poleHeight * 0.82))
                layer.stroke(cross, with: .color(Color(red: 0.015, green: 0.025, blue: 0.035).opacity(0.9)), lineWidth: 1.2)
            }

            // Glass reflection.
            var reflection = Path()
            reflection.move(to: CGPoint(x: glass.minX + glass.width * 0.06, y: glass.maxY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.44, y: glass.minY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.58, y: glass.minY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.20, y: glass.maxY))
            reflection.closeSubpath()
            layer.fill(reflection, with: .color(.white.opacity(0.035)))
        }

        // Mullion.
        context.fill(
            Path(CGRect(x: windowRect.midX - w * 0.004, y: windowRect.minY + w * 0.010, width: w * 0.008, height: windowRect.height - w * 0.020)),
            with: .color(Color(red: 0.20, green: 0.14, blue: 0.10))
        )
        context.stroke(glassPath, with: .color(.white.opacity(0.07)), lineWidth: 1)

        // Curtains, breathing.
        for side in 0..<2 {
            let isLeft = side == 0
            let baseX = isLeft ? windowRect.minX - w * 0.048 : windowRect.maxX - w * 0.018
            let breathe = wave(time, 0.5, isLeft ? 0 : 1.8) * w * 0.006
            let x = baseX + breathe
            let curtain = CGRect(x: x, y: windowRect.minY - h * 0.02, width: w * 0.066, height: windowRect.height + h * 0.06)
            gradientFill(
                &context,
                Path(roundedRect: curtain, cornerRadius: w * 0.010),
                [Color(red: 0.40, green: 0.18, blue: 0.16), Color(red: 0.18, green: 0.075, blue: 0.070)],
                CGPoint(x: curtain.minX, y: 0),
                CGPoint(x: curtain.maxX, y: 0)
            )
            for fold in 0..<3 {
                let foldX = curtain.minX + curtain.width * (0.20 + CGFloat(fold) * 0.28)
                var crease = Path()
                crease.move(to: CGPoint(x: foldX, y: curtain.minY))
                crease.addLine(to: CGPoint(x: foldX, y: curtain.maxY))
                context.stroke(crease, with: .color(.black.opacity(0.18)), lineWidth: 1)
            }
        }

        // Seats.
        let sway = wave(time, 0.9) * w * 0.003
        let seatTop = h * 0.675
        for side in 0..<2 {
            let x = (side == 0 ? -w * 0.10 : w * 0.62) + sway
            let seat = CGRect(x: x, y: seatTop, width: w * 0.48, height: h * 0.44)
            gradientFill(
                &context,
                Path(roundedRect: seat, cornerRadius: w * 0.032),
                [Color(red: 0.34, green: 0.18, blue: 0.15), Color(red: 0.12, green: 0.065, blue: 0.055)],
                CGPoint(x: seat.minX, y: seat.minY),
                CGPoint(x: seat.maxX, y: seat.maxY)
            )
            // Padded top cushion.
            let cushion = CGRect(
                x: seat.minX + seat.width * 0.06,
                y: seat.minY + h * 0.012,
                width: seat.width * 0.88,
                height: h * 0.062
            )
            gradientFill(
                &context,
                Path(roundedRect: cushion, cornerRadius: h * 0.030),
                [Color(red: 0.44, green: 0.24, blue: 0.20), Color(red: 0.24, green: 0.13, blue: 0.11)],
                CGPoint(x: cushion.minX, y: cushion.minY),
                CGPoint(x: cushion.maxX, y: cushion.maxY)
            )
            // Stitching seam.
            var seam = Path()
            seam.move(to: CGPoint(x: cushion.minX + w * 0.010, y: cushion.maxY + h * 0.008))
            seam.addLine(to: CGPoint(x: cushion.maxX - w * 0.010, y: cushion.maxY + h * 0.008))
            context.stroke(seam, with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            // Linen headrest cover, the small comfort of a night train.
            let linen = CGRect(
                x: seat.midX - seat.width * 0.16,
                y: seat.minY + h * 0.024,
                width: seat.width * 0.32,
                height: h * 0.040
            )
            context.fill(
                Path(roundedRect: linen, cornerRadius: h * 0.016),
                with: .color(Color(red: 0.86, green: 0.82, blue: 0.72).opacity(0.11))
            )
            context.stroke(
                Path(roundedRect: linen, cornerRadius: h * 0.016),
                with: .color(.white.opacity(0.08)),
                lineWidth: 1
            )
            // Padded armrest on the aisle side.
            let armX = side == 0 ? seat.maxX - w * 0.030 : seat.minX + w * 0.006
            context.fill(
                Path(roundedRect: CGRect(x: armX, y: seat.minY + h * 0.145, width: w * 0.024, height: h * 0.052), cornerRadius: h * 0.026),
                with: .color(Color(red: 0.42, green: 0.24, blue: 0.19))
            )
        }

        // Table.
        let tableTop = h * 0.795
        gradientFill(
            &context,
            Path(roundedRect: CGRect(x: w * 0.315 + sway, y: tableTop, width: w * 0.370, height: h * 0.115), cornerRadius: w * 0.012),
            [Color(red: 0.40, green: 0.25, blue: 0.18), Color(red: 0.17, green: 0.10, blue: 0.075)],
            CGPoint(x: 0, y: tableTop),
            CGPoint(x: 0, y: tableTop + h * 0.115)
        )
        var tableEdge = Path()
        tableEdge.move(to: CGPoint(x: w * 0.315 + sway, y: tableTop))
        tableEdge.addLine(to: CGPoint(x: w * 0.685 + sway, y: tableTop))
        context.stroke(tableEdge, with: .color(.white.opacity(0.16)), lineWidth: 1)
        // A slim pedestal under the tray.
        context.fill(
            Path(roundedRect: CGRect(x: w * 0.485 + sway, y: tableTop + h * 0.115, width: w * 0.030, height: h * 0.070), cornerRadius: 2),
            with: .color(Color(red: 0.15, green: 0.09, blue: 0.07))
        )

        // A closed book on the table.
        let bookRect = CGRect(
            x: w * 0.355 + sway,
            y: tableTop + h * 0.010,
            width: w * 0.100,
            height: h * 0.026
        )
        // Page block.
        context.fill(
            Path(roundedRect: bookRect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3),
            with: .color(Color(red: 0.88, green: 0.83, blue: 0.72).opacity(0.85))
        )
        // Cover.
        gradientFill(
            &context,
            Path(roundedRect: bookRect, cornerRadius: 2),
            [Color(red: 0.34, green: 0.20, blue: 0.20), Color(red: 0.20, green: 0.11, blue: 0.12)],
            CGPoint(x: bookRect.minX, y: bookRect.minY),
            CGPoint(x: bookRect.maxX, y: bookRect.maxY)
        )
        // Spine and a thin gilt title line.
        var bookSpine = Path()
        bookSpine.move(to: CGPoint(x: bookRect.minX + w * 0.008, y: bookRect.minY))
        bookSpine.addLine(to: CGPoint(x: bookRect.minX + w * 0.008, y: bookRect.maxY))
        context.stroke(bookSpine, with: .color(.black.opacity(0.35)), lineWidth: 1)
        var gilt = Path()
        gilt.move(to: CGPoint(x: bookRect.minX + w * 0.018, y: bookRect.midY))
        gilt.addLine(to: CGPoint(x: bookRect.minX + w * 0.080, y: bookRect.midY))
        context.stroke(gilt, with: .color(Color(red: 0.86, green: 0.68, blue: 0.38).opacity(0.55)), lineWidth: 1)

        // Cup with steam.
        let cup = CGPoint(x: w * 0.575 + sway, y: h * 0.862)
        context.fill(
            Path(roundedRect: CGRect(x: cup.x - w * 0.023, y: cup.y - h * 0.032, width: w * 0.046, height: h * 0.050), cornerRadius: w * 0.009),
            with: .color(Color(red: 0.78, green: 0.72, blue: 0.62).opacity(0.82))
        )
        var cupHandle = Path()
        cupHandle.addArc(center: CGPoint(x: cup.x + w * 0.025, y: cup.y - h * 0.016), radius: w * 0.012, startAngle: .degrees(-70), endAngle: .degrees(70), clockwise: false)
        context.stroke(cupHandle, with: .color(Color(red: 0.74, green: 0.68, blue: 0.58).opacity(0.85)), lineWidth: 2)
        context.fill(
            Path(ellipseIn: CGRect(x: cup.x - w * 0.023, y: cup.y - h * 0.036, width: w * 0.046, height: h * 0.011)),
            with: .color(Color(red: 0.28, green: 0.18, blue: 0.12).opacity(0.9))
        )
        for index in 0..<3 {
            let phase = time * 0.5 + Double(index) * 2.0
            let baseX = cup.x - w * 0.010 + CGFloat(index) * w * 0.010
            let drift = CGFloat(sin(phase)) * w * 0.012
            var steam = Path()
            steam.move(to: CGPoint(x: baseX, y: cup.y - h * 0.036))
            steam.addCurve(
                to: CGPoint(x: baseX + drift, y: cup.y - h * 0.120),
                control1: CGPoint(x: baseX - w * 0.014, y: cup.y - h * 0.070),
                control2: CGPoint(x: baseX + w * 0.016 + drift, y: cup.y - h * 0.095)
            )
            context.stroke(steam, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }

        vignette(&context, size: size, top: 0.34, bottom: 0.56)
    }

    // MARK: - Sakura Night ("Lantern River")

    private static func sakuraNight(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let w = size.width
        let h = size.height

        gradientFill(
            &context,
            Path(CGRect(origin: .zero, size: size)),
            [
                Color(red: 0.035, green: 0.030, blue: 0.095),
                Color(red: 0.115, green: 0.055, blue: 0.145),
                Color(red: 0.290, green: 0.105, blue: 0.165)
            ],
            CGPoint(x: w * 0.5, y: 0),
            CGPoint(x: w * 0.5, y: h * 0.72)
        )

        // Stars, quieter near the horizon.
        for index in 0..<110 {
            let x = w * hash(index, 1301)
            let y = h * 0.60 * pow(hash(index, 1303), 1.25)
            let radius = 0.35 + 1.0 * pow(hash(index, 1307), 3)
            let twinkle = 0.5 + 0.5 * sin(time * (0.35 + 0.7 * Double(hash(index, 1309))) + Double(hash(index, 1311)) * 6.28)
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(0.16 + 0.48 * twinkle))
            )
        }

        // Moon, low and warm.
        let moon = CGPoint(x: w * 0.560, y: h * 0.195)
        let moonRadius = w * 0.060
        glow(&context, center: moon, radius: w * 0.22, color: Color(red: 1.0, green: 0.84, blue: 0.66), opacity: 0.30)
        context.fill(
            Path(ellipseIn: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.86),
                    Color(red: 1.0, green: 0.86, blue: 0.70)
                ]),
                center: CGPoint(x: moon.x - moonRadius * 0.25, y: moon.y - moonRadius * 0.25),
                startRadius: 0,
                endRadius: moonRadius * 1.25
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: moon.x - moonRadius * 0.42, y: moon.y - moonRadius * 0.18, width: moonRadius * 0.34, height: moonRadius * 0.26)),
            with: .color(Color(red: 0.92, green: 0.78, blue: 0.64).opacity(0.30))
        )

        // Far hills in two soft bands.
        for (index, base) in [0.575, 0.625].enumerated() {
            var hills = Path()
            hills.move(to: CGPoint(x: 0, y: h))
            hills.addLine(to: CGPoint(x: 0, y: h * base))
            for step in 0...6 {
                let x = w * CGFloat(step) / 6
                let lift = h * (0.025 + 0.040 * hash(step + index * 9, 1321))
                hills.addQuadCurve(
                    to: CGPoint(x: x, y: h * base - lift),
                    control: CGPoint(x: x - w * 0.09, y: h * base - lift - h * 0.020)
                )
            }
            hills.addLine(to: CGPoint(x: w, y: h))
            hills.closeSubpath()
            context.fill(
                hills,
                with: .color(index == 0
                    ? Color(red: 0.105, green: 0.050, blue: 0.115).opacity(0.90)
                    : Color(red: 0.060, green: 0.030, blue: 0.075).opacity(0.95))
            )
        }

        // River.
        let riverTop = h * 0.640
        gradientFill(
            &context,
            Path(CGRect(x: 0, y: riverTop, width: w, height: h - riverTop)),
            [
                Color(red: 0.135, green: 0.075, blue: 0.150),
                Color(red: 0.050, green: 0.035, blue: 0.090),
                Color(red: 0.025, green: 0.020, blue: 0.060)
            ],
            CGPoint(x: 0, y: riverTop),
            CGPoint(x: 0, y: h)
        )

        // Moon path on the water.
        for index in 0..<26 {
            let progress = CGFloat(index) / 26
            let y = riverTop + (h - riverTop) * progress
            let width = w * (0.018 + 0.075 * progress) * (0.5 + 0.5 * hash(index, 1327))
            let x = moon.x + CGFloat(sin(time * 0.6 + Double(index))) * w * 0.012
            var shimmer = Path()
            shimmer.move(to: CGPoint(x: x - width * 0.5, y: y))
            shimmer.addLine(to: CGPoint(x: x + width * 0.5, y: y))
            context.stroke(
                shimmer,
                with: .color(Color(red: 1.0, green: 0.86, blue: 0.66).opacity(0.05 + 0.13 * Double(hash(index, 1329)))),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        }

        // River ripples.
        for index in 0..<34 {
            let y = riverTop + (h - riverTop) * hash(index, 1331)
            let length = w * (0.02 + 0.10 * hash(index, 1333))
            let x = w * hash(index, 1337) + CGFloat(sin(time * 0.5 + Double(index))) * w * 0.010
            var ripple = Path()
            ripple.move(to: CGPoint(x: x, y: y))
            ripple.addQuadCurve(
                to: CGPoint(x: x + length, y: y),
                control: CGPoint(x: x + length * 0.5, y: y - h * 0.002)
            )
            context.stroke(
                ripple,
                with: .color(Color(red: 0.86, green: 0.62, blue: 0.72).opacity(0.10)),
                style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
            )
        }

        // A small vermilion torii on the far bank.
        let toriiBase = CGPoint(x: w * 0.235, y: riverTop + h * 0.010)
        let toriiWidth = w * 0.145
        let toriiHeight = h * 0.135
        let toriiColor = Color(red: 0.78, green: 0.24, blue: 0.20)
        for side in [-1.0, 1.0] {
            let x = toriiBase.x + CGFloat(side) * toriiWidth * 0.36
            var pillar = Path()
            pillar.move(to: CGPoint(x: x - w * 0.006, y: toriiBase.y))
            pillar.addLine(to: CGPoint(x: x - w * 0.004, y: toriiBase.y - toriiHeight))
            pillar.addLine(to: CGPoint(x: x + w * 0.004, y: toriiBase.y - toriiHeight))
            pillar.addLine(to: CGPoint(x: x + w * 0.006, y: toriiBase.y))
            pillar.closeSubpath()
            context.fill(pillar, with: .color(toriiColor.opacity(0.92)))
        }
        var topBeam = Path()
        topBeam.move(to: CGPoint(x: toriiBase.x - toriiWidth * 0.54, y: toriiBase.y - toriiHeight))
        topBeam.addQuadCurve(
            to: CGPoint(x: toriiBase.x + toriiWidth * 0.54, y: toriiBase.y - toriiHeight),
            control: CGPoint(x: toriiBase.x, y: toriiBase.y - toriiHeight - h * 0.020)
        )
        context.stroke(topBeam, with: .color(toriiColor), style: StrokeStyle(lineWidth: h * 0.014, lineCap: .round))
        var lowerBeam = Path()
        lowerBeam.move(to: CGPoint(x: toriiBase.x - toriiWidth * 0.42, y: toriiBase.y - toriiHeight * 0.72))
        lowerBeam.addLine(to: CGPoint(x: toriiBase.x + toriiWidth * 0.42, y: toriiBase.y - toriiHeight * 0.72))
        context.stroke(lowerBeam, with: .color(toriiColor.opacity(0.92)), style: StrokeStyle(lineWidth: h * 0.009, lineCap: .round))
        // A soft reflection.
        context.drawLayer { layer in
            layer.opacity = 0.22
            layer.scaleBy(x: 1, y: -1)
            layer.translateBy(x: 0, y: -(riverTop * 2 + h * 0.05))
            layer.fill(topBeam, with: .color(toriiColor))
        }

        // Strung paper lanterns.
        let lanternCount = 7
        var string = Path()
        string.move(to: CGPoint(x: -w * 0.02, y: h * 0.105))
        string.addQuadCurve(
            to: CGPoint(x: w * 1.02, y: h * 0.150),
            control: CGPoint(x: w * 0.50, y: h * 0.255)
        )
        context.stroke(string, with: .color(.black.opacity(0.35)), lineWidth: 1)
        for index in 0..<lanternCount {
            let t = (CGFloat(index) + 0.7) / (CGFloat(lanternCount) + 0.4)
            let x = w * (-0.02 + 1.04 * t)
            let curve = 4 * t * (1 - t)
            let y = h * (0.105 + 0.045 * t + 0.105 * curve)
            let sway = wave(time, 0.8, Double(index) * 1.3) * w * 0.006
            let lanternCenter = CGPoint(x: x + sway, y: y + h * 0.028)
            let lanternWidth = w * 0.036
            let lanternHeight = h * 0.052
            glow(&context, center: lanternCenter, radius: w * 0.055, color: Color(red: 1.0, green: 0.66, blue: 0.38), opacity: 0.18)
            var lantern = Path()
            lantern.addRoundedRect(
                in: CGRect(
                    x: lanternCenter.x - lanternWidth * 0.5,
                    y: lanternCenter.y - lanternHeight * 0.5,
                    width: lanternWidth,
                    height: lanternHeight
                ),
                cornerSize: CGSize(width: lanternWidth * 0.42, height: lanternHeight * 0.30)
            )
            gradientFill(
                &context,
                lantern,
                [
                    Color(red: 1.0, green: 0.78, blue: 0.48).opacity(0.92),
                    Color(red: 0.96, green: 0.42, blue: 0.26).opacity(0.90)
                ],
                CGPoint(x: lanternCenter.x, y: lanternCenter.y - lanternHeight * 0.5),
                CGPoint(x: lanternCenter.x, y: lanternCenter.y + lanternHeight * 0.5)
            )
            var cap = Path()
            cap.move(to: CGPoint(x: lanternCenter.x - lanternWidth * 0.26, y: lanternCenter.y - lanternHeight * 0.52))
            cap.addLine(to: CGPoint(x: lanternCenter.x + lanternWidth * 0.26, y: lanternCenter.y - lanternHeight * 0.52))
            context.stroke(cap, with: .color(Color(red: 0.24, green: 0.12, blue: 0.10)), lineWidth: 1.4)
            var cord = Path()
            cord.move(to: CGPoint(x: x, y: y))
            cord.addLine(to: CGPoint(x: lanternCenter.x, y: lanternCenter.y - lanternHeight * 0.52))
            context.stroke(cord, with: .color(.black.opacity(0.35)), lineWidth: 0.8)
        }

        // Cherry tree, entering from the right.
        let trunkBase = CGPoint(x: w * 1.015, y: h * 0.800)
        var trunk = Path()
        trunk.move(to: CGPoint(x: trunkBase.x - w * 0.035, y: trunkBase.y))
        trunk.addQuadCurve(
            to: CGPoint(x: w * 0.865, y: h * 0.520),
            control: CGPoint(x: w * 0.965, y: h * 0.690)
        )
        trunk.addQuadCurve(
            to: CGPoint(x: w * 0.930, y: h * 0.300),
            control: CGPoint(x: w * 0.905, y: h * 0.430)
        )
        trunk.addLine(to: CGPoint(x: w * 0.955, y: h * 0.290))
        trunk.addQuadCurve(
            to: CGPoint(x: w * 0.900, y: h * 0.540),
            control: CGPoint(x: w * 0.935, y: h * 0.430)
        )
        trunk.addQuadCurve(
            to: CGPoint(x: trunkBase.x + w * 0.010, y: trunkBase.y),
            control: CGPoint(x: w * 1.000, y: h * 0.700)
        )
        trunk.closeSubpath()
        gradientFill(
            &context,
            trunk,
            [Color(red: 0.235, green: 0.105, blue: 0.120), Color(red: 0.090, green: 0.040, blue: 0.060)],
            CGPoint(x: w * 0.90, y: h * 0.30),
            CGPoint(x: w * 1.02, y: h * 0.80)
        )
        var branch = Path()
        branch.move(to: CGPoint(x: w * 0.925, y: h * 0.430))
        branch.addQuadCurve(
            to: CGPoint(x: w * 0.690, y: h * 0.300),
            control: CGPoint(x: w * 0.820, y: h * 0.330)
        )
        branch.addQuadCurve(
            to: CGPoint(x: w * 0.545, y: h * 0.245),
            control: CGPoint(x: w * 0.620, y: h * 0.250)
        )
        context.stroke(branch, with: .color(Color(red: 0.150, green: 0.065, blue: 0.085)), style: StrokeStyle(lineWidth: w * 0.010, lineCap: .round))
        var upperBranch = Path()
        upperBranch.move(to: CGPoint(x: w * 0.940, y: h * 0.330))
        upperBranch.addQuadCurve(
            to: CGPoint(x: w * 0.760, y: h * 0.130),
            control: CGPoint(x: w * 0.900, y: h * 0.190)
        )
        context.stroke(upperBranch, with: .color(Color(red: 0.150, green: 0.065, blue: 0.085)), style: StrokeStyle(lineWidth: w * 0.007, lineCap: .round))

        // Blossom clusters.
        let blossomCenters: [(CGFloat, CGFloat, CGFloat)] = [
            (0.955, 0.300, 0.105), (0.900, 0.245, 0.085), (0.835, 0.205, 0.080),
            (0.760, 0.140, 0.075), (0.690, 0.285, 0.090), (0.610, 0.245, 0.072),
            (0.545, 0.235, 0.058), (0.885, 0.370, 0.070), (0.800, 0.330, 0.060)
        ]
        for (index, cluster) in blossomCenters.enumerated() {
            let center = CGPoint(x: w * cluster.0, y: h * cluster.1)
            let radius = w * cluster.2
            let breathe = 1 + 0.015 * wave(time, 0.7, Double(index))
            context.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.scaleBy(x: breathe, y: breathe)
                for petal in 0..<15 {
                    let angle = Double(petal) / 15.0 * .pi * 2 + Double(index) * 0.4
                    let distance = radius * (0.25 + 0.65 * hash(petal + index * 17, 1341))
                    let px = CGFloat(cos(angle)) * distance
                    let py = CGFloat(sin(angle)) * distance * 0.70
                    let size = radius * (0.16 + 0.14 * hash(petal + index * 19, 1343))
                    let color = petal % 3 == 0
                        ? Color(red: 1.0, green: 0.78, blue: 0.82)
                        : Color(red: 0.94, green: 0.55, blue: 0.68)
                    layer.fill(
                        Path(ellipseIn: CGRect(x: px - size, y: py - size * 0.72, width: size * 2, height: size * 1.44)),
                        with: .color(color.opacity(0.78))
                    )
                }
                layer.fill(
                    Path(ellipseIn: CGRect(x: -radius * 0.20, y: -radius * 0.18, width: radius * 0.40, height: radius * 0.36)),
                    with: .color(Color(red: 1.0, green: 0.90, blue: 0.88).opacity(0.30))
                )
            }
        }

        // Falling petals.
        for index in 0..<58 {
            let speed = 0.028 + 0.040 * Double(hash(index, 1351))
            let progress = (Double(hash(index, 1353)) + time * speed).truncatingRemainder(dividingBy: 1.0)
            let x = w * CGFloat(hash(index, 1357)) + CGFloat(sin(time * 0.7 + Double(index))) * w * 0.030
            let y = h * CGFloat(progress)
            let size = w * (0.0035 + 0.0045 * hash(index, 1359))
            let rotation = time * (0.5 + Double(hash(index, 1361))) + Double(index)
            context.drawLayer { layer in
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .radians(rotation))
                layer.fill(
                    Path(ellipseIn: CGRect(x: -size, y: -size * 0.48, width: size * 2, height: size * 0.96)),
                    with: .color(Color(red: 1.0, green: 0.74, blue: 0.82).opacity(0.38 + 0.30 * Double(hash(index, 1363))))
                )
            }
        }

        // Fireflies along the bank.
        for index in 0..<22 {
            let x = w * hash(index, 1367)
            let y = h * (0.52 + 0.30 * hash(index, 1369)) + wave(time, 0.8, Double(index)) * h * 0.012
            let pulse = 0.5 + 0.5 * sin(time * (1.0 + Double(hash(index, 1371)) * 1.4) + Double(index))
            glow(&context, center: CGPoint(x: x, y: y), radius: w * 0.010, color: Color(red: 1.0, green: 0.88, blue: 0.52), opacity: 0.12 + 0.28 * pulse)
        }

        // Reeds in the near corner.
        for index in 0..<26 {
            let baseX = w * (0.02 + 0.26 * hash(index, 1373))
            let baseY = h * (0.94 + 0.04 * hash(index, 1377))
            let height = h * (0.07 + 0.13 * hash(index, 1379))
            let sway = wave(time, 0.9, Double(index) * 0.7) * w * 0.008
            var reed = Path()
            reed.move(to: CGPoint(x: baseX, y: baseY))
            reed.addQuadCurve(
                to: CGPoint(x: baseX + sway, y: baseY - height),
                control: CGPoint(x: baseX - w * 0.010, y: baseY - height * 0.55)
            )
            context.stroke(
                reed,
                with: .color(Color(red: 0.075, green: 0.045, blue: 0.085).opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.1 + hash(index, 1381), lineCap: .round)
            )
        }

        vignette(&context, size: size, top: 0.30, bottom: 0.58)
    }

    // MARK: - Cloud Library ("The Floating Stacks")

    private static func cloudLibrary(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let w = size.width
        let h = size.height

        // Dusk sky beyond the room.
        gradientFill(
            &context,
            Path(CGRect(origin: .zero, size: size)),
            [
                Color(red: 0.105, green: 0.105, blue: 0.235),
                Color(red: 0.310, green: 0.205, blue: 0.330),
                Color(red: 0.760, green: 0.475, blue: 0.420)
            ],
            CGPoint(x: w * 0.5, y: 0),
            CGPoint(x: w * 0.5, y: h * 0.78)
        )

        // Stars in the upper sky.
        for index in 0..<64 {
            let x = w * hash(index, 1401)
            let y = h * 0.34 * hash(index, 1403)
            let radius = 0.3 + 0.9 * pow(hash(index, 1407), 3)
            let twinkle = 0.5 + 0.5 * sin(time * (0.4 + 0.6 * Double(hash(index, 1409))) + Double(index))
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(0.12 + 0.40 * twinkle))
            )
        }

        // Cloud sea below the room.
        let cloudSpecs: [(phase: CGFloat, y: CGFloat, width: CGFloat)] = [
            (0.05, 0.70, 0.42), (0.40, 0.78, 0.50), (0.72, 0.66, 0.36)
        ]
        for (index, spec) in cloudSpecs.enumerated() {
            let travel = (Double(spec.phase) + time * (0.004 + 0.002 * Double(index))).truncatingRemainder(dividingBy: 1.0)
            let cx = w * (-0.25 + 1.50 * CGFloat(travel))
            drawCloud(
                &context,
                center: CGPoint(x: cx, y: h * spec.y),
                width: w * spec.width,
                height: h * 0.16,
                seed: 140 + index,
                body: [
                    Color(red: 0.760, green: 0.640, blue: 0.720).opacity(0.70),
                    Color(red: 0.330, green: 0.270, blue: 0.400).opacity(0.82)
                ],
                highlight: Color(red: 1.0, green: 0.820, blue: 0.700).opacity(0.42)
            )
        }

        // Arched window with a moonlit view.
        let window = CGRect(x: w * 0.445, y: h * 0.090, width: w * 0.405, height: h * 0.545)
        var windowPath = Path()
        windowPath.move(to: CGPoint(x: window.minX, y: window.maxY))
        windowPath.addLine(to: CGPoint(x: window.minX, y: window.minY + window.height * 0.32))
        windowPath.addQuadCurve(
            to: CGPoint(x: window.maxX, y: window.minY + window.height * 0.32),
            control: CGPoint(x: window.midX, y: window.minY - window.height * 0.18)
        )
        windowPath.addLine(to: CGPoint(x: window.maxX, y: window.maxY))
        windowPath.closeSubpath()
        context.fill(windowPath, with: .color(Color(red: 0.045, green: 0.050, blue: 0.105)))

        context.drawLayer { layer in
            layer.clip(to: windowPath)
            gradientFill(
                &layer,
                Path(window),
                [
                    Color(red: 0.055, green: 0.075, blue: 0.180),
                    Color(red: 0.190, green: 0.150, blue: 0.300),
                    Color(red: 0.500, green: 0.290, blue: 0.360)
                ],
                CGPoint(x: window.midX, y: window.minY),
                CGPoint(x: window.midX, y: window.maxY)
            )
            let moon = CGPoint(x: window.minX + window.width * 0.68, y: window.minY + window.height * 0.30)
            let moonRadius = window.width * 0.095
            glow(&layer, center: moon, radius: window.width * 0.32, color: Color(red: 1.0, green: 0.88, blue: 0.72), opacity: 0.35)
            layer.fill(
                Path(ellipseIn: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)),
                with: .color(Color(red: 1.0, green: 0.95, blue: 0.84))
            )
            for index in 0..<38 {
                let x = window.minX + window.width * hash(index, 1411)
                let y = window.minY + window.height * 0.55 * hash(index, 1413)
                let radius = 0.4 + 1.0 * hash(index, 1417)
                layer.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.30 + 0.40 * hash(index, 1419)))
                )
            }
            // A small floating island and its lantern.
            let island = CGPoint(x: window.minX + window.width * 0.24, y: window.minY + window.height * 0.62)
            var rock = Path()
            rock.move(to: CGPoint(x: island.x - window.width * 0.075, y: island.y))
            rock.addQuadCurve(
                to: CGPoint(x: island.x, y: island.y + window.height * 0.060),
                control: CGPoint(x: island.x - window.width * 0.030, y: island.y + window.height * 0.045)
            )
            rock.addQuadCurve(
                to: CGPoint(x: island.x + window.width * 0.075, y: island.y),
                control: CGPoint(x: island.x + window.width * 0.030, y: island.y + window.height * 0.045)
            )
            rock.closeSubpath()
            layer.fill(rock, with: .color(Color(red: 0.095, green: 0.080, blue: 0.120)))
            layer.fill(
                Path(ellipseIn: CGRect(x: island.x - window.width * 0.080, y: island.y - window.height * 0.010, width: window.width * 0.160, height: window.height * 0.022)),
                with: .color(Color(red: 0.130, green: 0.190, blue: 0.145))
            )
            glow(&layer, center: CGPoint(x: island.x, y: island.y - window.height * 0.030), radius: window.width * 0.060, color: Color(red: 1.0, green: 0.72, blue: 0.38), opacity: 0.30)
            layer.fill(
                Path(roundedRect: CGRect(x: island.x - window.width * 0.008, y: island.y - window.height * 0.040, width: window.width * 0.016, height: window.height * 0.030), cornerRadius: 2),
                with: .color(Color(red: 1.0, green: 0.80, blue: 0.46).opacity(0.85))
            )
            // Rain on the glass.
            for index in 0..<90 {
                let x = window.minX + window.width * hash(index, 1421)
                let y = window.minY + window.height * hash(index, 1423)
                let length = window.height * (0.015 + 0.040 * hash(index, 1427))
                var drop = Path()
                drop.move(to: CGPoint(x: x, y: y))
                drop.addLine(to: CGPoint(x: x - window.width * 0.004, y: y + length))
                layer.stroke(drop, with: .color(Color(red: 0.780, green: 0.850, blue: 0.980).opacity(0.16)), lineWidth: 0.8)
            }
        }

        // Window frame and mullions.
        context.stroke(windowPath, with: .color(Color(red: 0.170, green: 0.110, blue: 0.095)), lineWidth: w * 0.014)
        var mullion = Path()
        mullion.move(to: CGPoint(x: window.midX, y: window.minY + window.height * 0.10))
        mullion.addLine(to: CGPoint(x: window.midX, y: window.maxY))
        context.stroke(mullion, with: .color(Color(red: 0.170, green: 0.110, blue: 0.095)), lineWidth: w * 0.007)
        var crossBar = Path()
        crossBar.move(to: CGPoint(x: window.minX, y: window.minY + window.height * 0.56))
        crossBar.addLine(to: CGPoint(x: window.maxX, y: window.minY + window.height * 0.56))
        context.stroke(crossBar, with: .color(Color(red: 0.170, green: 0.110, blue: 0.095)), lineWidth: w * 0.006)
        // Warm rim from the room.
        context.stroke(windowPath, with: .color(Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.22)), lineWidth: 1.5)

        // Room walls and floor.
        var wall = Path()
        wall.move(to: CGPoint(x: 0, y: h * 0.115))
        wall.addLine(to: CGPoint(x: w * 0.445, y: h * 0.115))
        wall.addLine(to: CGPoint(x: w * 0.445, y: h * 0.700))
        wall.addLine(to: CGPoint(x: 0, y: h * 0.700))
        wall.closeSubpath()
        gradientFill(
            &context,
            wall,
            [Color(red: 0.230, green: 0.140, blue: 0.120), Color(red: 0.120, green: 0.070, blue: 0.070)],
            CGPoint(x: 0, y: h * 0.115),
            CGPoint(x: 0, y: h * 0.700)
        )
        var rightWall = Path()
        rightWall.move(to: CGPoint(x: w * 0.850, y: h * 0.115))
        rightWall.addLine(to: CGPoint(x: w, y: h * 0.115))
        rightWall.addLine(to: CGPoint(x: w, y: h * 0.700))
        rightWall.addLine(to: CGPoint(x: w * 0.850, y: h * 0.700))
        rightWall.closeSubpath()
        context.fill(rightWall, with: .color(Color(red: 0.140, green: 0.080, blue: 0.075)))
        // Ceiling.
        var ceiling = Path()
        ceiling.move(to: CGPoint(x: 0, y: 0))
        ceiling.addLine(to: CGPoint(x: w, y: 0))
        ceiling.addLine(to: CGPoint(x: w, y: h * 0.115))
        ceiling.addLine(to: CGPoint(x: 0, y: h * 0.115))
        ceiling.closeSubpath()
        gradientFill(
            &context,
            ceiling,
            [Color(red: 0.105, green: 0.060, blue: 0.060), Color(red: 0.200, green: 0.115, blue: 0.095)],
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: h * 0.115)
        )
        // Floorboards.
        var floor = Path()
        floor.move(to: CGPoint(x: 0, y: h * 0.700))
        floor.addLine(to: CGPoint(x: w, y: h * 0.700))
        floor.addLine(to: CGPoint(x: w, y: h))
        floor.addLine(to: CGPoint(x: 0, y: h))
        floor.closeSubpath()
        gradientFill(
            &context,
            floor,
            [Color(red: 0.190, green: 0.110, blue: 0.080), Color(red: 0.075, green: 0.045, blue: 0.040)],
            CGPoint(x: 0, y: h * 0.700),
            CGPoint(x: 0, y: h)
        )
        for index in 0..<12 {
            let x = w * CGFloat(index) / 11
            var seam = Path()
            seam.move(to: CGPoint(x: x, y: h * 0.700))
            seam.addLine(to: CGPoint(x: w * 0.5 + (x - w * 0.5) * 1.30, y: h))
            context.stroke(seam, with: .color(.black.opacity(0.14)), lineWidth: 1)
        }

        // Left bookcase.
        let shelf = CGRect(x: w * 0.025, y: h * 0.145, width: w * 0.235, height: h * 0.545)
        context.fill(
            Path(roundedRect: shelf, cornerRadius: w * 0.008),
            with: .color(Color(red: 0.155, green: 0.085, blue: 0.070))
        )
        for row in 0..<4 {
            let rowY = shelf.minY + shelf.height * (0.04 + 0.245 * CGFloat(row))
            context.fill(
                Path(CGRect(x: shelf.minX + w * 0.008, y: rowY + shelf.height * 0.215, width: shelf.width - w * 0.016, height: h * 0.008)),
                with: .color(Color(red: 0.100, green: 0.055, blue: 0.045))
            )
            var cursor = shelf.minX + w * 0.012
            for book in 0..<9 {
                let width = w * (0.010 + 0.012 * hash(book + row * 13, 1431))
                let height = shelf.height * (0.13 + 0.075 * hash(book + row * 17, 1433))
                if cursor + width > shelf.maxX - w * 0.010 { break }
                let color = [
                    Color(red: 0.480, green: 0.230, blue: 0.190),
                    Color(red: 0.270, green: 0.360, blue: 0.310),
                    Color(red: 0.360, green: 0.270, blue: 0.440),
                    Color(red: 0.620, green: 0.470, blue: 0.260),
                    Color(red: 0.310, green: 0.310, blue: 0.390)
                ][(book + row) % 5]
                context.fill(
                    Path(roundedRect: CGRect(x: cursor, y: rowY + shelf.height * 0.215 - height, width: width, height: height), cornerRadius: 1),
                    with: .color(color.opacity(0.85))
                )
                context.fill(
                    Path(CGRect(x: cursor + width * 0.18, y: rowY + shelf.height * 0.215 - height * 0.70, width: width * 0.10, height: height * 0.42)),
                    with: .color(Color(red: 0.900, green: 0.780, blue: 0.560).opacity(0.38))
                )
                cursor += width + w * 0.0015
            }
        }

        // Pendant lamp.
        let lampPivot = CGPoint(x: w * 0.390 + wave(time, 0.55) * w * 0.004, y: h * 0.090)
        var cord = Path()
        cord.move(to: CGPoint(x: lampPivot.x, y: 0))
        cord.addLine(to: CGPoint(x: lampPivot.x, y: lampPivot.y))
        context.stroke(cord, with: .color(.black.opacity(0.50)), lineWidth: 1.2)
        let lamp = CGPoint(x: lampPivot.x, y: lampPivot.y + h * 0.070)
        glow(&context, center: lamp, radius: w * 0.060, color: Color(red: 1.0, green: 0.72, blue: 0.40), opacity: 0.32)
        var shade = Path()
        shade.move(to: CGPoint(x: lamp.x - w * 0.052, y: lamp.y + h * 0.032))
        shade.addQuadCurve(
            to: CGPoint(x: lamp.x + w * 0.052, y: lamp.y + h * 0.032),
            control: CGPoint(x: lamp.x, y: lamp.y - h * 0.060)
        )
        shade.closeSubpath()
        gradientFill(
            &context,
            shade,
            [Color(red: 0.980, green: 0.720, blue: 0.400), Color(red: 0.620, green: 0.330, blue: 0.190)],
            CGPoint(x: lamp.x, y: lamp.y - h * 0.040),
            CGPoint(x: lamp.x, y: lamp.y + h * 0.032)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: lamp.x - w * 0.018, y: lamp.y + h * 0.026, width: w * 0.036, height: h * 0.012)),
            with: .color(Color(red: 1.0, green: 0.92, blue: 0.72).opacity(0.90))
        )

        // A generous armchair with a sleeping cat.
        let chair = CGRect(x: w * 0.250, y: h * 0.620, width: w * 0.245, height: h * 0.280)
        gradientFill(
            &context,
            Path(roundedRect: chair, cornerRadius: w * 0.045),
            [Color(red: 0.360, green: 0.180, blue: 0.220), Color(red: 0.160, green: 0.075, blue: 0.110)],
            CGPoint(x: chair.minX, y: chair.minY),
            CGPoint(x: chair.maxX, y: chair.maxY)
        )
        context.fill(
            Path(roundedRect: CGRect(x: chair.minX + w * 0.016, y: chair.minY + h * 0.020, width: chair.width - w * 0.032, height: h * 0.075), cornerRadius: h * 0.035),
            with: .color(Color(red: 0.430, green: 0.230, blue: 0.270).opacity(0.85))
        )
        for side in [-1.0, 1.0] {
            let armX = side < 0 ? chair.minX - w * 0.008 : chair.maxX - w * 0.018
            context.fill(
                Path(roundedRect: CGRect(x: armX, y: chair.minY + h * 0.085, width: w * 0.030, height: h * 0.175), cornerRadius: h * 0.020),
                with: .color(Color(red: 0.290, green: 0.140, blue: 0.175))
            )
        }
        drawCat(
            &context,
            at: CGPoint(x: chair.midX - w * 0.010, y: chair.minY + h * 0.085),
            scale: w * 0.00125,
            time: time
        )

        // Side table, book stack, candle.
        let table = CGRect(x: w * 0.585, y: h * 0.745, width: w * 0.150, height: h * 0.028)
        context.fill(
            Path(roundedRect: table, cornerRadius: w * 0.008),
            with: .color(Color(red: 0.310, green: 0.180, blue: 0.120))
        )
        for leg in [table.minX + w * 0.012, table.maxX - w * 0.020] {
            context.fill(
                Path(roundedRect: CGRect(x: leg, y: table.maxY, width: w * 0.008, height: h * 0.145), cornerRadius: 2),
                with: .color(Color(red: 0.220, green: 0.120, blue: 0.085))
            )
        }
        for index in 0..<4 {
            let bookWidth = w * (0.075 - 0.008 * CGFloat(index))
            let y = table.minY - h * 0.022 * CGFloat(index + 1)
            context.fill(
                Path(roundedRect: CGRect(x: table.midX - bookWidth * 0.5, y: y, width: bookWidth, height: h * 0.022), cornerRadius: 1.5),
                with: .color([
                    Color(red: 0.520, green: 0.270, blue: 0.220),
                    Color(red: 0.300, green: 0.380, blue: 0.330),
                    Color(red: 0.400, green: 0.300, blue: 0.470),
                    Color(red: 0.650, green: 0.500, blue: 0.290)
                ][index].opacity(0.92))
            )
        }
        let candle = CGPoint(x: table.maxX - w * 0.020, y: table.minY - h * 0.010)
        glow(&context, center: CGPoint(x: candle.x, y: candle.y - h * 0.040), radius: w * 0.035, color: Color(red: 1.0, green: 0.78, blue: 0.42), opacity: 0.28)
        context.fill(
            Path(roundedRect: CGRect(x: candle.x - w * 0.007, y: candle.y - h * 0.035, width: w * 0.014, height: h * 0.035), cornerRadius: 2),
            with: .color(Color(red: 0.880, green: 0.820, blue: 0.700))
        )
        let flameHeight = h * (0.014 + 0.003 * wave(time, 4.0))
        var flame = Path()
        flame.move(to: CGPoint(x: candle.x, y: candle.y - h * 0.035 - flameHeight))
        flame.addQuadCurve(
            to: CGPoint(x: candle.x + w * 0.006, y: candle.y - h * 0.033),
            control: CGPoint(x: candle.x + w * 0.009, y: candle.y - h * 0.040)
        )
        flame.addQuadCurve(
            to: CGPoint(x: candle.x - w * 0.006, y: candle.y - h * 0.033),
            control: CGPoint(x: candle.x - w * 0.009, y: candle.y - h * 0.040)
        )
        flame.closeSubpath()
        context.fill(flame, with: .color(Color(red: 1.0, green: 0.82, blue: 0.44).opacity(0.92)))

        // Rug.
        var rug = Path()
        rug.addEllipse(in: CGRect(x: w * 0.180, y: h * 0.900, width: w * 0.620, height: h * 0.100))
        context.fill(rug, with: .color(Color(red: 0.310, green: 0.160, blue: 0.190).opacity(0.70)))
        var rugRim = Path()
        rugRim.addEllipse(in: CGRect(x: w * 0.205, y: h * 0.912, width: w * 0.570, height: h * 0.074))
        context.stroke(rugRim, with: .color(Color(red: 0.760, green: 0.560, blue: 0.380).opacity(0.22)), lineWidth: 1.4)

        // A potted fern by the window.
        let pot = CGPoint(x: w * 0.865, y: h * 0.845)
        context.fill(
            Path(roundedRect: CGRect(x: pot.x - w * 0.030, y: pot.y - h * 0.055, width: w * 0.060, height: h * 0.060), cornerRadius: w * 0.010),
            with: .color(Color(red: 0.420, green: 0.220, blue: 0.160))
        )
        for index in 0..<11 {
            let angle = -2.6 + 5.2 * Double(index) / 10.0
            let length = h * (0.070 + 0.060 * hash(index, 1441))
            let sway = wave(time, 0.8, Double(index) * 0.8) * w * 0.006
            var frond = Path()
            frond.move(to: CGPoint(x: pot.x, y: pot.y - h * 0.052))
            frond.addQuadCurve(
                to: CGPoint(x: pot.x + CGFloat(cos(angle)) * length * 0.70 + sway, y: pot.y - h * 0.052 + CGFloat(sin(angle)) * length),
                control: CGPoint(x: pot.x + CGFloat(cos(angle)) * length * 0.30, y: pot.y - h * 0.080 + CGFloat(sin(angle)) * length * 0.55)
            )
            context.stroke(
                frond,
                with: .color(Color(red: 0.160, green: 0.300, blue: 0.220).opacity(0.86)),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
            )
        }

        // Drifting pages and dust in the lamplight.
        for index in 0..<13 {
            let speed = 0.010 + 0.014 * Double(hash(index, 1451))
            let progress = (Double(hash(index, 1453)) + time * speed).truncatingRemainder(dividingBy: 1.0)
            let x = w * (0.32 + 0.44 * hash(index, 1457)) + CGFloat(sin(time * 0.5 + Double(index))) * w * 0.025
            let y = h * (0.18 + 0.62 * CGFloat(progress))
            let size = w * (0.005 + 0.007 * hash(index, 1459))
            let rotation = time * (0.3 + Double(hash(index, 1461))) + Double(index)
            context.drawLayer { layer in
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .radians(rotation))
                layer.fill(
                    Path(roundedRect: CGRect(x: -size * 0.5, y: -size * 0.36, width: size, height: size * 0.72), cornerRadius: 0.8),
                    with: .color(Color(red: 0.960, green: 0.900, blue: 0.780).opacity(0.28))
                )
            }
        }
        for index in 0..<30 {
            let x = w * (0.24 + 0.58 * hash(index, 1463))
            let y = h * (0.20 + 0.62 * hash(index, 1467)) + wave(time, 0.4, Double(index)) * h * 0.006
            let pulse = 0.5 + 0.5 * sin(time * (0.7 + Double(hash(index, 1469))) + Double(index))
            context.fill(
                Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)),
                with: .color(Color(red: 1.0, green: 0.86, blue: 0.62).opacity(0.10 + 0.26 * pulse))
            )
        }

        vignette(&context, size: size, top: 0.32, bottom: 0.52)
    }

    // MARK: - Shared scene objects


    // MARK: - Sunset Drive ("Golden Coast")

    /// A golden-hour drive down the coast, seen from the driver's seat.
    ///
    /// Everything moves on its own clock: the road surface and guardrail posts
    /// sweep toward the car, cypress trees slide past at a slower parallax, the
    /// sea breathes, traffic passes in the other lane, the wheel makes small
    /// corrections, and the stereo keeps time with the song.
    private static func sunsetDrive(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let w = size.width
        let h = size.height
        let s = min(w, h)

        // A car on good asphalt still floats a little.
        let bob = wave(time, 1.15) * h * 0.0014 + wave(time, 2.35, 1.4) * h * 0.0006
        let horizon = h * 0.606 + bob
        let vx = w * 0.548
        let vy = h * 0.598 + bob
        let sun = CGPoint(x: w * 0.662, y: h * 0.452 + bob * 0.5)
        let sunRadius = s * 0.062

        let amber = Color(red: 1.0, green: 0.70, blue: 0.38)
        let paleAmber = Color(red: 1.0, green: 0.86, blue: 0.62)
        let rose = Color(red: 0.86, green: 0.46, blue: 0.44)
        let deepRose = Color(red: 0.44, green: 0.26, blue: 0.34)
        let seaDeep = Color(red: 0.055, green: 0.115, blue: 0.175)
        let ink = Color(red: 0.045, green: 0.042, blue: 0.055)

        // Perspective helper: depth 0 is the horizon, 1 is the bottom edge.
        func ground(_ depth: CGFloat, _ bottomX: CGFloat) -> CGPoint {
            let d = CGFloat(pow(Double(max(depth, 0)), 1.85))
            return CGPoint(
                x: vx + (bottomX - vx) * d,
                y: vy + (h * 0.985 - vy) * d
            )
        }
        func groundDepth(_ depth: CGFloat) -> CGFloat {
            CGFloat(pow(Double(max(depth, 0)), 1.85))
        }

        // MARK: Sky

        context.fill(
            Path(CGRect(x: -w * 0.05, y: -h * 0.05, width: w * 1.10, height: h * 1.10)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.085, green: 0.110, blue: 0.285), location: 0.0),
                    .init(color: Color(red: 0.215, green: 0.185, blue: 0.395), location: 0.22),
                    .init(color: Color(red: 0.560, green: 0.320, blue: 0.415), location: 0.44),
                    .init(color: Color(red: 0.900, green: 0.510, blue: 0.355), location: 0.545),
                    .init(color: Color(red: 1.000, green: 0.700, blue: 0.430), location: 0.596),
                    .init(color: Color(red: 1.000, green: 0.800, blue: 0.560), location: 0.610)
                ]),
                startPoint: CGPoint(x: w * 0.5, y: -h * 0.05),
                endPoint: CGPoint(x: w * 0.5, y: horizon)
            )
        )

        // The sun: a soft bloom, a squashed disc, and a thin horizon flare.
        let pulse = 0.94 + 0.04 * Double(wave(time, 0.22)) + 0.02 * Double(wave(time, 0.61, 1.3))
        glow(&context, center: sun, radius: s * 0.86, color: Color(red: 1.0, green: 0.56, blue: 0.30), opacity: 0.30 * pulse)
        glow(&context, center: sun, radius: s * 0.34, color: Color(red: 1.0, green: 0.76, blue: 0.46), opacity: 0.42 * pulse)
        glow(&context, center: sun, radius: s * 0.13, color: Color(red: 1.0, green: 0.93, blue: 0.72), opacity: 0.55 * pulse)

        context.fill(
            Path(ellipseIn: CGRect(
                x: sun.x - sunRadius,
                y: sun.y - sunRadius * 0.93,
                width: sunRadius * 2,
                height: sunRadius * 1.86
            )),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.985, blue: 0.90),
                    Color(red: 1.0, green: 0.92, blue: 0.70),
                    Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.55)
                ]),
                center: CGPoint(x: sun.x - sunRadius * 0.18, y: sun.y - sunRadius * 0.22),
                startRadius: 0,
                endRadius: sunRadius * 1.15
            )
        )

        // Anamorphic streak, just enough to feel like glass.
        var streak = Path()
        streak.move(to: CGPoint(x: sun.x - w * 0.26, y: sun.y))
        streak.addLine(to: CGPoint(x: sun.x + w * 0.26, y: sun.y))
        context.stroke(
            streak,
            with: .linearGradient(
                Gradient(colors: [.clear, paleAmber.opacity(0.20 * pulse), .clear]),
                startPoint: CGPoint(x: sun.x - w * 0.26, y: sun.y),
                endPoint: CGPoint(x: sun.x + w * 0.26, y: sun.y)
            ),
            style: StrokeStyle(lineWidth: s * 0.014, lineCap: .round)
        )

        // High cirrus, drifting slowly and blurred by distance.
        let cirrus: [(phase: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, speed: Double, tint: Color)] = [
            (0.05, 0.135, 0.62, 0.030, 0.0018, rose),
            (0.38, 0.205, 0.46, 0.024, 0.0024, Color(red: 0.98, green: 0.62, blue: 0.52)),
            (0.66, 0.095, 0.52, 0.026, 0.0014, Color(red: 0.74, green: 0.52, blue: 0.62)),
            (0.82, 0.285, 0.38, 0.020, 0.0030, Color(red: 1.0, green: 0.72, blue: 0.52)),
            (0.22, 0.345, 0.30, 0.016, 0.0036, Color(red: 0.98, green: 0.66, blue: 0.56))
        ]
        for (index, cloud) in cirrus.enumerated() {
            let travel = (Double(cloud.phase) + time * cloud.speed).truncatingRemainder(dividingBy: 1.0)
            let cx = -w * 0.35 + w * 1.70 * CGFloat(travel)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: s * 0.010))
                drawCloud(
                    &layer,
                    center: CGPoint(x: cx, y: h * cloud.y),
                    width: w * cloud.width,
                    height: h * cloud.height,
                    seed: 3101 + index,
                    body: [cloud.tint.opacity(0.34), cloud.tint.opacity(0.12)],
                    highlight: paleAmber.opacity(0.30)
                )
            }
        }

        // Lower, backlit cumulus above the horizon.
        let cumulus: [(phase: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, speed: Double)] = [
            (0.10, 0.500, 0.34, 0.060, 0.0030),
            (0.55, 0.455, 0.24, 0.048, 0.0042),
            (0.80, 0.530, 0.40, 0.050, 0.0024)
        ]
        for (index, cloud) in cumulus.enumerated() {
            let travel = (Double(cloud.phase) + time * cloud.speed).truncatingRemainder(dividingBy: 1.0)
            let cx = -w * 0.30 + w * 1.60 * CGFloat(travel)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: s * 0.006))
                drawCloud(
                    &layer,
                    center: CGPoint(x: cx, y: h * cloud.y),
                    width: w * cloud.width,
                    height: h * cloud.height,
                    seed: 3111 + index,
                    body: [
                        Color(red: 0.98, green: 0.68, blue: 0.46).opacity(0.44),
                        Color(red: 0.62, green: 0.38, blue: 0.40).opacity(0.30)
                    ],
                    highlight: Color(red: 1.0, green: 0.88, blue: 0.66).opacity(0.42)
                )
            }
        }

        // Thin bands of cloud lying on the horizon.
        for index in 0..<3 {
            let y = horizon - h * (0.030 + 0.022 * CGFloat(index))
            let width = w * (0.44 + 0.18 * hash(index, 3121))
            let x = w * hash(index, 3123) - width * 0.5 + wave(time, 0.002 + 0.001 * Double(index), Double(index)) * w * 0.02
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: s * 0.008))
                layer.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: width, height: h * 0.014)),
                    with: .color(Color(red: 1.0, green: 0.80, blue: 0.60).opacity(0.20 - 0.04 * Double(index)))
                )
            }
        }

        // Gulls, gliding and occasionally flapping.
        for index in 0..<6 {
            let baseX = w * (0.16 + 0.68 * hash(index, 3131))
            let baseY = h * (0.20 + 0.24 * hash(index, 3133))
            let drift = wave(time, 0.028 + 0.012 * Double(index), Double(index)) * w * 0.030
            let x = baseX + drift
            let y = baseY + wave(time, 0.045, Double(index) + 1.7) * h * 0.010
            let span = s * (0.008 + 0.006 * hash(index, 3137))
            let flap = 0.55 + 0.45 * wave(time, 1.4 + 0.4 * Double(index), Double(index))
            var gull = Path()
            gull.move(to: CGPoint(x: x - span, y: y + span * 0.10))
            gull.addQuadCurve(
                to: CGPoint(x: x, y: y + span * 0.18 * flap),
                control: CGPoint(x: x - span * 0.45, y: y - span * 0.42 * flap)
            )
            gull.addQuadCurve(
                to: CGPoint(x: x + span, y: y + span * 0.10),
                control: CGPoint(x: x + span * 0.45, y: y - span * 0.42 * flap)
            )
            context.stroke(
                gull,
                with: .color(deepRose.opacity(0.42)),
                style: StrokeStyle(lineWidth: max(0.6, s * 0.0016), lineCap: .round)
            )
        }

        // MARK: Headlands and lighthouse

        // The far left headland, softened by distance.
        var farLeft = Path()
        farLeft.move(to: CGPoint(x: -w * 0.02, y: horizon + 1))
        farLeft.addLine(to: CGPoint(x: -w * 0.02, y: h * 0.572))
        farLeft.addQuadCurve(to: CGPoint(x: w * 0.13, y: h * 0.556), control: CGPoint(x: w * 0.05, y: h * 0.534))
        farLeft.addQuadCurve(to: CGPoint(x: w * 0.27, y: h * 0.588), control: CGPoint(x: w * 0.20, y: h * 0.552))
        farLeft.addQuadCurve(to: CGPoint(x: w * 0.37, y: horizon), control: CGPoint(x: w * 0.33, y: h * 0.572))
        farLeft.closeSubpath()
        context.fill(farLeft, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.50, green: 0.36, blue: 0.40).opacity(0.62),
                Color(red: 0.34, green: 0.24, blue: 0.30).opacity(0.72)
            ]),
            startPoint: CGPoint(x: 0, y: h * 0.54),
            endPoint: CGPoint(x: 0, y: horizon)
        ))

        // A second, nearer ridge with a few warm windows.
        var nearLeft = Path()
        nearLeft.move(to: CGPoint(x: -w * 0.02, y: horizon + 1))
        nearLeft.addLine(to: CGPoint(x: -w * 0.02, y: h * 0.585))
        nearLeft.addQuadCurve(to: CGPoint(x: w * 0.10, y: h * 0.575), control: CGPoint(x: w * 0.04, y: h * 0.556))
        nearLeft.addQuadCurve(to: CGPoint(x: w * 0.20, y: h * 0.600), control: CGPoint(x: w * 0.15, y: h * 0.572))
        nearLeft.addLine(to: CGPoint(x: w * 0.24, y: horizon))
        nearLeft.closeSubpath()
        context.fill(nearLeft, with: .color(Color(red: 0.235, green: 0.175, blue: 0.205).opacity(0.90)))
        for index in 0..<4 {
            let hx = w * (0.035 + 0.042 * CGFloat(index))
            let hy = h * (0.583 + 0.004 * CGFloat(index % 2))
            let flicker = 0.55 + 0.45 * abs(sin(time * (0.5 + 0.3 * Double(index)) + Double(index)))
            context.fill(
                Path(ellipseIn: CGRect(x: hx, y: hy, width: s * 0.0032, height: s * 0.0026)),
                with: .color(Color(red: 1.0, green: 0.78, blue: 0.46).opacity(0.35 + 0.40 * flicker))
            )
        }

        // The right headland, with a lighthouse.
        var rightLand = Path()
        rightLand.move(to: CGPoint(x: w * 1.02, y: horizon + 1))
        rightLand.addLine(to: CGPoint(x: w * 1.02, y: h * 0.552))
        rightLand.addQuadCurve(to: CGPoint(x: w * 0.905, y: h * 0.536), control: CGPoint(x: w * 0.965, y: h * 0.520))
        rightLand.addQuadCurve(to: CGPoint(x: w * 0.805, y: h * 0.578), control: CGPoint(x: w * 0.855, y: h * 0.548))
        rightLand.addQuadCurve(to: CGPoint(x: w * 0.745, y: horizon), control: CGPoint(x: w * 0.775, y: h * 0.566))
        rightLand.closeSubpath()
        context.fill(rightLand, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.44, green: 0.30, blue: 0.34).opacity(0.66),
                Color(red: 0.25, green: 0.17, blue: 0.22).opacity(0.88)
            ]),
            startPoint: CGPoint(x: w, y: h * 0.53),
            endPoint: CGPoint(x: w * 0.80, y: horizon)
        ))

        let lighthouse = CGPoint(x: w * 0.878, y: h * 0.527)
        let towerHeight = h * 0.030
        var tower = Path()
        tower.move(to: CGPoint(x: lighthouse.x - s * 0.004, y: lighthouse.y))
        tower.addLine(to: CGPoint(x: lighthouse.x - s * 0.0028, y: lighthouse.y - towerHeight))
        tower.addLine(to: CGPoint(x: lighthouse.x + s * 0.0028, y: lighthouse.y - towerHeight))
        tower.addLine(to: CGPoint(x: lighthouse.x + s * 0.004, y: lighthouse.y))
        tower.closeSubpath()
        context.fill(tower, with: .color(Color(red: 0.92, green: 0.86, blue: 0.78).opacity(0.78)))
        context.fill(
            Path(CGRect(x: lighthouse.x - s * 0.0042, y: lighthouse.y - towerHeight - s * 0.0022, width: s * 0.0084, height: s * 0.0030)),
            with: .color(Color(red: 0.30, green: 0.22, blue: 0.24).opacity(0.85))
        )
        let lampPhase = time.truncatingRemainder(dividingBy: 7.5) / 7.5
        let lampOn = lampPhase < 0.16 ? sin(lampPhase / 0.16 * .pi) : 0.0
        let lampPoint = CGPoint(x: lighthouse.x, y: lighthouse.y - towerHeight - s * 0.0012)
        glow(&context, center: lampPoint, radius: s * 0.045, color: Color(red: 1.0, green: 0.86, blue: 0.58), opacity: 0.16 + 0.40 * lampOn)
        context.fill(
            Path(ellipseIn: CGRect(x: lampPoint.x - s * 0.0018, y: lampPoint.y - s * 0.0018, width: s * 0.0036, height: s * 0.0036)),
            with: .color(Color(red: 1.0, green: 0.94, blue: 0.74).opacity(0.55 + 0.45 * lampOn))
        )
        if lampOn > 0.01 {
            var beam = Path()
            beam.move(to: lampPoint)
            beam.addLine(to: CGPoint(x: lampPoint.x - w * 0.16, y: lampPoint.y - h * 0.030))
            beam.addLine(to: CGPoint(x: lampPoint.x - w * 0.16, y: lampPoint.y + h * 0.012))
            beam.closeSubpath()
            context.fill(beam, with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.66).opacity(0.16 * lampOn), .clear]),
                startPoint: lampPoint,
                endPoint: CGPoint(x: lampPoint.x - w * 0.16, y: lampPoint.y)
            ))
        }

        // MARK: Sea

        context.fill(
            Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon + 2)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.99, green: 0.76, blue: 0.50), location: 0.0),
                    .init(color: Color(red: 0.76, green: 0.55, blue: 0.45), location: 0.10),
                    .init(color: Color(red: 0.38, green: 0.38, blue: 0.40), location: 0.30),
                    .init(color: Color(red: 0.16, green: 0.25, blue: 0.32), location: 0.58),
                    .init(color: seaDeep, location: 1.0)
                ]),
                startPoint: CGPoint(x: w * 0.5, y: horizon),
                endPoint: CGPoint(x: w * 0.5, y: h)
            )
        )

        // Warm haze along the waterline.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.012))
            layer.fill(
                Path(CGRect(x: 0, y: horizon - h * 0.012, width: w, height: h * 0.030)),
                with: .linearGradient(
                    Gradient(colors: [.clear, Color(red: 1.0, green: 0.82, blue: 0.58).opacity(0.36), .clear]),
                    startPoint: CGPoint(x: w * 0.5, y: horizon - h * 0.012),
                    endPoint: CGPoint(x: w * 0.5, y: horizon + h * 0.018)
                )
            )
        }

        // The sun's path across the water.
        for index in 0..<52 {
            let progress = CGFloat(index) / 52
            let y = horizon + (h * 0.86 - horizon) * progress
            let width = w * (0.008 + 0.085 * progress) * (0.35 + 0.65 * hash(index, 3141))
            let sway = CGFloat(sin(time * 0.55 + Double(index) * 0.9)) * w * 0.006 * progress
            let x = sun.x + sway
            var glint = Path()
            glint.move(to: CGPoint(x: x - width * 0.5, y: y))
            glint.addLine(to: CGPoint(x: x + width * 0.5, y: y))
            context.stroke(
                glint,
                with: .color(Color(red: 1.0, green: 0.90, blue: 0.68).opacity(0.06 + 0.22 * Double(hash(index, 3143)) * (1.0 - 0.35 * Double(progress)))),
                style: StrokeStyle(lineWidth: max(0.7, s * 0.0022 * (0.6 + progress)), lineCap: .round)
            )
        }

        // Long, slow swells.
        for index in 0..<34 {
            let depth = hash(index, 3147)
            let y = horizon + (h * 0.86 - horizon) * depth
            let length = w * (0.03 + 0.17 * hash(index, 3149)) * (0.4 + depth)
            let x = w * hash(index, 3151) + wave(time, 0.10 + 0.05 * Double(hash(index, 3153)), Double(index)) * w * 0.012
            var swell = Path()
            swell.move(to: CGPoint(x: x, y: y))
            swell.addQuadCurve(
                to: CGPoint(x: x + length, y: y),
                control: CGPoint(x: x + length * 0.5, y: y - h * (0.002 + 0.003 * depth))
            )
            context.stroke(
                swell,
                with: .color(Color(red: 0.86, green: 0.94, blue: 0.95).opacity(0.04 + 0.10 * Double(depth))),
                style: StrokeStyle(lineWidth: max(0.6, s * 0.0016 * (0.5 + depth)), lineCap: .round)
            )
        }

        // A sailboat, and a freighter far out.
        let boatBob = wave(time, 0.11, 0.4) * h * 0.0016
        let boat = CGPoint(x: w * 0.300 + wave(time, 0.004) * w * 0.004, y: horizon - h * 0.003 + boatBob)
        var hull = Path()
        hull.move(to: CGPoint(x: boat.x - s * 0.010, y: boat.y))
        hull.addLine(to: CGPoint(x: boat.x + s * 0.010, y: boat.y))
        hull.addLine(to: CGPoint(x: boat.x + s * 0.005, y: boat.y + s * 0.0045))
        hull.addLine(to: CGPoint(x: boat.x - s * 0.005, y: boat.y + s * 0.0045))
        hull.closeSubpath()
        context.fill(hull, with: .color(Color(red: 0.16, green: 0.13, blue: 0.16).opacity(0.72)))
        var sail = Path()
        sail.move(to: CGPoint(x: boat.x, y: boat.y - s * 0.030))
        sail.addLine(to: CGPoint(x: boat.x, y: boat.y - s * 0.001))
        sail.addLine(to: CGPoint(x: boat.x + s * 0.011, y: boat.y - s * 0.001))
        sail.closeSubpath()
        context.fill(sail, with: .color(Color(red: 1.0, green: 0.95, blue: 0.84).opacity(0.66)))

        let shipX = w * CGFloat(0.60 + 0.10 * (time * 0.0016).truncatingRemainder(dividingBy: 1.0))
        let shipY = horizon - h * 0.002
        context.fill(
            Path(CGRect(x: shipX, y: shipY - s * 0.0026, width: s * 0.024, height: s * 0.0026)),
            with: .color(Color(red: 0.20, green: 0.16, blue: 0.18).opacity(0.55))
        )
        context.fill(
            Path(CGRect(x: shipX + s * 0.004, y: shipY - s * 0.0058, width: s * 0.008, height: s * 0.0034)),
            with: .color(Color(red: 0.22, green: 0.18, blue: 0.20).opacity(0.50))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: shipX + s * 0.016, y: shipY - s * 0.0042, width: s * 0.0014, height: s * 0.0014)),
            with: .color(Color(red: 1.0, green: 0.84, blue: 0.54).opacity(0.65))
        )

        // MARK: Road and verge

        // The land either side of the road, kept low and dark.
        var verge = Path()
        verge.move(to: CGPoint(x: 0, y: h))
        verge.addLine(to: CGPoint(x: 0, y: h * 0.625))
        verge.addQuadCurve(to: CGPoint(x: vx - w * 0.010, y: vy), control: CGPoint(x: w * 0.26, y: h * 0.640))
        verge.addLine(to: CGPoint(x: w, y: vy))
        verge.addLine(to: CGPoint(x: w, y: h))
        verge.closeSubpath()
        context.fill(verge, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.34, green: 0.26, blue: 0.24),
                Color(red: 0.20, green: 0.16, blue: 0.16),
                Color(red: 0.09, green: 0.085, blue: 0.095)
            ]),
            startPoint: CGPoint(x: w * 0.5, y: h * 0.62),
            endPoint: CGPoint(x: w * 0.5, y: h)
        ))

        // The road itself.
        var road = Path()
        road.move(to: CGPoint(x: w * 0.055, y: h * 1.02))
        road.addLine(to: CGPoint(x: vx - w * 0.008, y: vy))
        road.addLine(to: CGPoint(x: vx + w * 0.008, y: vy))
        road.addLine(to: CGPoint(x: w * 0.945, y: h * 1.02))
        road.closeSubpath()
        context.fill(road, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.44, green: 0.35, blue: 0.32), location: 0.0),
                .init(color: Color(red: 0.25, green: 0.22, blue: 0.235), location: 0.18),
                .init(color: Color(red: 0.145, green: 0.135, blue: 0.150), location: 0.55),
                .init(color: Color(red: 0.085, green: 0.080, blue: 0.092), location: 1.0)
            ]),
            startPoint: CGPoint(x: w * 0.5, y: vy),
            endPoint: CGPoint(x: w * 0.5, y: h)
        ))

        // The sun's reflection on the asphalt.
        context.drawLayer { layer in
            layer.clip(to: road)
            layer.fill(
                Path(CGRect(x: vx - w * 0.30, y: vy - h * 0.20, width: w * 0.60, height: h * 0.60)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.72, blue: 0.44).opacity(0.30),
                        Color(red: 1.0, green: 0.60, blue: 0.34).opacity(0.10),
                        .clear
                    ]),
                    center: CGPoint(x: vx, y: vy + h * 0.01),
                    startRadius: 0,
                    endRadius: w * 0.30
                )
            )
            // A faint sheen down the middle of the lane.
            layer.fill(
                Path(CGRect(x: vx - w * 0.06, y: vy, width: w * 0.12, height: h * 0.40)),
                with: .linearGradient(
                    Gradient(colors: [paleAmber.opacity(0.10), .clear]),
                    startPoint: CGPoint(x: vx, y: vy),
                    endPoint: CGPoint(x: vx, y: vy + h * 0.40)
                )
            )
        }

        // Edge lines, tapered by perspective.
        func edgeLine(_ bottomX: CGFloat, widthAtBottom: CGFloat, opacity: Double) {
            let topLeft = CGPoint(x: vx - w * 0.0016, y: vy)
            let topRight = CGPoint(x: vx + w * 0.0016, y: vy)
            let bottomLeft = CGPoint(x: bottomX - widthAtBottom * 0.5, y: h * 1.02)
            let bottomRight = CGPoint(x: bottomX + widthAtBottom * 0.5, y: h * 1.02)
            var line = Path()
            line.move(to: topLeft)
            line.addLine(to: topRight)
            line.addLine(to: bottomRight)
            line.addLine(to: bottomLeft)
            line.closeSubpath()
            context.fill(line, with: .color(Color(red: 1.0, green: 0.90, blue: 0.74).opacity(opacity)))
        }
        edgeLine(w * 0.070, widthAtBottom: w * 0.010, opacity: 0.42)
        edgeLine(w * 0.930, widthAtBottom: w * 0.010, opacity: 0.36)

        // Centre dashes, moving toward the car.
        for index in 0..<26 {
            let t = CGFloat((Double(index) / 26.0 + time * 0.085).truncatingRemainder(dividingBy: 1.0))
            let depth = groundDepth(t)
            let y = vy + (h * 1.02 - vy) * depth
            let x = vx + (w * 0.500 - vx) * depth
            let dashWidth = w * (0.0010 + 0.0090 * depth)
            let dashHeight = h * (0.0030 + 0.050 * depth)
            var dash = Path()
            dash.move(to: CGPoint(x: x - dashWidth * 0.5, y: y))
            dash.addLine(to: CGPoint(x: x + dashWidth * 0.5, y: y))
            dash.addLine(to: CGPoint(x: x + dashWidth * 0.62, y: y + dashHeight))
            dash.addLine(to: CGPoint(x: x - dashWidth * 0.62, y: y + dashHeight))
            dash.closeSubpath()
            context.fill(
                dash,
                with: .color(Color(red: 1.0, green: 0.92, blue: 0.70).opacity(0.10 + 0.42 * Double(depth)))
            )
        }

        // Reflector posts on the shoulder, each one catching the light.
        for index in 0..<10 {
            let t = CGFloat((Double(index) / 10.0 + time * 0.082).truncatingRemainder(dividingBy: 1.0))
            let depth = groundDepth(t)
            let y = vy + (h * 1.02 - vy) * depth
            let x = vx + (w * 0.905 - vx) * depth
            let postHeight = h * (0.004 + 0.055 * depth)
            let postWidth = w * (0.0008 + 0.0040 * depth)
            var post = Path()
            post.move(to: CGPoint(x: x - postWidth * 0.5, y: y))
            post.addLine(to: CGPoint(x: x - postWidth * 0.34, y: y - postHeight))
            post.addLine(to: CGPoint(x: x + postWidth * 0.34, y: y - postHeight))
            post.addLine(to: CGPoint(x: x + postWidth * 0.5, y: y))
            post.closeSubpath()
            context.fill(post, with: .color(Color(red: 0.86, green: 0.82, blue: 0.74).opacity(0.30 + 0.45 * Double(depth))))
            if depth > 0.05 {
                glow(
                    &context,
                    center: CGPoint(x: x, y: y - postHeight * 0.72),
                    radius: postWidth * 2.2,
                    color: Color(red: 1.0, green: 0.72, blue: 0.34),
                    opacity: 0.22 + 0.50 * Double(depth)
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: x - postWidth * 0.34,
                        y: y - postHeight * 0.78,
                        width: postWidth * 0.68,
                        height: postHeight * 0.12
                    )),
                    with: .color(Color(red: 1.0, green: 0.76, blue: 0.36).opacity(0.60 + 0.35 * Double(depth)))
                )
            }
        }

        // Guardrail on the sea side: a metal band with posts and a highlight.
        let railNear = ground(1.0, w * 0.930)
        let railFar = ground(0.0, w * 0.930)
        var railBand = Path()
        railBand.move(to: CGPoint(x: railFar.x, y: railFar.y - h * 0.004))
        railBand.addLine(to: CGPoint(x: railNear.x, y: railNear.y - h * 0.060))
        railBand.addLine(to: CGPoint(x: railNear.x, y: railNear.y - h * 0.036))
        railBand.addLine(to: CGPoint(x: railFar.x, y: railFar.y - h * 0.001))
        railBand.closeSubpath()
        context.fill(railBand, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.92, green: 0.88, blue: 0.80).opacity(0.42),
                Color(red: 0.62, green: 0.58, blue: 0.56).opacity(0.30)
            ]),
            startPoint: CGPoint(x: railFar.x, y: railFar.y),
            endPoint: CGPoint(x: railNear.x, y: railNear.y)
        ))
        for index in 0..<12 {
            let t = CGFloat((Double(index) / 12.0 + time * 0.082).truncatingRemainder(dividingBy: 1.0))
            let depth = groundDepth(t)
            let y = vy + (h * 1.02 - vy) * depth
            let x = vx + (w * 0.930 - vx) * depth
            let postHeight = h * (0.004 + 0.062 * depth)
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y - postHeight))
                },
                with: .color(Color(red: 0.10, green: 0.105, blue: 0.125).opacity(0.80)),
                style: StrokeStyle(lineWidth: max(0.6, w * 0.0012 + w * 0.0040 * depth), lineCap: .round)
            )
            if depth > 0.15 {
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x - w * 0.0008, y: y - postHeight))
                        path.addLine(to: CGPoint(x: x - w * 0.0008, y: y - postHeight * 0.55))
                    },
                    with: .color(paleAmber.opacity(0.18 * Double(depth))),
                    style: StrokeStyle(lineWidth: max(0.5, w * 0.0008), lineCap: .round)
                )
            }
        }

        // Cypress trees on the land side, each at its own depth.
        for index in 0..<13 {
            let t = CGFloat((Double(index) / 13.0 + time * 0.070).truncatingRemainder(dividingBy: 1.0))
            let depth = groundDepth(t)
            let base = ground(t, w * 0.115)
            let treeHeight = h * (0.012 + 0.300 * depth)
            let treeWidth = treeHeight * (0.10 + 0.030 * hash(index, 3161))
            let sway = wave(time, 0.45, Double(index)) * treeWidth * 0.020
            drawCypress(
                &context,
                x: base.x + sway,
                baseY: base.y,
                height: treeHeight,
                width: treeWidth,
                depth: depth,
                seed: 3163 + index,
                ink: ink
            )
        }

        // One large cypress close to the camera, framing the left edge.
        drawCypress(
            &context,
            x: w * 0.028 + wave(time, 0.30, 1.2) * w * 0.002,
            baseY: h * 1.02,
            height: h * 0.52,
            width: w * 0.050,
            depth: 1.0,
            seed: 3191,
            ink: ink
        )

        // Grass along the verge, lit from behind.
        for index in 0..<22 {
            let depth = 0.55 + 0.45 * hash(index, 3171)
            let base = ground(depth, w * (0.085 + 0.060 * hash(index, 3173)))
            let bladeHeight = h * (0.008 + 0.030 * depth) * (0.6 + 0.8 * hash(index, 3175))
            let sway = wave(time, 0.7 + 0.3 * Double(hash(index, 3177)), Double(index)) * w * 0.003
            var blade = Path()
            blade.move(to: CGPoint(x: base.x, y: base.y))
            blade.addQuadCurve(
                to: CGPoint(x: base.x + sway, y: base.y - bladeHeight),
                control: CGPoint(x: base.x + sway * 0.4, y: base.y - bladeHeight * 0.55)
            )
            context.stroke(
                blade,
                with: .color(Color(red: 0.58, green: 0.46, blue: 0.28).opacity(0.22 + 0.18 * Double(depth))),
                style: StrokeStyle(lineWidth: max(0.5, s * 0.0016), lineCap: .round)
            )
        }

        // MARK: Traffic

        // The car ahead, holding its distance.
        let aheadDepth: CGFloat = 0.30 + 0.012 * wave(time, 0.11)
        let ahead = ground(aheadDepth, w * 0.610)
        let aheadWidth = w * (0.014 + 0.075 * groundDepth(aheadDepth))
        let aheadHeight = aheadWidth * 0.62
        let brakeCycle = time.truncatingRemainder(dividingBy: 5.8)
        let braking = brakeCycle > 4.6 && brakeCycle < 5.25
        let brakeGlow = braking ? 0.95 : 0.55
        drawCarAhead(
            &context,
            center: CGPoint(x: ahead.x, y: ahead.y),
            width: aheadWidth,
            height: aheadHeight,
            brake: brakeGlow,
            seed: 3201
        )

        // A car passing the other way, every ten seconds.
        let passCycle = time.truncatingRemainder(dividingBy: 10.0) / 10.0
        if passCycle > 0.10 && passCycle < 0.72 {
            let progress = CGFloat((passCycle - 0.10) / 0.62)
            let depth = 0.04 + 0.92 * progress * progress
            let x = vx + (w * 0.465 - vx) * groundDepth(depth)
            let y = vy + (h * 1.02 - vy) * groundDepth(depth)
            let carWidth = w * (0.012 + 0.160 * groundDepth(depth))
            let carHeight = carWidth * 0.46
            let intensity = 0.35 + 0.65 * progress
            drawOncomingCar(
                &context,
                center: CGPoint(x: x, y: y - carHeight * 0.30),
                width: carWidth,
                height: carHeight,
                intensity: intensity,
                time: time
            )
            if progress > 0.55 {
                glow(
                    &context,
                    center: CGPoint(x: x, y: y - carHeight * 0.45),
                    radius: carWidth * 1.5,
                    color: Color(red: 1.0, green: 0.90, blue: 0.70),
                    opacity: 0.16 * Double(progress)
                )
            }
        }

        // Warm dust and pollen in the last light.
        for index in 0..<30 {
            let baseX = w * hash(index, 3211)
            let baseY = h * (0.18 + 0.60 * hash(index, 3213))
            let x = baseX + wave(time, 0.08 + 0.04 * Double(hash(index, 3217)), Double(index)) * w * 0.016
            let y = baseY + wave(time, 0.06 + 0.03 * Double(hash(index, 3219)), Double(index) + 1) * h * 0.010
            let radius = s * (0.0008 + 0.0016 * hash(index, 3221))
            let twinkle = 0.35 + 0.65 * abs(sin(time * (0.35 + 0.5 * Double(hash(index, 3223))) + Double(index)))
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 1.0, green: 0.82, blue: 0.54).opacity(0.05 + 0.20 * twinkle))
            )
        }

        // MARK: Windshield

        // The tinted band at the top of the glass.
        context.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h * 0.095)),
            with: .linearGradient(
                Gradient(colors: [Color.black.opacity(0.34), .clear]),
                startPoint: CGPoint(x: w * 0.5, y: 0),
                endPoint: CGPoint(x: w * 0.5, y: h * 0.095)
            )
        )

        // A broad, faint reflection across the glass.
        context.drawLayer { layer in
            var reflection = Path()
            reflection.move(to: CGPoint(x: w * 0.10, y: -h * 0.05))
            reflection.addLine(to: CGPoint(x: w * 0.36, y: -h * 0.05))
            reflection.addLine(to: CGPoint(x: w * 0.62, y: h * 0.72))
            reflection.addLine(to: CGPoint(x: w * 0.46, y: h * 0.72))
            reflection.closeSubpath()
            layer.addFilter(.blur(radius: s * 0.020))
            layer.fill(reflection, with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.030), Color.white.opacity(0.006), .clear]),
                startPoint: CGPoint(x: w * 0.24, y: 0),
                endPoint: CGPoint(x: w * 0.54, y: h * 0.70)
            ))
        }

        // Dust on the glass.
        for index in 0..<18 {
            let x = w * hash(index, 3231)
            let y = h * (0.02 + 0.70 * hash(index, 3233))
            let radius = s * (0.0006 + 0.0012 * hash(index, 3237))
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(Color.white.opacity(0.02 + 0.05 * Double(hash(index, 3239))))
            )
        }

        // The A-pillars and their rubber seals.
        func pillar(leftSide: Bool) {
            let outer = leftSide ? CGFloat(0) : w
            let inner = leftSide ? w * 0.082 : w * 0.918
            var shape = Path()
            shape.move(to: CGPoint(x: outer, y: -h * 0.02))
            shape.addLine(to: CGPoint(x: inner, y: -h * 0.02))
            shape.addQuadCurve(
                to: CGPoint(x: outer, y: h * 0.615),
                control: CGPoint(x: leftSide ? w * 0.050 : w * 0.950, y: h * 0.285)
            )
            shape.closeSubpath()
            context.fill(shape, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.075, green: 0.070, blue: 0.085),
                    Color(red: 0.030, green: 0.030, blue: 0.040),
                    Color(red: 0.015, green: 0.015, blue: 0.022)
                ]),
                startPoint: CGPoint(x: outer, y: 0),
                endPoint: CGPoint(x: inner, y: h * 0.60)
            ))

            // The warm inner edge, catching the sunset.
            var seal = Path()
            seal.move(to: CGPoint(x: inner, y: -h * 0.02))
            seal.addQuadCurve(
                to: CGPoint(x: outer, y: h * 0.615),
                control: CGPoint(x: leftSide ? w * 0.050 : w * 0.950, y: h * 0.285)
            )
            context.stroke(
                seal,
                with: .color(Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.16)),
                style: StrokeStyle(lineWidth: max(1.0, s * 0.0030), lineCap: .round)
            )
            var innerLine = Path()
            innerLine.move(to: CGPoint(x: inner + (leftSide ? -w * 0.004 : w * 0.004), y: -h * 0.02))
            innerLine.addQuadCurve(
                to: CGPoint(x: outer + (leftSide ? w * 0.012 : -w * 0.012), y: h * 0.615),
                control: CGPoint(x: leftSide ? w * 0.044 : w * 0.956, y: h * 0.285)
            )
            context.stroke(
                innerLine,
                with: .color(Color.black.opacity(0.55)),
                style: StrokeStyle(lineWidth: max(0.8, s * 0.0018), lineCap: .round)
            )
        }
        pillar(leftSide: true)
        pillar(leftSide: false)

        // MARK: Mirror and charm

        let mirror = CGRect(x: w * 0.446, y: h * 0.030, width: w * 0.150, height: h * 0.052)
        // Stem.
        var stem = Path()
        stem.move(to: CGPoint(x: mirror.midX - s * 0.0035, y: -h * 0.01))
        stem.addLine(to: CGPoint(x: mirror.midX - s * 0.0028, y: mirror.minY + h * 0.006))
        stem.addLine(to: CGPoint(x: mirror.midX + s * 0.0028, y: mirror.minY + h * 0.006))
        stem.addLine(to: CGPoint(x: mirror.midX + s * 0.0035, y: -h * 0.01))
        stem.closeSubpath()
        context.fill(stem, with: .color(Color(red: 0.045, green: 0.042, blue: 0.055).opacity(0.95)))

        // Housing.
        context.fill(
            Path(roundedRect: mirror, cornerRadius: s * 0.014),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.095, green: 0.090, blue: 0.105),
                    Color(red: 0.035, green: 0.033, blue: 0.045)
                ]),
                startPoint: CGPoint(x: mirror.midX, y: mirror.minY),
                endPoint: CGPoint(x: mirror.midX, y: mirror.maxY)
            )
        )
        let glass = mirror.insetBy(dx: w * 0.0065, dy: h * 0.0065)
        context.drawLayer { layer in
            layer.clip(to: Path(roundedRect: glass, cornerRadius: s * 0.009))
            // The road behind, receding.
            layer.fill(
                Path(glass),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.96, green: 0.66, blue: 0.40), location: 0.0),
                        .init(color: Color(red: 0.66, green: 0.38, blue: 0.38), location: 0.42),
                        .init(color: Color(red: 0.22, green: 0.20, blue: 0.26), location: 0.62),
                        .init(color: Color(red: 0.10, green: 0.10, blue: 0.13), location: 1.0)
                    ]),
                    startPoint: CGPoint(x: glass.midX, y: glass.minY),
                    endPoint: CGPoint(x: glass.midX, y: glass.maxY)
                )
            )
            // A sun, low in the mirror.
            let mirrorSun = CGPoint(x: glass.minX + glass.width * 0.72, y: glass.minY + glass.height * 0.32)
            layer.fill(
                Path(ellipseIn: CGRect(x: mirrorSun.x - s * 0.004, y: mirrorSun.y - s * 0.004, width: s * 0.008, height: s * 0.008)),
                with: .color(Color(red: 1.0, green: 0.94, blue: 0.76).opacity(0.85))
            )
            // Road and horizon.
            let mirrorHorizon = glass.minY + glass.height * 0.58
            var road = Path()
            road.move(to: CGPoint(x: glass.minX, y: glass.maxY))
            road.addLine(to: CGPoint(x: glass.midX - glass.width * 0.03, y: mirrorHorizon))
            road.addLine(to: CGPoint(x: glass.midX + glass.width * 0.03, y: mirrorHorizon))
            road.addLine(to: CGPoint(x: glass.maxX, y: glass.maxY))
            road.closeSubpath()
            layer.fill(road, with: .color(Color(red: 0.10, green: 0.095, blue: 0.12).opacity(0.92)))

            // A car following, its headlights growing.
            let followCycle = time.truncatingRemainder(dividingBy: 13.0) / 13.0
            if followCycle > 0.30 {
                let p = CGFloat((followCycle - 0.30) / 0.70)
                let cx = glass.midX + glass.width * 0.10 * (1 - p)
                let cy = mirrorHorizon + glass.height * (0.08 + 0.30 * p)
                let cw = glass.width * (0.05 + 0.11 * p)
                let ch = cw * 0.52
                layer.fill(
                    Path(roundedRect: CGRect(x: cx - cw * 0.5, y: cy - ch, width: cw, height: ch), cornerRadius: cw * 0.16),
                    with: .color(Color(red: 0.09, green: 0.085, blue: 0.10).opacity(0.94))
                )
                for side in [-1.0, 1.0] {
                    let lx = cx + CGFloat(side) * cw * 0.30
                    layer.fill(
                        Path(ellipseIn: CGRect(x: lx - cw * 0.075, y: cy - ch * 0.48, width: cw * 0.15, height: ch * 0.16)),
                        with: .color(Color(red: 1.0, green: 0.94, blue: 0.78).opacity(0.85))
                    )
                }
            }
            // Glass sheen.
            layer.fill(
                Path(glass),
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.10), .clear, Color.white.opacity(0.04)]),
                    startPoint: CGPoint(x: glass.minX, y: glass.minY),
                    endPoint: CGPoint(x: glass.maxX, y: glass.maxY)
                )
            )
        }
        context.stroke(
            Path(roundedRect: mirror, cornerRadius: s * 0.014),
            with: .color(Color(red: 1.0, green: 0.80, blue: 0.56).opacity(0.18)),
            lineWidth: 1
        )
        context.stroke(
            Path(roundedRect: glass, cornerRadius: s * 0.009),
            with: .color(Color.black.opacity(0.55)),
            lineWidth: 1
        )

        // The crystal charm, swinging with the car's motion.
        let anchor = CGPoint(x: mirror.midX + w * 0.004, y: mirror.maxY)
        let sway = wave(time, 0.85) * w * 0.012 + wave(time, 1.9, 1.1) * w * 0.004
        let charm = CGPoint(x: anchor.x + sway, y: anchor.y + h * 0.055)
        var thread = Path()
        thread.move(to: anchor)
        thread.addQuadCurve(
            to: charm,
            control: CGPoint(x: anchor.x + sway * 0.35, y: anchor.y + h * 0.028)
        )
        context.stroke(
            thread,
            with: .color(Color(red: 1.0, green: 0.90, blue: 0.72).opacity(0.30)),
            style: StrokeStyle(lineWidth: max(0.5, s * 0.0010), lineCap: .round)
        )
        let crystalSize = s * 0.0075
        var crystal = Path()
        crystal.move(to: CGPoint(x: charm.x, y: charm.y - crystalSize * 1.30))
        crystal.addLine(to: CGPoint(x: charm.x + crystalSize * 0.72, y: charm.y - crystalSize * 0.25))
        crystal.addLine(to: CGPoint(x: charm.x, y: charm.y + crystalSize * 1.30))
        crystal.addLine(to: CGPoint(x: charm.x - crystalSize * 0.72, y: charm.y - crystalSize * 0.25))
        crystal.closeSubpath()
        glow(&context, center: charm, radius: crystalSize * 3.2, color: Color(red: 1.0, green: 0.80, blue: 0.46), opacity: 0.20)
        context.fill(crystal, with: .linearGradient(
            Gradient(colors: [
                Color(red: 1.0, green: 0.92, blue: 0.70).opacity(0.85),
                Color(red: 0.98, green: 0.62, blue: 0.38).opacity(0.70)
            ]),
            startPoint: CGPoint(x: charm.x - crystalSize, y: charm.y - crystalSize),
            endPoint: CGPoint(x: charm.x + crystalSize, y: charm.y + crystalSize)
        ))
        context.stroke(
            crystal,
            with: .color(Color(red: 1.0, green: 0.96, blue: 0.84).opacity(0.55)),
            lineWidth: 0.8
        )
        // A tiny prism of colour at the edge.
        let prism = CGPoint(x: charm.x + crystalSize * 0.42, y: charm.y - crystalSize * 0.35)
        context.fill(
            Path(ellipseIn: CGRect(x: prism.x - s * 0.0012, y: prism.y - s * 0.0012, width: s * 0.0024, height: s * 0.0024)),
            with: .color(Color(red: 0.68, green: 0.86, blue: 1.0).opacity(0.45))
        )

        // MARK: Dashboard

        var dashboard = Path()
        dashboard.move(to: CGPoint(x: -w * 0.02, y: h * 1.02))
        dashboard.addLine(to: CGPoint(x: -w * 0.02, y: h * 0.912))
        dashboard.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.858),
            control1: CGPoint(x: w * 0.16, y: h * 0.900),
            control2: CGPoint(x: w * 0.33, y: h * 0.862)
        )
        dashboard.addCurve(
            to: CGPoint(x: w * 1.02, y: h * 0.912),
            control1: CGPoint(x: w * 0.68, y: h * 0.862),
            control2: CGPoint(x: w * 0.84, y: h * 0.902)
        )
        dashboard.addLine(to: CGPoint(x: w * 1.02, y: h * 1.02))
        dashboard.closeSubpath()
        context.fill(dashboard, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.175, green: 0.155, blue: 0.170), location: 0.0),
                .init(color: Color(red: 0.095, green: 0.085, blue: 0.100), location: 0.35),
                .init(color: Color(red: 0.035, green: 0.032, blue: 0.042), location: 1.0)
            ]),
            startPoint: CGPoint(x: w * 0.5, y: h * 0.855),
            endPoint: CGPoint(x: w * 0.5, y: h)
        ))

        // The rim of the dash, catching the sunset.
        var dashRim = Path()
        dashRim.move(to: CGPoint(x: -w * 0.02, y: h * 0.912))
        dashRim.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.858),
            control1: CGPoint(x: w * 0.16, y: h * 0.900),
            control2: CGPoint(x: w * 0.33, y: h * 0.862)
        )
        dashRim.addCurve(
            to: CGPoint(x: w * 1.02, y: h * 0.912),
            control1: CGPoint(x: w * 0.68, y: h * 0.862),
            control2: CGPoint(x: w * 0.84, y: h * 0.902)
        )
        context.stroke(
            dashRim,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.70, blue: 0.40).opacity(0.10),
                    Color(red: 1.0, green: 0.78, blue: 0.48).opacity(0.55),
                    Color(red: 1.0, green: 0.70, blue: 0.40).opacity(0.10)
                ]),
                startPoint: CGPoint(x: 0, y: h * 0.89),
                endPoint: CGPoint(x: w, y: h * 0.89)
            ),
            style: StrokeStyle(lineWidth: max(1.0, s * 0.0022), lineCap: .round)
        )

        // A soft reflection of the sky on the dash top.
        context.drawLayer { layer in
            layer.clip(to: dashboard)
            layer.fill(
                Path(CGRect(x: w * 0.28, y: h * 0.845, width: w * 0.50, height: h * 0.090)),
                with: .linearGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.66, blue: 0.38).opacity(0.16), .clear]),
                    startPoint: CGPoint(x: w * 0.5, y: h * 0.845),
                    endPoint: CGPoint(x: w * 0.5, y: h * 0.935)
                )
            )
        }

        // Stitching along the dash edge.
        for index in 0..<30 {
            let t = CGFloat(index) / 29
            let x = -w * 0.01 + w * 1.02 * t
            let y = h * (0.905 - 0.044 * (1.0 - abs(t - 0.5) * 2.0) * 0.92)
            var stitch = Path()
            stitch.move(to: CGPoint(x: x, y: y + h * 0.002))
            stitch.addLine(to: CGPoint(x: x + w * 0.006, y: y + h * 0.001))
            context.stroke(
                stitch,
                with: .color(Color(red: 0.86, green: 0.62, blue: 0.40).opacity(0.16)),
                style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
            )
        }

        // Air vents either side of the centre stack.
        func vent(_ rect: CGRect, slats: Int) {
            context.fill(
                Path(roundedRect: rect, cornerRadius: rect.height * 0.28),
                with: .color(Color(red: 0.045, green: 0.042, blue: 0.052).opacity(0.95))
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: rect.height * 0.28),
                with: .color(Color(red: 0.62, green: 0.58, blue: 0.56).opacity(0.20)),
                lineWidth: 0.8
            )
            for index in 0..<slats {
                let y = rect.minY + rect.height * (0.22 + 0.56 * CGFloat(index) / CGFloat(max(slats - 1, 1)))
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: y))
                        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: y))
                    },
                    with: .color(Color(red: 0.34, green: 0.32, blue: 0.34).opacity(0.55)),
                    style: StrokeStyle(lineWidth: max(0.6, rect.height * 0.045), lineCap: .round)
                )
            }
        }
        vent(CGRect(x: w * 0.372, y: h * 0.878, width: w * 0.074, height: h * 0.024), slats: 4)
        vent(CGRect(x: w * 0.700, y: h * 0.878, width: w * 0.074, height: h * 0.024), slats: 4)

        // MARK: Instrument cluster

        let cluster = CGRect(x: w * 0.098, y: h * 0.888, width: w * 0.225, height: h * 0.082)
        context.fill(
            Path(roundedRect: cluster, cornerRadius: h * 0.014),
            with: .color(Color(red: 0.022, green: 0.022, blue: 0.030).opacity(0.96))
        )
        context.stroke(
            Path(roundedRect: cluster, cornerRadius: h * 0.014),
            with: .color(Color(red: 0.54, green: 0.50, blue: 0.48).opacity(0.22)),
            lineWidth: 0.9
        )
        context.drawLayer { layer in
            layer.clip(to: Path(roundedRect: cluster, cornerRadius: h * 0.014))
            layer.fill(
                Path(cluster),
                with: .linearGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.68, blue: 0.36).opacity(0.10), .clear]),
                    startPoint: CGPoint(x: cluster.midX, y: cluster.minY),
                    endPoint: CGPoint(x: cluster.midX, y: cluster.maxY)
                )
            )
        }
        let gaugeRadius = cluster.height * 0.36
        for index in 0..<2 {
            let center = CGPoint(
                x: cluster.minX + cluster.width * (0.28 + 0.34 * CGFloat(index)),
                y: cluster.midY + cluster.height * 0.04
            )
            context.stroke(
                Path { path in
                    path.addArc(center: center, radius: gaugeRadius, startAngle: .degrees(150), endAngle: .degrees(390), clockwise: false)
                },
                with: .color(Color(red: 1.0, green: 0.72, blue: 0.44).opacity(0.30)),
                style: StrokeStyle(lineWidth: max(0.8, s * 0.0016), lineCap: .round)
            )
            for tick in 0..<11 {
                let angle = Double.pi * (0.833 + 1.333 * Double(tick) / 10.0)
                let inner = gaugeRadius * 0.82
                let outer = gaugeRadius * (tick % 5 == 0 ? 1.02 : 0.94)
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner))
                        path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * outer, y: center.y + CGFloat(sin(angle)) * outer))
                    },
                    with: .color(Color(red: 1.0, green: 0.80, blue: 0.54).opacity(tick % 5 == 0 ? 0.45 : 0.22)),
                    style: StrokeStyle(lineWidth: tick % 5 == 0 ? 1.1 : 0.7, lineCap: .round)
                )
            }
            let value = index == 0
                ? 0.56 + 0.030 * wave(time, 0.23) + 0.010 * wave(time, 0.9, 0.7)
                : 0.42 + 0.050 * wave(time, 0.17, 1.2) + 0.014 * wave(time, 0.7, 0.4)
            let needleAngle = Double.pi * (0.833 + 1.333 * Double(value))
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: center.x - CGFloat(cos(needleAngle)) * gaugeRadius * 0.10, y: center.y - CGFloat(sin(needleAngle)) * gaugeRadius * 0.10))
                    path.addLine(to: CGPoint(x: center.x + CGFloat(cos(needleAngle)) * gaugeRadius * 0.86, y: center.y + CGFloat(sin(needleAngle)) * gaugeRadius * 0.86))
                },
                with: .color(Color(red: 1.0, green: 0.84, blue: 0.58).opacity(0.72)),
                style: StrokeStyle(lineWidth: max(1.0, s * 0.0020), lineCap: .round)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - s * 0.0032, y: center.y - s * 0.0032, width: s * 0.0064, height: s * 0.0064)),
                with: .color(Color(red: 0.30, green: 0.27, blue: 0.28).opacity(0.95))
            )
        }
        // A small digital readout between the gauges.
        let readout = CGRect(x: cluster.midX - cluster.width * 0.055, y: cluster.minY + cluster.height * 0.10, width: cluster.width * 0.11, height: cluster.height * 0.30)
        context.fill(Path(roundedRect: readout, cornerRadius: readout.height * 0.22), with: .color(Color(red: 0.06, green: 0.045, blue: 0.040).opacity(0.95)))
        context.draw(
            Text("58")
                .font(.system(size: max(5, cluster.height * 0.22), weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.46).opacity(0.85)),
            at: CGPoint(x: readout.midX, y: readout.midY - readout.height * 0.02)
        )
        context.draw(
            Text("MPH")
                .font(.system(size: max(3.5, cluster.height * 0.10), weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.46).opacity(0.40)),
            at: CGPoint(x: readout.midX, y: readout.maxY - readout.height * 0.16)
        )

        // MARK: Steering wheel

        let wheelCenter = CGPoint(x: w * 0.238, y: h * 1.120)
        let wheelRadius = s * 0.205
        let wheelAngle = Double(wave(time, 0.45)) * 0.006 + Double(wave(time, 1.30, 0.9)) * 0.003
        context.drawLayer { layer in
            layer.translateBy(x: wheelCenter.x, y: wheelCenter.y)
            layer.rotate(by: .radians(wheelAngle))
            layer.translateBy(x: -wheelCenter.x, y: -wheelCenter.y)

            var rim = Path()
            rim.addArc(center: wheelCenter, radius: wheelRadius, startAngle: .degrees(194), endAngle: .degrees(346), clockwise: false)
            layer.stroke(
                rim,
                with: .color(Color(red: 0.105, green: 0.098, blue: 0.112).opacity(0.99)),
                style: StrokeStyle(lineWidth: max(6, s * 0.036), lineCap: .round)
            )
            var rimLight = Path()
            rimLight.addArc(center: wheelCenter, radius: wheelRadius * 0.985, startAngle: .degrees(198), endAngle: .degrees(250), clockwise: false)
            layer.stroke(
                rimLight,
                with: .color(Color(red: 1.0, green: 0.74, blue: 0.44).opacity(0.30)),
                style: StrokeStyle(lineWidth: max(1.0, s * 0.0030), lineCap: .round)
            )
            var rimInner = Path()
            rimInner.addArc(center: wheelCenter, radius: wheelRadius * 0.86, startAngle: .degrees(196), endAngle: .degrees(344), clockwise: false)
            layer.stroke(
                rimInner,
                with: .color(Color.black.opacity(0.50)),
                style: StrokeStyle(lineWidth: max(0.8, s * 0.0020), lineCap: .round)
            )
            // Spokes disappearing under the dash.
            for angle in [Double(214), Double(326)] {
                let a = angle * .pi / 180
                layer.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: wheelCenter.x + CGFloat(cos(a)) * wheelRadius * 0.90, y: wheelCenter.y + CGFloat(sin(a)) * wheelRadius * 0.90))
                        path.addLine(to: CGPoint(x: wheelCenter.x + CGFloat(cos(a)) * wheelRadius * 0.30, y: wheelCenter.y + CGFloat(sin(a)) * wheelRadius * 0.30))
                    },
                    with: .color(Color(red: 0.085, green: 0.080, blue: 0.095).opacity(0.98)),
                    style: StrokeStyle(lineWidth: max(3, s * 0.016), lineCap: .round)
                )
            }
        }

        // MARK: Stereo

        let stereo = CGRect(x: w * 0.462, y: h * 0.906, width: w * 0.190, height: h * 0.056)
        context.fill(
            Path(roundedRect: stereo, cornerRadius: h * 0.012),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.085, green: 0.080, blue: 0.095),
                    Color(red: 0.030, green: 0.028, blue: 0.038)
                ]),
                startPoint: CGPoint(x: stereo.midX, y: stereo.minY),
                endPoint: CGPoint(x: stereo.midX, y: stereo.maxY)
            )
        )
        context.stroke(
            Path(roundedRect: stereo, cornerRadius: h * 0.012),
            with: .color(Color(red: 0.72, green: 0.66, blue: 0.60).opacity(0.22)),
            lineWidth: 0.9
        )
        // A warm chrome line along the top.
        context.stroke(
            Path { path in
                path.move(to: CGPoint(x: stereo.minX + stereo.width * 0.03, y: stereo.minY + 1))
                path.addLine(to: CGPoint(x: stereo.maxX - stereo.width * 0.03, y: stereo.minY + 1))
            },
            with: .color(Color(red: 1.0, green: 0.82, blue: 0.56).opacity(0.22)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round)
        )

        let display = stereo.insetBy(dx: w * 0.020, dy: h * 0.010)
        context.fill(
            Path(roundedRect: display, cornerRadius: h * 0.005),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.60, blue: 0.28).opacity(0.26),
                    Color(red: 0.72, green: 0.26, blue: 0.20).opacity(0.20)
                ]),
                startPoint: CGPoint(x: display.minX, y: display.midY),
                endPoint: CGPoint(x: display.maxX, y: display.midY)
            )
        )
        context.stroke(
            Path(roundedRect: display, cornerRadius: h * 0.005),
            with: .color(Color(red: 1.0, green: 0.76, blue: 0.44).opacity(0.20)),
            lineWidth: 0.8
        )

        // Track information.
        context.draw(
            Text("GOLDEN COAST")
                .font(.system(size: max(4, display.height * 0.26), weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.62).opacity(0.88)),
            at: CGPoint(x: display.minX + display.width * 0.30, y: display.minY + display.height * 0.30),
            anchor: .leading
        )
        context.draw(
            Text("ATMORA")
                .font(.system(size: max(3, display.height * 0.18), weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.48).opacity(0.55)),
            at: CGPoint(x: display.minX + display.width * 0.30, y: display.minY + display.height * 0.58),
            anchor: .leading
        )
        // A progress line that keeps moving.
        let progress = CGFloat((time * 0.012).truncatingRemainder(dividingBy: 1.0))
        context.fill(
            Path(roundedRect: CGRect(x: display.minX + display.width * 0.30, y: display.maxY - display.height * 0.16, width: display.width * 0.44, height: max(0.7, display.height * 0.035)), cornerRadius: 1),
            with: .color(Color(red: 1.0, green: 0.82, blue: 0.56).opacity(0.18))
        )
        context.fill(
            Path(roundedRect: CGRect(x: display.minX + display.width * 0.30, y: display.maxY - display.height * 0.16, width: display.width * 0.44 * progress, height: max(0.7, display.height * 0.035)), cornerRadius: 1),
            with: .color(Color(red: 1.0, green: 0.86, blue: 0.62).opacity(0.75))
        )

        // Waveform bars, breathing with the song.
        for index in 0..<9 {
            let barX = display.maxX - display.width * (0.06 + 0.018 * CGFloat(8 - index))
            let energy = 0.25 + 0.75 * abs(sin(time * (1.3 + Double(index) * 0.19) + Double(index) * 0.8))
            let barHeight = display.height * CGFloat(0.14 + 0.56 * energy)
            context.fill(
                Path(roundedRect: CGRect(
                    x: barX - display.width * 0.006,
                    y: display.midY - barHeight * 0.5,
                    width: display.width * 0.012,
                    height: barHeight
                ), cornerRadius: display.width * 0.006),
                with: .color(Color(red: 1.0, green: 0.90, blue: 0.66).opacity(0.35 + 0.55 * energy))
            )
        }

        // Knobs.
        for side in [0.0, 1.0] {
            let knobCenter = CGPoint(x: stereo.minX + stereo.width * (0.050 + 0.900 * CGFloat(side)), y: stereo.midY)
            let knobRadius = stereo.height * 0.24
            context.fill(
                Path(ellipseIn: CGRect(x: knobCenter.x - knobRadius, y: knobCenter.y - knobRadius, width: knobRadius * 2, height: knobRadius * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 0.30, green: 0.28, blue: 0.30), Color(red: 0.10, green: 0.095, blue: 0.11)]),
                    center: CGPoint(x: knobCenter.x - knobRadius * 0.25, y: knobCenter.y - knobRadius * 0.30),
                    startRadius: 0,
                    endRadius: knobRadius
                )
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: knobCenter.x - knobRadius, y: knobCenter.y - knobRadius, width: knobRadius * 2, height: knobRadius * 2)),
                with: .color(Color(red: 1.0, green: 0.80, blue: 0.54).opacity(0.28)),
                lineWidth: 0.8
            )
        }

        // Notes drifting up out of the stereo.
        for index in 0..<7 {
            let phase = (time * (0.085 + 0.018 * Double(index)) + Double(index) * 0.145).truncatingRemainder(dividingBy: 1.0)
            let x = stereo.midX + CGFloat(sin(time * 0.55 + Double(index) * 1.6)) * w * 0.070
            let y = stereo.minY - h * (0.020 + 0.330 * CGFloat(phase))
            let size = s * (0.006 + 0.004 * hash(index, 3241))
            let opacity = (0.06 + 0.22 * (1.0 - phase)) * (0.7 + 0.3 * Double(hash(index, 3243)))
            var note = Path()
            note.addEllipse(in: CGRect(x: x - size, y: y - size * 0.72, width: size * 1.5, height: size * 1.1))
            var stem = Path()
            stem.move(to: CGPoint(x: x + size * 0.45, y: y - size * 0.30))
            stem.addLine(to: CGPoint(x: x + size * 0.45, y: y - size * 2.6))
            stem.addLine(to: CGPoint(x: x + size * 0.95, y: y - size * 2.35))
            note.addPath(stem)
            context.fill(note, with: .color(Color(red: 1.0, green: 0.86, blue: 0.60).opacity(opacity)))
        }

        // MARK: Grade

        // Warm light spilling from the sun side.
        glow(
            &context,
            center: CGPoint(x: w * 0.98, y: h * 0.02),
            radius: s * 0.62,
            color: Color(red: 1.0, green: 0.68, blue: 0.36),
            opacity: 0.10
        )

        // A gentle vignette, heavier at the corners.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.clear, .clear, Color.black.opacity(0.10), Color.black.opacity(0.34)]),
                center: CGPoint(x: w * 0.52, y: h * 0.46),
                startRadius: s * 0.20,
                endRadius: max(w, h) * 0.78
            )
        )
        vignette(&context, size: size, top: 0.42, bottom: 0.48)
    }

    private static func drawCypress(
        _ context: inout GraphicsContext,
        x: CGFloat,
        baseY: CGFloat,
        height: CGFloat,
        width: CGFloat,
        depth: CGFloat,
        seed: Int,
        ink: Color
    ) {
        let lean = (hash(seed, 7) - 0.5) * width * 0.35
        let top = CGPoint(x: x + lean, y: baseY - height)
        let waist = baseY - height * 0.42
        let spread = width * (0.42 + 0.10 * hash(seed, 11))

        var tree = Path()
        tree.move(to: CGPoint(x: x, y: baseY))
        tree.addQuadCurve(
            to: CGPoint(x: x - spread, y: waist),
            control: CGPoint(x: x - spread * 1.25, y: baseY - height * 0.18)
        )
        tree.addQuadCurve(
            to: top,
            control: CGPoint(x: x - spread * 0.78, y: baseY - height * 0.80)
        )
        tree.addQuadCurve(
            to: CGPoint(x: x + spread, y: waist),
            control: CGPoint(x: x + spread * 0.78, y: baseY - height * 0.80)
        )
        tree.addQuadCurve(
            to: CGPoint(x: x, y: baseY),
            control: CGPoint(x: x + spread * 1.25, y: baseY - height * 0.18)
        )
        tree.closeSubpath()
        context.fill(
            tree,
            with: .linearGradient(
                Gradient(colors: [
                    ink.opacity(0.88 + 0.10 * Double(depth)),
                    Color(red: 0.075, green: 0.115, blue: 0.115).opacity(0.92)
                ]),
                startPoint: CGPoint(x: x + spread, y: baseY - height),
                endPoint: CGPoint(x: x - spread, y: baseY)
            )
        )

        // The sun-side rim.
        var rim = Path()
        rim.move(to: top)
        rim.addQuadCurve(
            to: CGPoint(x: x + spread * 0.94, y: waist),
            control: CGPoint(x: x + spread * 0.78, y: baseY - height * 0.80)
        )
        context.stroke(
            rim,
            with: .color(Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.10 + 0.22 * Double(depth))),
            style: StrokeStyle(lineWidth: max(0.5, width * 0.02), lineCap: .round)
        )

        // A hint of trunk on the nearest trees.
        if depth > 0.35 {
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: baseY))
                    path.addLine(to: CGPoint(x: x + lean * 0.2, y: baseY - height * 0.16))
                },
                with: .color(Color(red: 0.18, green: 0.14, blue: 0.12).opacity(0.65)),
                style: StrokeStyle(lineWidth: max(1.0, width * 0.10), lineCap: .round)
            )
        }
    }

    private static func drawCarAhead(
        _ context: inout GraphicsContext,
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        brake: Double,
        seed: Int
    ) {
        let left = center.x - width * 0.5
        let right = center.x + width * 0.5
        let bottom = center.y
        let top = center.y - height

        // A soft shadow under the car.
        context.fill(
            Path(ellipseIn: CGRect(x: left - width * 0.10, y: bottom - height * 0.10, width: width * 1.20, height: height * 0.24)),
            with: .radialGradient(
                Gradient(colors: [Color.black.opacity(0.35), .clear]),
                center: CGPoint(x: center.x, y: bottom),
                startRadius: 0,
                endRadius: width * 0.62
            )
        )

        // Body.
        var body = Path()
        body.move(to: CGPoint(x: left, y: bottom))
        body.addLine(to: CGPoint(x: left + width * 0.04, y: bottom - height * 0.34))
        body.addLine(to: CGPoint(x: left + width * 0.18, y: top + height * 0.18))
        body.addQuadCurve(
            to: CGPoint(x: right - width * 0.18, y: top + height * 0.18),
            control: CGPoint(x: center.x, y: top - height * 0.08)
        )
        body.addLine(to: CGPoint(x: right - width * 0.04, y: bottom - height * 0.34))
        body.addLine(to: CGPoint(x: right, y: bottom))
        body.closeSubpath()
        context.fill(body, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.16, green: 0.14, blue: 0.16),
                Color(red: 0.075, green: 0.070, blue: 0.085)
            ]),
            startPoint: CGPoint(x: center.x, y: top),
            endPoint: CGPoint(x: center.x, y: bottom)
        ))

        // Rear window and roof highlight.
        context.fill(
            Path { path in
                path.move(to: CGPoint(x: left + width * 0.22, y: top + height * 0.24))
                path.addLine(to: CGPoint(x: right - width * 0.22, y: top + height * 0.24))
                path.addLine(to: CGPoint(x: right - width * 0.30, y: top + height * 0.56))
                path.addLine(to: CGPoint(x: left + width * 0.30, y: top + height * 0.56))
                path.closeSubpath()
            },
            with: .color(Color(red: 0.14, green: 0.13, blue: 0.17).opacity(0.90))
        )
        context.stroke(
            Path { path in
                path.move(to: CGPoint(x: left + width * 0.18, y: top + height * 0.20))
                path.addQuadCurve(to: CGPoint(x: right - width * 0.18, y: top + height * 0.20), control: CGPoint(x: center.x, y: top - height * 0.05))
            },
            with: .color(Color(red: 1.0, green: 0.74, blue: 0.44).opacity(0.30)),
            style: StrokeStyle(lineWidth: max(0.6, width * 0.010), lineCap: .round)
        )

        // Tail lights.
        for side in [-1.0, 1.0] {
            let lx = center.x + CGFloat(side) * width * 0.33
            let ly = bottom - height * 0.38
            glow(&context, center: CGPoint(x: lx, y: ly), radius: width * 0.24, color: Color(red: 1.0, green: 0.22, blue: 0.12), opacity: 0.30 * brake)
            context.fill(
                Path(roundedRect: CGRect(x: lx - width * 0.075, y: ly - height * 0.055, width: width * 0.15, height: height * 0.11), cornerRadius: height * 0.04),
                with: .color(Color(red: 1.0, green: 0.30, blue: 0.16).opacity(0.55 + 0.40 * brake))
            )
        }

        // License plate.
        context.fill(
            Path(roundedRect: CGRect(x: center.x - width * 0.11, y: bottom - height * 0.20, width: width * 0.22, height: height * 0.09), cornerRadius: height * 0.012),
            with: .color(Color(red: 0.72, green: 0.70, blue: 0.62).opacity(0.28))
        )

        // Tyres.
        for side in [-1.0, 1.0] {
            context.fill(
                Path(roundedRect: CGRect(x: center.x + CGFloat(side) * width * 0.47 - width * 0.05, y: bottom - height * 0.16, width: width * 0.10, height: height * 0.16), cornerRadius: height * 0.03),
                with: .color(Color.black.opacity(0.75))
            )
        }
    }

    private static func drawOncomingCar(
        _ context: inout GraphicsContext,
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        intensity: CGFloat,
        time: TimeInterval
    ) {
        let left = center.x - width * 0.5
        let right = center.x + width * 0.5
        let bottom = center.y + height * 0.5
        let top = center.y - height * 0.5

        // Headlight wash on the road.
        for side in [-1.0, 1.0] {
            let lx = center.x + CGFloat(side) * width * 0.30
            let ly = center.y - height * 0.05
            glow(
                &context,
                center: CGPoint(x: lx, y: ly),
                radius: width * (0.70 + 0.20 * intensity),
                color: Color(red: 1.0, green: 0.94, blue: 0.78),
                opacity: 0.26 + 0.34 * Double(intensity)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: lx - width * 0.085, y: ly - height * 0.055, width: width * 0.17, height: height * 0.11)),
                with: .color(Color(red: 1.0, green: 0.97, blue: 0.86).opacity(0.70 + 0.25 * Double(intensity)))
            )
        }

        // Body.
        var body = Path()
        body.move(to: CGPoint(x: left, y: bottom))
        body.addLine(to: CGPoint(x: left + width * 0.05, y: bottom - height * 0.36))
        body.addLine(to: CGPoint(x: left + width * 0.20, y: top + height * 0.22))
        body.addQuadCurve(
            to: CGPoint(x: right - width * 0.20, y: top + height * 0.22),
            control: CGPoint(x: center.x, y: top - height * 0.05)
        )
        body.addLine(to: CGPoint(x: right - width * 0.05, y: bottom - height * 0.36))
        body.addLine(to: CGPoint(x: right, y: bottom))
        body.closeSubpath()
        context.fill(body, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.20, green: 0.19, blue: 0.21),
                Color(red: 0.09, green: 0.085, blue: 0.10)
            ]),
            startPoint: CGPoint(x: center.x, y: top),
            endPoint: CGPoint(x: center.x, y: bottom)
        ))
        // Windscreen catching the sunset.
        context.fill(
            Path { path in
                path.move(to: CGPoint(x: left + width * 0.22, y: top + height * 0.30))
                path.addLine(to: CGPoint(x: right - width * 0.22, y: top + height * 0.30))
                path.addLine(to: CGPoint(x: right - width * 0.30, y: top + height * 0.60))
                path.addLine(to: CGPoint(x: left + width * 0.30, y: top + height * 0.60))
                path.closeSubpath()
            },
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.42),
                    Color(red: 0.30, green: 0.24, blue: 0.28).opacity(0.55)
                ]),
                startPoint: CGPoint(x: center.x, y: top + height * 0.30),
                endPoint: CGPoint(x: center.x, y: top + height * 0.60)
            )
        )
        // A glint along the bonnet.
        context.stroke(
            Path { path in
                path.move(to: CGPoint(x: left + width * 0.10, y: bottom - height * 0.38))
                path.addQuadCurve(to: CGPoint(x: right - width * 0.10, y: bottom - height * 0.38), control: CGPoint(x: center.x, y: bottom - height * 0.46))
            },
            with: .color(Color(red: 1.0, green: 0.80, blue: 0.52).opacity(0.18 + 0.20 * Double(intensity))),
            style: StrokeStyle(lineWidth: max(0.6, width * 0.008), lineCap: .round)
        )
    }

    // MARK: - Seaside Records ("Afternoon Side A")

    private static func seasideRecords(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let w = size.width
        let h = size.height

        gradientFill(
            &context,
            Path(CGRect(origin: .zero, size: size)),
            [
                Color(red: 0.235, green: 0.170, blue: 0.135),
                Color(red: 0.150, green: 0.110, blue: 0.095),
                Color(red: 0.080, green: 0.065, blue: 0.060)
            ],
            CGPoint(x: w * 0.5, y: 0),
            CGPoint(x: w * 0.5, y: h)
        )

        // Warm afternoon light from the window.
        glow(&context, center: CGPoint(x: w * 0.30, y: h * 0.22), radius: w * 0.55, color: Color(red: 1.0, green: 0.80, blue: 0.56), opacity: 0.16)

        // Window frame.
        let window = CGRect(x: w * 0.055, y: h * 0.105, width: w * 0.530, height: h * 0.555)
        let frameRadius = w * 0.018
        context.fill(Path(roundedRect: window, cornerRadius: frameRadius), with: .color(Color(red: 0.285, green: 0.195, blue: 0.145)))
        let glass = window.insetBy(dx: w * 0.014, dy: h * 0.014)
        let glassPath = Path(roundedRect: glass, cornerRadius: frameRadius * 0.62)

        context.drawLayer { layer in
            layer.clip(to: glassPath)

            // Sky and sea.
            let horizon = glass.minY + glass.height * 0.46
            gradientFill(
                &layer,
                Path(CGRect(x: glass.minX, y: glass.minY, width: glass.width, height: horizon - glass.minY)),
                [
                    Color(red: 0.760, green: 0.740, blue: 0.680),
                    Color(red: 0.920, green: 0.820, blue: 0.680),
                    Color(red: 0.980, green: 0.850, blue: 0.690)
                ],
                CGPoint(x: glass.midX, y: glass.minY),
                CGPoint(x: glass.midX, y: horizon)
            )
            gradientFill(
                &layer,
                Path(CGRect(x: glass.minX, y: horizon, width: glass.width, height: glass.maxY - horizon)),
                [
                    Color(red: 0.400, green: 0.620, blue: 0.650),
                    Color(red: 0.250, green: 0.470, blue: 0.540),
                    Color(red: 0.130, green: 0.300, blue: 0.380)
                ],
                CGPoint(x: glass.midX, y: horizon),
                CGPoint(x: glass.midX, y: glass.maxY)
            )

            // Low sun and its path on the water.
            let sun = CGPoint(x: glass.minX + glass.width * 0.70, y: glass.minY + glass.height * 0.32)
            let sunRadius = glass.width * 0.070
            glow(&layer, center: sun, radius: glass.width * 0.30, color: Color(red: 1.0, green: 0.90, blue: 0.70), opacity: 0.42)
            layer.fill(
                Path(ellipseIn: CGRect(x: sun.x - sunRadius, y: sun.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)),
                with: .color(Color(red: 1.0, green: 0.95, blue: 0.82))
            )
            for index in 0..<28 {
                let progress = CGFloat(index) / 28.0
                let y = horizon + (glass.maxY - horizon) * progress
                let width = glass.width * (0.012 + 0.085 * progress) * (0.45 + 0.55 * hash(index, 1701))
                let x = sun.x + (hash(index, 1703) - 0.5) * glass.width * 0.035
                let shimmer = 0.55 + 0.45 * sin(time * (0.6 + 0.9 * Double(hash(index, 1707))) + Double(index))
                var glint = Path()
                glint.move(to: CGPoint(x: x - width * 0.5, y: y))
                glint.addLine(to: CGPoint(x: x + width * 0.5, y: y))
                layer.stroke(glint, with: .color(Color(red: 1.0, green: 0.89, blue: 0.68).opacity(0.10 + 0.20 * shimmer)), lineWidth: 1.4)
            }

            // Horizon and a slow sail.
            var horizonLine = Path()
            horizonLine.move(to: CGPoint(x: glass.minX, y: horizon))
            horizonLine.addLine(to: CGPoint(x: glass.maxX, y: horizon))
            layer.stroke(horizonLine, with: .color(Color(red: 1.0, green: 0.93, blue: 0.80).opacity(0.32)), lineWidth: 1)

            let sailX = glass.minX + glass.width * (0.24 + 0.010 * wave(time, 0.10))
            let sailY = horizon - glass.height * 0.012
            var sail = Path()
            sail.move(to: CGPoint(x: sailX, y: sailY - glass.height * 0.055))
            sail.addLine(to: CGPoint(x: sailX, y: sailY))
            sail.addLine(to: CGPoint(x: sailX + glass.width * 0.030, y: sailY))
            sail.closeSubpath()
            layer.fill(sail, with: .color(Color(red: 0.99, green: 0.96, blue: 0.90).opacity(0.90)))
            var hull = Path()
            hull.move(to: CGPoint(x: sailX - glass.width * 0.006, y: sailY + glass.height * 0.004))
            hull.addLine(to: CGPoint(x: sailX + glass.width * 0.036, y: sailY + glass.height * 0.004))
            hull.addLine(to: CGPoint(x: sailX + glass.width * 0.028, y: sailY + glass.height * 0.014))
            hull.addLine(to: CGPoint(x: sailX, y: sailY + glass.height * 0.014))
            hull.closeSubpath()
            layer.fill(hull, with: .color(Color(red: 0.22, green: 0.24, blue: 0.24).opacity(0.80)))

            // A pair of distant gulls.
            for index in 0..<2 {
                let gx = glass.minX + glass.width * (0.46 + 0.10 * CGFloat(index)) + wave(time, 0.20, Double(index)) * glass.width * 0.01
                let gy = glass.minY + glass.height * (0.18 + 0.06 * CGFloat(index))
                var gull = Path()
                gull.move(to: CGPoint(x: gx - glass.width * 0.012, y: gy))
                gull.addQuadCurve(to: CGPoint(x: gx, y: gy + glass.height * 0.006), control: CGPoint(x: gx - glass.width * 0.006, y: gy - glass.height * 0.006))
                gull.addQuadCurve(to: CGPoint(x: gx + glass.width * 0.012, y: gy), control: CGPoint(x: gx + glass.width * 0.006, y: gy - glass.height * 0.006))
                layer.stroke(gull, with: .color(Color(red: 0.28, green: 0.28, blue: 0.27).opacity(0.55)), lineWidth: 1.1)
            }

            // Soft reflection on the glass.
            var reflection = Path()
            reflection.move(to: CGPoint(x: glass.minX + glass.width * 0.08, y: glass.maxY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.42, y: glass.minY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.52, y: glass.minY))
            reflection.addLine(to: CGPoint(x: glass.minX + glass.width * 0.18, y: glass.maxY))
            reflection.closeSubpath()
            layer.fill(reflection, with: .color(.white.opacity(0.035)))
        }

        context.stroke(glassPath, with: .color(Color(red: 0.62, green: 0.46, blue: 0.32).opacity(0.65)), lineWidth: w * 0.005)

        // Mullions.
        var verticalMullion = Path()
        verticalMullion.move(to: CGPoint(x: glass.midX, y: glass.minY))
        verticalMullion.addLine(to: CGPoint(x: glass.midX, y: glass.maxY))
        context.stroke(verticalMullion, with: .color(Color(red: 0.255, green: 0.170, blue: 0.125)), lineWidth: w * 0.008)
        var crossMullion = Path()
        crossMullion.move(to: CGPoint(x: glass.minX, y: glass.minY + glass.height * 0.52))
        crossMullion.addLine(to: CGPoint(x: glass.maxX, y: glass.minY + glass.height * 0.52))
        context.stroke(crossMullion, with: .color(Color(red: 0.255, green: 0.170, blue: 0.125)), lineWidth: w * 0.007)

        // Curtains, breathing slightly.
        for side in 0..<2 {
            let sway = wave(time, 0.16, Double(side) * 2.0) * w * 0.004
            let x0 = side == 0 ? window.minX - w * 0.034 + sway : window.maxX - w * 0.030 + sway
            let x1 = side == 0 ? window.minX + w * 0.026 + sway : window.maxX + w * 0.034 + sway
            var curtain = Path()
            curtain.move(to: CGPoint(x: x0, y: window.minY - h * 0.025))
            curtain.addLine(to: CGPoint(x: x1, y: window.minY - h * 0.025))
            curtain.addLine(to: CGPoint(x: x1, y: window.maxY + h * 0.045))
            curtain.addQuadCurve(to: CGPoint(x: x0, y: window.maxY + h * 0.045), control: CGPoint(x: (x0 + x1) / 2, y: window.maxY + h * 0.065))
            curtain.closeSubpath()
            context.fill(curtain, with: .color(Color(red: 0.40, green: 0.245, blue: 0.175).opacity(0.92)))
            for fold in 0..<3 {
                let fx = x0 + (x1 - x0) * (0.22 + 0.26 * CGFloat(fold))
                var foldPath = Path()
                foldPath.move(to: CGPoint(x: fx, y: window.minY))
                foldPath.addLine(to: CGPoint(x: fx, y: window.maxY + h * 0.035))
                context.stroke(foldPath, with: .color(.black.opacity(0.14)), lineWidth: 2)
            }
        }

        // Record shelves on the right wall.
        let shelf = CGRect(x: w * 0.625, y: h * 0.135, width: w * 0.340, height: h * 0.555)
        context.fill(Path(roundedRect: shelf, cornerRadius: w * 0.008), with: .color(Color(red: 0.180, green: 0.110, blue: 0.085)))
        for row in 0..<4 {
            let rowY = shelf.minY + shelf.height * (0.245 + 0.235 * CGFloat(row))
            var board = Path()
            board.move(to: CGPoint(x: shelf.minX + w * 0.008, y: rowY))
            board.addLine(to: CGPoint(x: shelf.maxX - w * 0.008, y: rowY))
            context.stroke(board, with: .color(Color(red: 0.110, green: 0.065, blue: 0.052)), lineWidth: h * 0.007)
            var cursor = shelf.minX + w * 0.014
            for record in 0..<12 {
                let width = w * (0.012 + 0.012 * hash(row * 30 + record, 1711))
                let height = shelf.height * (0.14 + 0.06 * hash(row * 30 + record, 1713))
                if cursor + width > shelf.maxX - w * 0.012 { break }
                let palette: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.60, 0.30, 0.25), (0.33, 0.44, 0.40), (0.43, 0.35, 0.50),
                    (0.76, 0.60, 0.38), (0.28, 0.36, 0.46), (0.66, 0.40, 0.34)
                ]
                let color = palette[Int(hash(row * 30 + record, 1717) * 5.99)]
                context.fill(
                    Path(CGRect(x: cursor, y: rowY - height, width: width, height: height)),
                    with: .color(Color(red: color.0, green: color.1, blue: color.2).opacity(0.92))
                )
                var seam = Path()
                seam.move(to: CGPoint(x: cursor + width * 0.5, y: rowY - height))
                seam.addLine(to: CGPoint(x: cursor + width * 0.5, y: rowY))
                context.stroke(seam, with: .color(.black.opacity(0.12)), lineWidth: 0.8)
                cursor += width + w * 0.0012
            }
        }

        // Pendant lamp, swaying very slightly.
        let lampX = w * 0.43 + wave(time, 0.22) * w * 0.002
        let lampY = h * 0.185
        glow(&context, center: CGPoint(x: lampX, y: lampY), radius: w * 0.065, color: Color(red: 1.0, green: 0.78, blue: 0.46), opacity: 0.22)
        var cord = Path()
        cord.move(to: CGPoint(x: lampX, y: 0))
        cord.addLine(to: CGPoint(x: lampX, y: lampY - h * 0.040))
        context.stroke(cord, with: .color(.black.opacity(0.35)), lineWidth: 1.6)
        var shade = Path()
        shade.move(to: CGPoint(x: lampX - w * 0.048, y: lampY))
        shade.addLine(to: CGPoint(x: lampX, y: lampY - h * 0.060))
        shade.addLine(to: CGPoint(x: lampX + w * 0.048, y: lampY))
        shade.closeSubpath()
        context.fill(shade, with: .color(Color(red: 0.72, green: 0.44, blue: 0.24)))
        context.fill(
            Path(ellipseIn: CGRect(x: lampX - w * 0.017, y: lampY - h * 0.004, width: w * 0.034, height: h * 0.014)),
            with: .color(Color(red: 1.0, green: 0.90, blue: 0.70))
        )

        // Counter.
        let counterTop = h * 0.735
        context.fill(
            Path(roundedRect: CGRect(x: w * 0.045, y: counterTop, width: w * 0.915, height: h * 0.300), cornerRadius: w * 0.018),
            with: .color(Color(red: 0.285, green: 0.180, blue: 0.130))
        )
        var counterEdge = Path()
        counterEdge.move(to: CGPoint(x: w * 0.045, y: counterTop + 1))
        counterEdge.addLine(to: CGPoint(x: w * 0.960, y: counterTop + 1))
        context.stroke(counterEdge, with: .color(Color(red: 0.80, green: 0.62, blue: 0.42).opacity(0.30)), lineWidth: 2)

        // Turntable.
        context.fill(
            Path(roundedRect: CGRect(x: w * 0.145, y: h * 0.775, width: w * 0.285, height: h * 0.150), cornerRadius: w * 0.012),
            with: .color(Color(red: 0.145, green: 0.130, blue: 0.120))
        )
        context.fill(
            Path(roundedRect: CGRect(x: w * 0.152, y: h * 0.782, width: w * 0.271, height: h * 0.136), cornerRadius: w * 0.010),
            with: .color(Color(red: 0.220, green: 0.190, blue: 0.170))
        )
        let discCenter = CGPoint(x: w * 0.272, y: h * 0.850)
        let discRadius = w * 0.058
        context.fill(
            Path(ellipseIn: CGRect(x: discCenter.x - discRadius, y: discCenter.y - discRadius, width: discRadius * 2, height: discRadius * 2)),
            with: .color(Color(red: 0.060, green: 0.060, blue: 0.070))
        )
        for groove in 0..<7 {
            let radius = discRadius * (0.36 + 0.085 * CGFloat(groove))
            context.stroke(
                Path(ellipseIn: CGRect(x: discCenter.x - radius, y: discCenter.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 0.30, green: 0.30, blue: 0.33).opacity(0.26)),
                lineWidth: 0.8
            )
        }
        // A highlight that turns with the record.
        let highlightAngle = CGFloat(time * 0.10)
        let highlight = CGPoint(
            x: discCenter.x + cos(highlightAngle) * discRadius * 0.58,
            y: discCenter.y + sin(highlightAngle) * discRadius * 0.58
        )
        glow(&context, center: highlight, radius: discRadius * 0.38, color: Color(red: 0.85, green: 0.82, blue: 0.76), opacity: 0.10)
        context.fill(
            Path(ellipseIn: CGRect(x: discCenter.x - discRadius * 0.30, y: discCenter.y - discRadius * 0.30, width: discRadius * 0.60, height: discRadius * 0.60)),
            with: .color(Color(red: 0.72, green: 0.32, blue: 0.22))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: discCenter.x - discRadius * 0.035, y: discCenter.y - discRadius * 0.035, width: discRadius * 0.070, height: discRadius * 0.070)),
            with: .color(Color(red: 0.82, green: 0.79, blue: 0.72))
        )
        // Tonearm.
        var arm = Path()
        arm.move(to: CGPoint(x: w * 0.400, y: h * 0.798))
        arm.addLine(to: CGPoint(x: w * 0.300, y: h * 0.842))
        context.stroke(arm, with: .color(Color(red: 0.76, green: 0.76, blue: 0.73).opacity(0.90)), lineWidth: w * 0.0022)
        context.fill(
            Path(ellipseIn: CGRect(x: w * 0.392, y: h * 0.790, width: w * 0.016, height: h * 0.016)),
            with: .color(Color(red: 0.46, green: 0.45, blue: 0.43))
        )

        // Record sleeves leaning against the wall.
        let sleevePalette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.58, 0.30, 0.25), (0.32, 0.43, 0.40), (0.41, 0.34, 0.49), (0.74, 0.57, 0.36)
        ]
        for index in 0..<7 {
            let x = w * (0.520 + CGFloat(index) * 0.040)
            let top = h * (0.735 - 0.120 - CGFloat(index) * 0.010)
            let color = sleevePalette[index % sleevePalette.count]
            context.fill(
                Path(roundedRect: CGRect(x: x, y: top, width: w * 0.038, height: h * 0.120), cornerRadius: 2),
                with: .color(Color(red: color.0, green: color.1, blue: color.2).opacity(0.94))
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: x + w * 0.008, y: top + h * 0.014, width: w * 0.022, height: h * 0.036)),
                with: .color(.black.opacity(0.16)),
                lineWidth: 1
            )
        }

        // Mug on the counter.
        let mug = CGPoint(x: w * 0.815, y: h * 0.760)
        context.fill(
            Path(roundedRect: CGRect(x: mug.x - w * 0.020, y: mug.y, width: w * 0.040, height: h * 0.060), cornerRadius: w * 0.008),
            with: .color(Color(red: 0.76, green: 0.69, blue: 0.58))
        )
        var handle = Path()
        handle.addArc(center: CGPoint(x: mug.x + w * 0.022, y: mug.y + h * 0.030), radius: w * 0.014, startAngle: .degrees(-80), endAngle: .degrees(80), clockwise: false)
        context.stroke(handle, with: .color(Color(red: 0.76, green: 0.69, blue: 0.58)), lineWidth: w * 0.004)
        context.fill(
            Path(ellipseIn: CGRect(x: mug.x - w * 0.017, y: mug.y - h * 0.004, width: w * 0.034, height: h * 0.014)),
            with: .color(Color(red: 0.32, green: 0.21, blue: 0.15))
        )

        // Plant in the near corner.
        let plantBase = CGPoint(x: w * 0.940, y: h * 0.700)
        context.fill(
            Path(roundedRect: CGRect(x: plantBase.x - w * 0.030, y: plantBase.y, width: w * 0.060, height: h * 0.070), cornerRadius: w * 0.008),
            with: .color(Color(red: 0.40, green: 0.24, blue: 0.17))
        )
        for index in 0..<14 {
            let angle = -2.7 + 5.4 * CGFloat(index) / 13.0
            let length = h * (0.070 + 0.070 * hash(index, 1721))
            let flutter = wave(time, 0.35, Double(index)) * w * 0.004
            var frond = Path()
            frond.move(to: plantBase)
            frond.addQuadCurve(
                to: CGPoint(x: plantBase.x + cos(angle) * length * 0.70 + flutter, y: plantBase.y + sin(angle) * length),
                control: CGPoint(x: plantBase.x + cos(angle) * length * 0.20, y: plantBase.y + sin(angle) * length * 0.55)
            )
            context.stroke(frond, with: .color(Color(red: 0.17, green: 0.34, blue: 0.24).opacity(0.90)), lineWidth: 2.0)
        }

        // Dust turning in the window light.
        for index in 0..<44 {
            let x = w * (0.08 + 0.54 * hash(index, 1723)) + wave(time, 0.12 + 0.08 * Double(hash(index, 1727)), Double(index)) * w * 0.012
            let y = h * (0.14 + 0.68 * hash(index, 1729)) + wave(time, 0.09 + 0.06 * Double(hash(index, 1731)), Double(index) + 2) * h * 0.010
            let radius = w * (0.0008 + 0.0016 * hash(index, 1733))
            let twinkle = 0.35 + 0.65 * abs(sin(time * (0.5 + 0.7 * Double(hash(index, 1737))) + Double(index)))
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 1.0, green: 0.88, blue: 0.68).opacity(0.18 + 0.22 * twinkle))
            )
        }

        vignette(&context, size: size, top: 0.46, bottom: 0.48)
    }

    private static func drawCat(_ context: inout GraphicsContext, at origin: CGPoint, scale: CGFloat, time: TimeInterval) {
        let breath = 1 + 0.018 * wave(time, 0.7)
        context.drawLayer { layer in
            layer.translateBy(x: origin.x, y: origin.y)
            layer.scaleBy(x: breath, y: breath)

            // Body.
            layer.fill(
                Path(ellipseIn: CGRect(x: -scale * 46, y: -scale * 26, width: scale * 88, height: scale * 30)),
                with: .color(Color(red: 0.075, green: 0.065, blue: 0.085))
            )
            // Head.
            layer.fill(
                Path(ellipseIn: CGRect(x: -scale * 52, y: -scale * 42, width: scale * 30, height: scale * 26)),
                with: .color(Color(red: 0.075, green: 0.065, blue: 0.085))
            )
            // Ears.
            var ears = Path()
            ears.move(to: CGPoint(x: -scale * 50, y: -scale * 40))
            ears.addLine(to: CGPoint(x: -scale * 47, y: -scale * 50))
            ears.addLine(to: CGPoint(x: -scale * 42, y: -scale * 41))
            ears.closeSubpath()
            ears.move(to: CGPoint(x: -scale * 35, y: -scale * 41))
            ears.addLine(to: CGPoint(x: -scale * 30, y: -scale * 50))
            ears.addLine(to: CGPoint(x: -scale * 27, y: -scale * 39))
            ears.closeSubpath()
            layer.fill(ears, with: .color(Color(red: 0.075, green: 0.065, blue: 0.085)))
            // Tail, curling and flicking.
            let flick = wave(time, 1.1, 0.6) * scale * 4
            var tail = Path()
            tail.move(to: CGPoint(x: scale * 38, y: -scale * 12))
            tail.addCurve(
                to: CGPoint(x: scale * 54 + flick, y: -scale * 2),
                control1: CGPoint(x: scale * 52, y: -scale * 20),
                control2: CGPoint(x: scale * 58, y: -scale * 12)
            )
            layer.stroke(tail, with: .color(Color(red: 0.075, green: 0.065, blue: 0.085)), style: StrokeStyle(lineWidth: scale * 6, lineCap: .round))
            // Warm rim light from the lamp along the back and head.
            var rim = Path()
            rim.move(to: CGPoint(x: -scale * 40, y: -scale * 40))
            rim.addQuadCurve(
                to: CGPoint(x: -scale * 4, y: -scale * 26),
                control: CGPoint(x: -scale * 24, y: -scale * 31)
            )
            rim.addQuadCurve(
                to: CGPoint(x: scale * 40, y: -scale * 15),
                control: CGPoint(x: scale * 20, y: -scale * 24)
            )
            layer.stroke(rim, with: .color(Color(red: 1.0, green: 0.72, blue: 0.40).opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            // A soft inner ear tint.
            var earInner = Path()
            earInner.move(to: CGPoint(x: -scale * 48, y: -scale * 42))
            earInner.addLine(to: CGPoint(x: -scale * 46, y: -scale * 48))
            earInner.addLine(to: CGPoint(x: -scale * 43, y: -scale * 42))
            earInner.closeSubpath()
            earInner.move(to: CGPoint(x: -scale * 34, y: -scale * 42))
            earInner.addLine(to: CGPoint(x: -scale * 31, y: -scale * 48))
            earInner.addLine(to: CGPoint(x: -scale * 29, y: -scale * 41))
            earInner.closeSubpath()
            layer.fill(earInner, with: .color(Color(red: 0.55, green: 0.30, blue: 0.26).opacity(0.45)))
        }
    }

    private static func drawCloud(
        _ context: inout GraphicsContext,
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        seed: Int,
        body: [Color],
        highlight: Color
    ) {
        let path = cloudPath(center: center, width: width, height: height, seed: seed)
        gradientFill(
            &context,
            path,
            body,
            CGPoint(x: center.x, y: center.y - height * 0.9),
            CGPoint(x: center.x, y: center.y + height * 0.35)
        )
        context.drawLayer { layer in
            layer.clip(to: path)
            layer.fill(
                Path(CGRect(
                    x: center.x - width * 0.55,
                    y: center.y - height * 1.30,
                    width: width * 1.10,
                    height: height * 2.30
                )),
                with: .linearGradient(
                    Gradient(colors: [highlight, highlight.opacity(0.25), .clear]),
                    startPoint: CGPoint(x: center.x, y: center.y - height * 1.10),
                    endPoint: CGPoint(x: center.x, y: center.y + height * 0.55)
                )
            )
        }
    }

    /// A smooth, stylised anime cloud: a puffy silhouette with a flat base and
    /// asymmetric lobes, rather than a row of identical circles.
    private static func cloudPath(center: CGPoint, width: CGFloat, height: CGFloat, seed: Int) -> Path {
        let left = center.x - width * 0.5
        let bottom = center.y + height * 0.18
        func px(_ t: CGFloat) -> CGFloat { left + width * t }
        func py(_ t: CGFloat) -> CGFloat { bottom - height * t }

        var path = Path()
        path.move(to: CGPoint(x: left, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: px(0.14), y: py(0.30 + 0.10 * hash(seed, 11))),
            control: CGPoint(x: px(0.01), y: py(0.14))
        )
        path.addQuadCurve(
            to: CGPoint(x: px(0.34), y: py(0.46 + 0.12 * hash(seed, 13))),
            control: CGPoint(x: px(0.20), y: py(0.74 + 0.10 * hash(seed, 17)))
        )
        path.addQuadCurve(
            to: CGPoint(x: px(0.56), y: py(0.58 + 0.10 * hash(seed, 19))),
            control: CGPoint(x: px(0.44), y: py(0.94 + 0.08 * hash(seed, 23)))
        )
        path.addQuadCurve(
            to: CGPoint(x: px(0.76), y: py(0.44 + 0.12 * hash(seed, 29))),
            control: CGPoint(x: px(0.68), y: py(0.78 + 0.08 * hash(seed, 31)))
        )
        path.addQuadCurve(
            to: CGPoint(x: px(0.94), y: py(0.22 + 0.10 * hash(seed, 37))),
            control: CGPoint(x: px(0.88), y: py(0.54))
        )
        path.addQuadCurve(
            to: CGPoint(x: px(1.0), y: bottom),
            control: CGPoint(x: px(1.02), y: py(0.08))
        )
        // A gently sagging underside keeps the cloud from reading as a shelf.
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom),
            control: CGPoint(x: center.x, y: bottom + height * 0.12)
        )
        path.closeSubpath()
        return path
    }

    private static func drawShootingStar(
        _ context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        period: Double,
        start: CGPoint,
        end: CGPoint,
        seed: Int
    ) {
        let local = time.truncatingRemainder(dividingBy: period) / period
        guard local < 0.16 else { return }
        let progress = CGFloat(local / 0.16)
        let head = CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
        let tail = CGPoint(
            x: head.x + size.width * 0.070,
            y: head.y - size.height * 0.040
        )
        var streak = Path()
        streak.move(to: tail)
        streak.addLine(to: head)
        let fade = 1 - Double(progress)
        context.stroke(
            streak,
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.70 * fade)]),
                startPoint: tail,
                endPoint: head
            ),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
        )
        glow(&context, center: head, radius: size.width * 0.010, color: .white, opacity: 0.45 * fade)
    }

    // MARK: - Primitives

    private static func gradientFill(
        _ context: inout GraphicsContext,
        _ path: Path,
        _ colors: [Color],
        _ start: CGPoint,
        _ end: CGPoint
    ) {
        context.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: start, endPoint: end))
    }

    private static func glow(
        _ context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        opacity: Double
    ) {
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.28), .clear]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private static func starGlint(
        _ context: inout GraphicsContext,
        at point: CGPoint,
        radius: CGFloat,
        opacity: Double
    ) {
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.white.opacity(opacity))
        )
        let length = radius * 3.4
        var flare = Path()
        flare.move(to: CGPoint(x: point.x - length, y: point.y))
        flare.addLine(to: CGPoint(x: point.x + length, y: point.y))
        flare.move(to: CGPoint(x: point.x, y: point.y - length))
        flare.addLine(to: CGPoint(x: point.x, y: point.y + length))
        context.stroke(flare, with: .color(.white.opacity(opacity * 0.30)), lineWidth: 0.6)
    }

    private static func sparkle(
        _ context: inout GraphicsContext,
        at point: CGPoint,
        size: CGFloat,
        color: Color,
        opacity: Double
    ) {
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y - size))
        path.addQuadCurve(to: CGPoint(x: point.x + size, y: point.y), control: CGPoint(x: point.x + size * 0.18, y: point.y - size * 0.18))
        path.addQuadCurve(to: CGPoint(x: point.x, y: point.y + size), control: CGPoint(x: point.x + size * 0.18, y: point.y + size * 0.18))
        path.addQuadCurve(to: CGPoint(x: point.x - size, y: point.y), control: CGPoint(x: point.x - size * 0.18, y: point.y + size * 0.18))
        path.addQuadCurve(to: CGPoint(x: point.x, y: point.y - size), control: CGPoint(x: point.x - size * 0.18, y: point.y - size * 0.18))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(opacity)))
    }

    private static func vignette(_ context: inout GraphicsContext, size: CGSize, top: CGFloat, bottom: Double) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [.clear, .clear, Color.black.opacity(0.18), Color.black.opacity(bottom)]),
                startPoint: CGPoint(x: size.width * 0.5, y: size.height * top),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )
    }

    /// A deterministic wave in [-1, 1] so motion is smooth and repeatable.
    private static func wave(_ time: TimeInterval, _ speed: Double, _ phase: Double = 0) -> CGFloat {
        CGFloat(sin(time * speed + phase))
    }

    /// Deterministic noise shared by all scenes so artwork is stable between
    /// redraws and window resizes.
    private static func hash(_ value: Int, _ salt: Int) -> CGFloat {
        let x = sin(Double(value) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(x - floor(x))
    }
}
