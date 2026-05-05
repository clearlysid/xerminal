import UIKit
import SwiftTerm

struct Theme: Codable, Hashable {
    var name: String
    var bg: RGB
    var fg: RGB
    var cursor: RGB
    /// 16 ANSI colors: 0..7 normal, 8..15 bright.
    var ansi16: [RGB]

    struct RGB: Codable, Hashable {
        var r: UInt8
        var g: UInt8
        var b: UInt8

        init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

        init(_ hex: UInt32) {
            self.r = UInt8((hex >> 16) & 0xFF)
            self.g = UInt8((hex >> 8) & 0xFF)
            self.b = UInt8(hex & 0xFF)
        }

        var uiColor: UIColor {
            UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
        }

        var swiftTermColor: SwiftTerm.Color {
            SwiftTerm.Color(red: UInt16(r) * 257, green: UInt16(g) * 257, blue: UInt16(b) * 257)
        }
    }
}

extension Theme {
    func apply(to view: TerminalView) {
        view.nativeBackgroundColor = bg.uiColor
        view.nativeForegroundColor = fg.uiColor
        view.caretColor = cursor.uiColor
        view.installColors(ansi16.map { $0.swiftTermColor })
    }
}

// MARK: - Bundled themes

extension Theme {
    static let bundled: [Theme] = [kakuDark, flexoki, vercel, githubDark, solarizedDark, dracula, nord, tokyoNight]

    static func named(_ name: String) -> Theme {
        bundled.first { $0.name == name } ?? kakuDark
    }

    static let kakuDark = Theme(
        name: "Kaku Dark",
        bg: RGB(0x0A_0A_0A), fg: RGB(0xE5_E5_E5), cursor: RGB(0xE5_E5_E5),
        ansi16: [
            RGB(0x1A_1A_1A), RGB(0xE0_6C_75), RGB(0x98_C3_79), RGB(0xE5_C0_7B),
            RGB(0x61_AF_EF), RGB(0xC6_78_DD), RGB(0x56_B6_C2), RGB(0xAB_B2_BF),
            RGB(0x4B_4B_4B), RGB(0xE0_6C_75), RGB(0x98_C3_79), RGB(0xE5_C0_7B),
            RGB(0x61_AF_EF), RGB(0xC6_78_DD), RGB(0x56_B6_C2), RGB(0xFF_FF_FF),
        ])

    static let solarizedDark = Theme(
        name: "Solarized Dark",
        bg: RGB(0x00_2B_36), fg: RGB(0x83_94_96), cursor: RGB(0x93_A1_A1),
        ansi16: [
            RGB(0x07_36_42), RGB(0xDC_32_2F), RGB(0x85_99_00), RGB(0xB5_89_00),
            RGB(0x26_8B_D2), RGB(0xD3_36_82), RGB(0x2A_A1_98), RGB(0xEE_E8_D5),
            RGB(0x00_2B_36), RGB(0xCB_4B_16), RGB(0x58_6E_75), RGB(0x65_7B_83),
            RGB(0x83_94_96), RGB(0x6C_71_C4), RGB(0x93_A1_A1), RGB(0xFD_F6_E3),
        ])

    static let dracula = Theme(
        name: "Dracula",
        bg: RGB(0x28_2A_36), fg: RGB(0xF8_F8_F2), cursor: RGB(0xF8_F8_F2),
        ansi16: [
            RGB(0x21_22_2C), RGB(0xFF_55_55), RGB(0x50_FA_7B), RGB(0xF1_FA_8C),
            RGB(0xBD_93_F9), RGB(0xFF_79_C6), RGB(0x8B_E9_FD), RGB(0xF8_F8_F2),
            RGB(0x6D_72_A0), RGB(0xFF_6E_6E), RGB(0x69_FF_94), RGB(0xFF_FF_A5),
            RGB(0xD6_AC_FF), RGB(0xFF_92_DF), RGB(0xA4_FF_FF), RGB(0xFF_FF_FF),
        ])

    static let nord = Theme(
        name: "Nord",
        bg: RGB(0x2E_34_40), fg: RGB(0xD8_DE_E9), cursor: RGB(0xD8_DE_E9),
        ansi16: [
            RGB(0x3B_42_52), RGB(0xBF_61_6A), RGB(0xA3_BE_8C), RGB(0xEB_CB_8B),
            RGB(0x81_A1_C1), RGB(0xB4_8E_AD), RGB(0x88_C0_D0), RGB(0xE5_E9_F0),
            RGB(0x4C_56_6A), RGB(0xBF_61_6A), RGB(0xA3_BE_8C), RGB(0xEB_CB_8B),
            RGB(0x81_A1_C1), RGB(0xB4_8E_AD), RGB(0x8F_BC_BB), RGB(0xEC_EF_F4),
        ])

    /// https://stephango.com/flexoki — inky/warm palette by Steph Ango.
    static let flexoki = Theme(
        name: "Flexoki",
        bg: RGB(0x10_0F_0F), fg: RGB(0xCE_CD_C3), cursor: RGB(0xCE_CD_C3),
        ansi16: [
            RGB(0x10_0F_0F), RGB(0xD1_4D_41), RGB(0x87_9A_39), RGB(0xD0_A2_15),
            RGB(0x43_85_BE), RGB(0xCE_5D_97), RGB(0x3A_A9_9F), RGB(0xCE_CD_C3),
            RGB(0x57_56_53), RGB(0xAF_3A_2A), RGB(0x66_80_0B), RGB(0xAD_85_05),
            RGB(0x20_5E_A6), RGB(0xA0_2F_6F), RGB(0x24_83_7B), RGB(0xFF_FC_F0),
        ])

    /// Vercel-inspired: pure black/white with brand accents (#FF0080, #0070F3, #50E3C2).
    static let vercel = Theme(
        name: "Vercel",
        bg: RGB(0x00_00_00), fg: RGB(0xFA_FA_FA), cursor: RGB(0xFF_FF_FF),
        ansi16: [
            RGB(0x00_00_00), RGB(0xEE_00_00), RGB(0x50_E3_C2), RGB(0xF5_A6_23),
            RGB(0x00_70_F3), RGB(0xFF_00_80), RGB(0x50_E3_C2), RGB(0xFA_FA_FA),
            RGB(0x66_66_66), RGB(0xFF_6E_6E), RGB(0x79_FF_E1), RGB(0xFF_D0_00),
            RGB(0x32_91_FF), RGB(0xFF_40_81), RGB(0x79_FF_E1), RGB(0xFF_FF_FF),
        ])

    /// GitHub Dark — official palette.
    static let githubDark = Theme(
        name: "GitHub Dark",
        bg: RGB(0x0D_11_17), fg: RGB(0xC9_D1_D9), cursor: RGB(0xC9_D1_D9),
        ansi16: [
            RGB(0x48_4F_58), RGB(0xFF_7B_72), RGB(0x3F_B9_50), RGB(0xD2_99_22),
            RGB(0x58_A6_FF), RGB(0xBC_8C_FF), RGB(0x39_C5_CF), RGB(0xB1_BA_C4),
            RGB(0x6E_76_81), RGB(0xFF_A1_98), RGB(0x56_D3_64), RGB(0xE3_B3_41),
            RGB(0x79_C0_FF), RGB(0xD2_A8_FF), RGB(0x56_D4_DD), RGB(0xF0_F6_FC),
        ])

    static let tokyoNight = Theme(
        name: "Tokyo Night",
        bg: RGB(0x1A_1B_26), fg: RGB(0xC0_CA_F5), cursor: RGB(0xC0_CA_F5),
        ansi16: [
            RGB(0x15_16_1E), RGB(0xF7_76_8E), RGB(0x9E_CE_6A), RGB(0xE0_AF_68),
            RGB(0x7A_A2_F7), RGB(0xBB_9A_F7), RGB(0x7D_CF_FF), RGB(0xA9_B1_D6),
            RGB(0x41_48_68), RGB(0xF7_76_8E), RGB(0x9E_CE_6A), RGB(0xE0_AF_68),
            RGB(0x7A_A2_F7), RGB(0xBB_9A_F7), RGB(0x7D_CF_FF), RGB(0xC0_CA_F5),
        ])
}
