//
//  TimeInterval+Display.swift
//  Unplugged.Extensions
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

extension TimeInterval {
    /// "H:MM:SS" when the value is at least one hour, "M:SS" otherwise.
    var hms: String {
        let total = max(0, Int(self))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "MM:SS" fixed-width regardless of duration.
    var mmss: String {
        let total = max(0, Int(self))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Compact human-readable form: "2h 15m", "45m", "12s".
    var humanReadable: String {
        let total = max(0, Int(self))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }
}
