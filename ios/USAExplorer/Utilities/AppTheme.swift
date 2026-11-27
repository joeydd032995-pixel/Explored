import SwiftUI
import UIKit

/// Single source of truth for the app's visual language: navy fog, gold
/// territory. Every view pulls from here so the palette never drifts.
/// `nonisolated`: pure constants, safe from any executor (map renderers
/// read them from nonisolated MapKit delegate callbacks).
nonisolated enum AppTheme {
    // MARK: Core palette

    /// The canvas — deep navy everything sits on.
    static let primaryNavy = Color(red: 10/255, green: 15/255, blue: 30/255)   // #0A0F1E
    /// Card surface.
    static let surface = Color(red: 18/255, green: 24/255, blue: 42/255)       // #12182A
    /// Elevated surfaces (sheets, nested cards).
    static let elevated = Color(red: 15/255, green: 21/255, blue: 40/255)      // #0F1528
    /// The accent — discovered territory, progress, calls to action.
    static let gold = Color(red: 245/255, green: 197/255, blue: 24/255)        // #F5C518
    static let goldMuted = Color(red: 200/255, green: 160/255, blue: 30/255)
    static let goldHighlight = Color(red: 255/255, green: 220/255, blue: 80/255)

    // MARK: Semantic

    static let success = Color(red: 0.25, green: 0.78, blue: 0.45)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.15)
    /// Cameras and other sensitive layers.
    static let danger = Color(red: 0.90, green: 0.27, blue: 0.27)

    // MARK: UIKit counterparts (MapKit renderers can't take SwiftUI colors)

    enum ui {
        static let navy = UIColor(red: 10/255, green: 15/255, blue: 30/255, alpha: 1)
        static let gold = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 1)
        static let goldMuted = UIColor(red: 200/255, green: 160/255, blue: 30/255, alpha: 1)
        static let goldHighlight = UIColor(red: 255/255, green: 220/255, blue: 80/255, alpha: 1)
        static let danger = UIColor(red: 0.90, green: 0.27, blue: 0.27, alpha: 1)
    }

    // MARK: Typography

    /// Big display numerals — the national percentage and hero stats.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Uppercase, tracked eyebrow labels above sections.
    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.5))
    }
}

// MARK: - Card treatment

extension View {
    /// The standard card: continuous-corner surface, hairline border, layered
    /// shadow lifting it off the navy canvas.
    func appCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    /// Frosted navy container for map HUD controls: material underneath, navy
    /// tint on top, hairline border and a soft shadow so the cluster floats
    /// over the map.
    func hudChrome() -> some View {
        self
            .background(AppTheme.primaryNavy.opacity(0.75))
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

// MARK: - Ring gauge

/// Small circular progress with a gold fill — used on state rows and the
/// confidence meter.
struct RingGauge: View {
    /// 0...1
    let progress: Double
    var size: CGFloat = 26
    var lineWidth: CGFloat = 3.5
    var tint: Color = AppTheme.gold

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.0001), 1))
                .stroke(
                    AngularGradient(colors: [tint, AppTheme.goldHighlight], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)
    }
}

// MARK: - Progress bar

/// The brand progress bar: 8 pt tall, gold gradient, chamfered capsule, and a
/// spring on every width change.
struct ThemedProgressBar: View {
    /// 0...100
    let percent: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.gold, AppTheme.goldHighlight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * min(1, max(percent, 0) / 100)))
                    .overlay(alignment: .trailing) {
                        // Inner highlight edge.
                        Capsule()
                            .fill(.white.opacity(0.35))
                            .frame(width: 1.5)
                            .padding(.vertical, 1)
                            .opacity(percent > 0.5 ? 1 : 0)
                    }
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: percent)
    }
}

// MARK: - Status dot

/// Tiny enabled / low-confidence / disabled indicator.
struct StatusDot: View {
    enum State {
        case active, idle, muted
    }

    let state: State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 3)
                    .opacity(state == .active ? 1 : 0)
            )
    }

    private var color: Color {
        switch state {
        case .active: AppTheme.success
        case .idle: AppTheme.warning
        case .muted: .white.opacity(0.3)
        }
    }
}

// MARK: - Hex particle field

/// A slow drift of tiny gold hexagons behind the national percentage — pure
/// atmosphere, drawn on Canvas so it costs nothing but a draw pass.
struct HexParticleField: View {
    var density: Int = 26

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<density {
                    let seed = Double(i)
                    let x = clamped(
                        (sin(t * 0.05 + seed * 1.7) + 1) / 2 * (size.width + 60) - 30,
                        size.width
                    )
                    let y = clamped(
                        (cos(t * 0.04 + seed * 2.3) + 1) / 2 * size.height,
                        size.height
                    )
                    let radius: CGFloat = 3 + CGFloat((i * 7) % 5)
                    let alpha = 0.05 + 0.05 * ((i * 13) % 4 == 0 ? 2.0 : 1.0)

                    var path = Path()
                    let vertices = (0..<6).map { angle -> CGPoint in
                        let theta = Double(angle) * .pi / 3 + t * 0.1 + seed
                        return CGPoint(
                            x: x + CGFloat(cos(theta)) * radius,
                            y: y + CGFloat(sin(theta)) * radius
                        )
                    }
                    path.move(to: vertices[0])
                    vertices.dropFirst().forEach { path.addLine(to: $0) }
                    path.closeSubpath()

                    context.fill(path, with: .color(AppTheme.gold.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func clamped(_ value: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(0, value), upper)
    }
}
