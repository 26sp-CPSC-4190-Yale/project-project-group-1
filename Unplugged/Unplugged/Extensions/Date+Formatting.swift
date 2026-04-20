//
//  Date+Formatting.swift
//  Unplugged.Extensions
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

extension Date {
    func toRelativeTime() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    func toShortDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

