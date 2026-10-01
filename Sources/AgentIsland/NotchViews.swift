import SwiftUI

/// Notch silhouette: flat top that flares outward into the menu bar and
/// rounded bottom corners, like the Dynamic Island on macOS notch apps.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(white: 0.93)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.33)
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.29)
}

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var store: UsageStore

    var body: some View {
        let open = model.isOpen
        let flare: CGFloat = open ? 14 : 0
        // Closed, stay a hair inside the hardware notch so nothing is visible.
        let size = open
            ? model.openSize
            : CGSize(width: max(0, model.notch.width - 4), height: model.notch.height)

        ZStack(alignment: .top) {
            NotchShape(topRadius: flare, bottomRadius: open ? 28 : 8)
                .fill(Color.black)
                .frame(width: size.width + flare * 2, height: size.height)
                .opacity(open || model.notch.hasHardwareNotch ? 1 : 0)
                .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 12, y: 4)

            if open {
                PanelContent(store: store, notch: model.notch)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if !model.isOpen { model.onOpenRequest?() }
        }
    }
}

struct PanelContent: View {
    @ObservedObject var store: UsageStore
    let notch: NotchGeometry

    var body: some View {
        VStack(spacing: 10) {
            header
            HStack(spacing: 10) {
                ProviderCard(title: "Claude Code", tint: Palette.claude, snapshot: store.claude)
                ProviderCard(title: "Codex", tint: Palette.codex, snapshot: store.codex)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }

    /// The header straddles the camera notch: title on the left, refresh on the right.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if let logo = AppAssets.logo {
                    Image(nsImage: logo).resizable().frame(width: 16, height: 16)
                }
                Text("Limites de 5h")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: notch.hasHardwareNotch ? notch.width : 0)

            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(updatedText(now: context.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Button(action: store.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(store.isRefreshing
                                   ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                   : .default,
                                   value: store.isRefreshing)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Atualizar agora")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: notch.height)
    }

    private func updatedText(now: Date) -> String {
        guard let last = store.lastRefresh else { return "carregando…" }
        let seconds = Int(now.timeIntervalSince(last))
        if seconds < 60 { return "agora" }
        return "há \(seconds / 60) min"
    }
}

struct ProviderCard: View {
    let title: String
    let tint: Color
    let snapshot: ProviderSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.07)))
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let session = snapshot.usage?.session
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RingGauge(fraction: session.map { $0.remainingPercent / 100 },
                          tint: color(for: session?.remainingPercent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let session {
                        Text("\(Int(session.remainingPercent.rounded()))% restante")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(Format.sessionReset(session.resetsAt, now: now, includeTime: false))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    } else if snapshot.error == nil {
                        Text("Carregando…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }

            if let error = snapshot.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.warning)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let weekly = snapshot.usage?.weekly {
                WeeklyRow(window: weekly, tint: tint, now: now)
            }
        }
    }

    private func color(for remaining: Double?) -> Color {
        guard let remaining else { return tint }
        if remaining <= 10 { return Palette.danger }
        if remaining <= 25 { return Palette.warning }
        return tint
    }
}

struct RingGauge: View {
    let fraction: Double?
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
            Text(fraction.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 48, height: 48)
    }
}

struct WeeklyRow: View {
    let window: UsageWindow
    let tint: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Semanal")
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% restante")
                    .monospacedDigit()
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(tint.opacity(0.85))
                        .frame(width: proxy.size.width * window.remainingPercent / 100)
                }
            }
            .frame(height: 4)

            Text(Format.weeklyReset(window.resetsAt, now: now))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

enum Format {
    static func countdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes)min" }
        if minutes > 0 { return "\(minutes)min" }
        return "<1min"
    }

    static func sessionReset(_ date: Date?, now: Date, includeTime: Bool = true) -> String {
        guard let date else { return "Nenhuma sessão ativa" }
        if date <= now { return "Reiniciando…" }
        let text = "Reinicia em \(countdown(to: date, now: now))"
        return includeTime ? "\(text) · \(time.string(from: date))" : text
    }

    static func weeklyReset(_ date: Date?, now: Date) -> String {
        guard let date, date > now else { return "Sem data de reinício" }
        return "Reinicia \(weekday.string(from: date)) · em \(countdown(to: date, now: now))"
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEE, HH:mm"
        return f
    }()
}
