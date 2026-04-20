//
//  View+ConditionalModifier.swift
//  Unplugged.Extensions
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

