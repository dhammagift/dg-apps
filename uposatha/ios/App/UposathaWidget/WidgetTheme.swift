import SwiftUI
import UIKit

// The widget's palette: the same table as Android's (WidgetConfig.LIGHT_C / DARK_C, widget/tools/gen_android_res.py PALETTE),
// as dynamic colours, so the widget follows the system theme. The card is the app's card tint, not white / black.
extension Color {
    static func dg(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255,
                           alpha: 1)
        })
    }

    // A fixed colour (the same in both themes), 0xRRGGBB
    static func hex(_ v: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255,
              opacity: alpha)
    }

    static let dgSurface = dg(0xEEF4F2, 0x1A211F)
    static let dgTile = dg(0xFFFFFF, 0x252D2B)
    static let dgText = dg(0x1B1D19, 0xE2E2E2)
    static let dgText2 = dg(0x5C6058, 0xB0B0B0)
    static let dgMuted = dg(0x6E716A, 0x8E8E8E)
    static let dgAccent = dg(0x149C7C, 0x149C7C)
    static let dgAccentInk = dg(0x0F7C63, 0x1FB394)
    static let dgVikala = dg(0x9B1C31, 0xE0607A)
    static let dgBand = dg(0xCFE9E2, 0x17312C)
    static let dgGold = dg(0xC4972F, 0xC9A13A)
    static let dgGoldBg = dg(0xF5EAD0, 0x3A3220)
    static let dgPlate = dg(0xD1D7DD, 0x393F44)
    static let dgBorderStrong = dg(0xC3CFCB, 0x414B49)
    static let dgPartDay = dg(0xBDE3DA, 0x1D3A34)
    static let dgPartNight = dg(0xC1C9D0, 0x444C54)
}

// The three faces of Lato the design uses (the same files as Android's res/font).
enum DgWeight {
    case regular, semibold, bold

    // The PostScript names of the bundled files (name table, id 6)
    var psName: String {
        switch self {
        case .regular: return "Lato-Regular"
        case .semibold: return "Lato-Semibold"
        case .bold: return "Lato-Bold"
        }
    }

    var system: UIFont.Weight {
        switch self {
        case .regular: return UIFont.Weight.regular
        case .semibold: return UIFont.Weight.semibold
        case .bold: return UIFont.Weight.bold
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: return Font.Weight.regular
        case .semibold: return Font.Weight.semibold
        case .bold: return Font.Weight.bold
        }
    }
}

// Lato is three files in the extension's bundle, named in its Info.plist (UIAppFonts): the system registers them itself, in the
// extension AND in the process that draws the widget from its archive. Registering them by hand from data (CTFontManagerRegisterGraphicsFont)
// worked in the extension only: the archive named a font the drawing process did not have, and it refused the WHOLE widget -
// every size came out black, on a real iPhone and on the simulator (owner, TestFlight 561; uposatha/test/ios-sim/widget-gallery.sh).
enum DgFonts {
    // True when all three faces answer by their PostScript names; false: the widget draws and measures with the system font.
    static let ready: Bool = {
        let faces: [DgWeight] = [.regular, .semibold, .bold]
        return faces.allSatisfy { UIFont(name: $0.psName, size: 12) != nil }
    }()
}

// A fixed size (no Dynamic Type): every design is measured with the same font and scaled to its widget.
func dgFont(_ size: CGFloat, _ weight: DgWeight = .regular) -> Font {
    if DgFonts.ready { return Font.custom(weight.psName, fixedSize: size) }
    return Font.system(size: size, weight: weight.fontWeight)
}

// The same face for measuring
func dgUIFont(_ size: CGFloat, _ weight: DgWeight = .regular) -> UIFont {
    if DgFonts.ready, let f = UIFont(name: weight.psName, size: size) { return f }
    return UIFont.systemFont(ofSize: size, weight: weight.system)
}

// The width of one line of text in the widget's font
func measuredWidth(_ text: String, _ size: CGFloat, _ weight: DgWeight = .regular) -> CGFloat {
    if text.isEmpty { return 0 }
    let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key.font: dgUIFont(size, weight)]
    return (text as NSString).size(withAttributes: attrs).width
}
