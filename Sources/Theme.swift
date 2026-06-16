import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        case 3:
            (r, g, b) = ((value >> 8 & 0xF) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

struct DeckButton: ButtonStyle {
    var tint: Color
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Color.black : tint)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(filled ? tint : tint.opacity(0.14))
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(Rectangle())
    }
}
