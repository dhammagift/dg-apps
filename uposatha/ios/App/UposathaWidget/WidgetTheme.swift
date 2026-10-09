import SwiftUI

// The app's own colour tokens (--dg-*, light / dark), as dynamic colours: the widget follows the system theme.
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

    static let dgSurface = dg(0xFFFFFF, 0x191919)
    static let dgText = dg(0x1B1D19, 0xDDDDDD)
    static let dgMuted = dg(0x6E716A, 0x7C7C7C)
    static let dgAccent = dg(0x149C7C, 0x136857)
    static let dgAccentInk = dg(0x0F7C63, 0x09967A)
    static let dgNavy = dg(0x243448, 0x1B2836)
    static let dgNavyInk = dg(0x2F4A63, 0xA9C4DC)
    static let dgBorder = dg(0xE7E5DE, 0x2C2C2C)
    static let dgBorderStrong = dg(0xD7D4C9, 0x3B3B3B)
    // The shadow of the moon: --dg-navy 70 % + black
    static let dgMoonShade = dg(0x192432, 0x131C26)
    // vikala: the production literal (#9b1c31, dark #d8546b), there is no token for it
    static let dgVikala = dg(0x9B1C31, 0xD8546B)
}

// The designer's typeface is Lato. iOS cannot load the site's .woff2 files (UIAppFonts takes TTF/OTF), so the widget
// uses the system font; to switch, bundle Lato's TTFs, list them in UIAppFonts and change this one function.
func dgFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    Font.system(size: size, weight: weight)
}
