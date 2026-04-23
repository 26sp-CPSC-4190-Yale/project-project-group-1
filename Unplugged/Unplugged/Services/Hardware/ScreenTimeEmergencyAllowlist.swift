//
//  ScreenTimeEmergencyAllowlist.swift
//  Unplugged.Services.Hardware
//

import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

enum EmergencySystemApplication: String, CaseIterable, Identifiable {
    case appStore
    case books
    case calculator
    case calendar
    case camera
    case clock
    case compass
    case contacts
    case faceTime
    case files
    case findMy
    case fitness
    case freeform
    case health
    case home
    case iTunesStore
    case journal
    case mail
    case maps
    case messages
    case music
    case news
    case notes
    case passwords
    case phone
    case photos
    case podcasts
    case reminders
    case safari
    case settings
    case shortcuts
    case stocks
    case tips
    case translate
    case tv
    case voiceMemos
    case wallet
    case watch
    case weather

    var id: String { bundleIdentifier }

    var bundleIdentifier: String {
        switch self {
        case .appStore: "com.apple.AppStore"
        case .books: "com.apple.iBooks"
        case .calculator: "com.apple.calculator"
        case .calendar: "com.apple.mobilecal"
        case .camera: "com.apple.camera"
        case .clock: "com.apple.mobiletimer"
        case .compass: "com.apple.compass"
        case .contacts: "com.apple.MobileAddressBook"
        case .faceTime: "com.apple.facetime"
        case .files: "com.apple.DocumentsApp"
        case .findMy: "com.apple.findmy"
        case .fitness: "com.apple.Fitness"
        case .freeform: "com.apple.freeform"
        case .health: "com.apple.Health"
        case .home: "com.apple.Home"
        case .iTunesStore: "com.apple.MobileStore"
        case .journal: "com.apple.journal"
        case .mail: "com.apple.mobilemail"
        case .maps: "com.apple.Maps"
        case .messages: "com.apple.MobileSMS"
        case .music: "com.apple.music"
        case .news: "com.apple.News"
        case .notes: "com.apple.mobilenotes"
        case .passwords: "com.apple.Passwords"
        case .phone: "com.apple.mobilephone"
        case .photos: "com.apple.mobileslideshow"
        case .podcasts: "com.apple.podcasts"
        case .reminders: "com.apple.reminders"
        case .safari: "com.apple.mobilesafari"
        case .settings: "com.apple.Preferences"
        case .shortcuts: "com.apple.shortcuts"
        case .stocks: "com.apple.stocks"
        case .tips: "com.apple.tips"
        case .translate: "com.apple.Translate"
        case .tv: "com.apple.TV"
        case .voiceMemos: "com.apple.VoiceMemos"
        case .wallet: "com.apple.Passbook"
        case .watch: "com.apple.Bridge"
        case .weather: "com.apple.weather"
        }
    }

    var title: String {
        switch self {
        case .appStore: "App Store"
        case .books: "Books"
        case .calculator: "Calculator"
        case .calendar: "Calendar"
        case .camera: "Camera"
        case .clock: "Clock"
        case .compass: "Compass"
        case .contacts: "Contacts"
        case .faceTime: "FaceTime"
        case .files: "Files"
        case .findMy: "Find My"
        case .fitness: "Fitness"
        case .freeform: "Freeform"
        case .health: "Health"
        case .home: "Home"
        case .iTunesStore: "iTunes Store"
        case .journal: "Journal"
        case .mail: "Mail"
        case .maps: "Maps"
        case .messages: "Messages"
        case .music: "Music"
        case .news: "News"
        case .notes: "Notes"
        case .passwords: "Passwords"
        case .phone: "Phone"
        case .photos: "Photos"
        case .podcasts: "Podcasts"
        case .reminders: "Reminders"
        case .safari: "Safari"
        case .settings: "Settings"
        case .shortcuts: "Shortcuts"
        case .stocks: "Stocks"
        case .tips: "Tips"
        case .translate: "Translate"
        case .tv: "TV"
        case .voiceMemos: "Voice Memos"
        case .wallet: "Wallet"
        case .watch: "Watch"
        case .weather: "Weather"
        }
    }

    var symbolName: String {
        switch self {
        case .appStore: "a.circle.fill"
        case .books: "books.vertical.fill"
        case .calculator: "plus.forwardslash.minus"
        case .calendar: "calendar"
        case .camera: "camera.fill"
        case .clock: "clock.fill"
        case .compass: "safari.fill"
        case .contacts: "person.crop.circle.fill"
        case .faceTime: "video.fill"
        case .files: "folder.fill"
        case .findMy: "location.circle.fill"
        case .fitness: "figure.run.circle.fill"
        case .freeform: "square.grid.2x2.fill"
        case .health: "heart.fill"
        case .home: "house.fill"
        case .iTunesStore: "star.circle.fill"
        case .journal: "book.closed.fill"
        case .mail: "envelope.fill"
        case .maps: "map.fill"
        case .messages: "message.fill"
        case .music: "music.note"
        case .news: "newspaper.fill"
        case .notes: "note.text"
        case .passwords: "key.fill"
        case .phone: "phone.fill"
        case .photos: "photo.fill"
        case .podcasts: "dot.radiowaves.left.and.right"
        case .reminders: "checklist"
        case .safari: "safari.fill"
        case .settings: "gearshape.fill"
        case .shortcuts: "square.stack.3d.down.right.fill"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .tips: "lightbulb.fill"
        case .translate: "translate"
        case .tv: "tv.fill"
        case .voiceMemos: "waveform"
        case .wallet: "wallet.pass.fill"
        case .watch: "applewatch"
        case .weather: "cloud.sun.fill"
        }
    }
}

#if canImport(FamilyControls)
nonisolated struct ScreenTimeEmergencyAllowlist: Codable, Equatable, Sendable {
    var selection: FamilyActivitySelection
    var allowedSystemApplicationBundleIdentifiers: Set<String>

    init(
        selection: FamilyActivitySelection = FamilyActivitySelection(includeEntireCategory: false),
        allowedSystemApplicationBundleIdentifiers: Set<String> = []
    ) {
        self.selection = selection
        self.allowedSystemApplicationBundleIdentifiers = allowedSystemApplicationBundleIdentifiers
    }
}
#endif
