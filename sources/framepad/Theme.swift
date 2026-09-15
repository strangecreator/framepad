import SwiftUI
import FramepadCore

enum Palette {
    static let background = Color(hex: 0x111315)
    static let surface = Color(hex: 0x191C1F)
    static let raised = Color(hex: 0x22262A)
    static let border = Color.white.opacity(0.085)
    static let text = Color(hex: 0xF0F2ED)
    static let secondary = Color(hex: 0x999FA5)
    static let muted = Color(hex: 0x687079)
    static let accent = Color(hex: 0xD4F49B)
}
extension Color {
    init(hex: UInt) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

struct BrandMark: View {
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27).fill(Palette.accent)
            Image(systemName: "viewfinder").font(.system(size: size * 0.66, weight: .medium)).foregroundStyle(Palette.background)
            Image(systemName: "play.fill").font(.system(size: size * 0.23, weight: .bold)).foregroundStyle(Palette.background).offset(x: 1)
        }.frame(width: size, height: size)
    }
}
struct TimeLabel: View {
    var seconds: Double
    var size: CGFloat = 12
    var highlighted = false
    var body: some View {
        let parts = Timecode.parts(seconds)
        HStack(spacing: 0) {
            Text(parts.main).foregroundStyle(highlighted ? Palette.accent : Palette.text)
            Text(parts.milliseconds).foregroundStyle(Palette.muted)
        }.font(.system(size: size, weight: .medium, design: .monospaced)).monospacedDigit()
            .accessibilityLabel(Timecode.string(seconds))
    }
}
struct KeyCap: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.secondary).padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.border, lineWidth: 1))
    }
}
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.background)
            .padding(.horizontal, 17).padding(.vertical, 11)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
            .scaleEffect(configuration.isPressed ? 0.98 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .buttonHover(cornerRadius: 9)
    }
}
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border, lineWidth: 1))
            .buttonHover()
    }
}
struct IconButton: View {
    var symbol: String
    var help: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Palette.accent : Palette.secondary)
                .frame(width: 30, height: 30)
                .background(active ? Palette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(PointerButtonStyle(horizontalPadding: 0)).help(help).accessibilityLabel(help)
    }
}
struct SectionLabel: View {
    var title: String
    var body: some View { Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted) }
}
