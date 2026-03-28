//
//  Theme.swift
//  Unplugged.SharedUI.Styles
//
//  Created by Sebastian Gonzalez on 3/12/26.
//
// Define colors, fonts, and spacing for the entire app

import SwiftUI

// MARK: - Colors
// Usage: Color.primaryColor, Color.secondaryColor, Color.tertiaryColor
extension Color {
    static let primaryColor = Color(red: 0, green: 53.0 / 255.0, blue: 107.0 / 255.0)
    static let secondaryColor = Color(red: 135.0 / 255.0, green: 193.0 / 255.0, blue: 168.0 / 255.0)
    static let tertiaryColor = Color(red: 255.0 / 255.0, green: 255.0 / 255.0, blue: 255.0 / 255.0)
    static let destructiveColor = Color(red: 220.0 / 255.0, green: 53.0 / 255.0, blue: 69.0 / 255.0)
    static let surfaceColor = Color(red: 0, green: 40.0 / 255.0, blue: 82.0 / 255.0)
}

// MARK: - Fonts
// Usage: Font.titleFont, Font.headlineFont
extension Font {
    static let titleFont = Font.system(size: 34, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 17, weight: .regular, design: .default)
    static let captionFont = Font.system(size: 13, weight: .regular, design: .default)
}

// MARK: - Spacing & Radius
// Usage: CGFloat.spacingMd, CGFloat.cornerRadius
extension CGFloat {
    static let spacingSm: CGFloat = 8
    static let spacingMd: CGFloat = 16
    static let spacingLg: CGFloat = 24
    static let spacingXl: CGFloat = 32

    static let cornerRadiusSm: CGFloat = 8
    static let cornerRadius: CGFloat = 16
}
