import SwiftUI
import UIKit

extension Color {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let groupedBG = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let accentSleep = Color.dynamic(0x5856D6, 0x7D7AFF)
    static let snoreTint = Color.dynamic(0xC9601E, 0xFF9F5A)
    static let talkTint = Color.dynamic(0x8E44D9, 0xC48BFF)
    static let regularTint = Color.dynamic(0x0A84FF, 0x409CFF)

    // Night-only palette (bedtime screen is always dark).
    static let nightInk = Color(red: 0.914, green: 0.839, blue: 0.765)
    static let nightQuiet = Color(red: 0.612, green: 0.549, blue: 0.486)
    static let nightCard = Color(red: 0.07, green: 0.06, blue: 0.05)
    static let nightButton = Color(red: 0.914, green: 0.725, blue: 0.541)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension SleepStage {
    var color: Color {
        switch self {
        case .awake: .dynamic(0xFF8D61, 0xFF9F6E)
        case .rem: .dynamic(0x3DB8F5, 0x5AC8FA)
        case .light: .dynamic(0x1E7CF2, 0x2F8BFF)
        case .deep: .dynamic(0x3634A3, 0x5E5CE6)
        }
    }
}

extension ScorePart.Kind {
    var color: Color {
        switch self {
        case .duration: .dynamic(0x5856D6, 0x5E5CE6)
        case .unbroken: .dynamic(0x0A84FF, 0x0A84FF)
        case .regularity: .dynamic(0x32ADE6, 0x64D2FF)
        case .depth: .dynamic(0x3634A3, 0x7D7AFF)
        case .onset: .dynamic(0x8E8CF5, 0xBF9CFF)
        }
    }
}

extension EventKind {
    var tint: Color {
        switch self {
        case .snoring: .snoreTint
        case .talking: .talkTint
        case .fellAsleep, .lightsOut: .accentSleep
        case .wokeUp: .dynamic(0xA86B00, 0xFFD60A)
        case .nightEnded: .dynamic(0x1F7A3A, 0x30D158)
        default: .secondary
        }
    }

    var title: String {
        switch self {
        case .phoneDown: "Phone put down"
        case .lightsOut: "Lights out"
        case .fellAsleep: "Fell asleep"
        case .snoring: "Snoring"
        case .talking: "Talking in your sleep"
        case .cough: "Cough"
        case .awake: "Awake"
        case .wokeUp: "Woke up"
        case .nightEnded: "Night ended"
        }
    }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
