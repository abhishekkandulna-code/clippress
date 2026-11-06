import AppKit
import CoreText
import SwiftUI

// Kennect design system, Admin profile: Poppins, 8px spacing grid, fixed teal primary.

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Palette {
    // Brand
    static let primary = Color(hex: 0x00696C)
    static let onPrimary = Color.white
    static let secondaryContainer = Color(hex: 0xCCE8E8)
    static let onSecondaryContainer = Color(hex: 0x0A201F)
    static let tertiary = Color(hex: 0x4C5F7C)

    // Neutral
    static let neutral20 = Color(hex: 0x2D3131)
    static let neutral30 = Color(hex: 0x444747)
    static let neutral40 = Color(hex: 0x5B5F5F)
    static let neutral50 = Color(hex: 0x747877)
    static let neutral60 = Color(hex: 0x8E9191)
    static let neutral70 = Color(hex: 0xA9ACAC)
    static let neutral80 = Color(hex: 0xC4C7C6)
    static let neutral90 = Color(hex: 0xE1E3E2)
    static let neutral95 = Color(hex: 0xEFF1F0)
    static let neutral99 = Color(hex: 0xFBFDFC)
    static let neutralVariant90 = Color(hex: 0xDAE4E4)
    static let surface = Color.white

    // Feedback
    static let error = Color(hex: 0xBA1B1B)
    static let errorStrong = Color(hex: 0x930006)
    static let errorContainer = Color(hex: 0xFFEDE9)
    static let warning = Color(hex: 0xBB8800)
    static let warningContainer = Color(hex: 0xFFEFD2)
    static let success = Color(hex: 0x005230)
    static let successContainer = Color(hex: 0xE8FFEF)
    static let info = Color(hex: 0x4C5F7C)
    static let infoContainer = Color(hex: 0xEAF1FF)
}

enum Space {
    static let s1: CGFloat = 4   // fine-tuning only
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12  // fine-tuning only
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
}

enum Radius {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
}

enum TypeScale {
    case header1, header2, header3, bodyL, bodyM, bodyS

    var size: CGFloat {
        switch self {
        case .header1: return 24
        case .header2: return 20
        case .header3: return 18
        case .bodyL: return 16
        case .bodyM: return 14
        case .bodyS: return 12
        }
    }

    var tracking: CGFloat {
        switch self {
        case .bodyL: return 0.1
        case .bodyM: return 0.2
        case .bodyS: return 0.3
        default: return 0
        }
    }
}

enum FontWeight {
    case regular, medium, semibold, bold

    var postScriptName: String {
        switch self {
        case .regular: return "Poppins-Regular"
        case .medium: return "Poppins-Medium"
        case .semibold: return "Poppins-SemiBold"
        case .bold: return "Poppins-Bold"
        }
    }

    var systemWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

extension Font {
    static func kennect(_ scale: TypeScale, _ weight: FontWeight = .regular) -> Font {
        FontLoader.poppinsAvailable
            ? .custom(weight.postScriptName, fixedSize: scale.size)
            : .system(size: scale.size, weight: weight.systemWeight)
    }
}

extension View {
    func textStyle(_ scale: TypeScale, _ weight: FontWeight = .regular, color: Color = Palette.neutral30) -> some View {
        font(.kennect(scale, weight))
            .tracking(scale.tracking)
            .foregroundColor(color)
    }

    /// shadow.card: 0 2px 12px 0 #0000001A
    func cardShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    /// shadow.button: 1px 1px 6px -2px #0000005C
    func buttonShadow() -> some View {
        shadow(color: .black.opacity(0.36), radius: 2, x: 1, y: 1)
    }

    /// 2px focus-visible ring drawn from the primary colour.
    func focusRing(_ visible: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Palette.primary, lineWidth: 2)
                .padding(-3)
                .opacity(visible ? 1 : 0)
        }
    }
}

/// Registers the bundled Poppins files. Falls back to the system font if they are missing.
enum FontLoader {
    private(set) static var poppinsAvailable = false

    static func registerBundledFonts() {
        for directory in candidateDirectories {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files where file.pathExtension.lowercased() == "ttf" {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
            break
        }
        poppinsAvailable = NSFont(name: FontWeight.regular.postScriptName, size: 12) != nil
    }

    private static var candidateDirectories: [URL] {
        // Inside the .app bundle, then the source checkout (for `swift run` during development).
        let checkout = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts")
        return [Bundle.main.resourceURL?.appendingPathComponent("Fonts"), checkout].compactMap { $0 }
    }
}
