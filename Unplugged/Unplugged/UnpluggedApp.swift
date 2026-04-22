//
//  UnpluggedApp.swift
//  Unplugged
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

@main
struct UnpluggedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container: DependencyContainer

    init() {
        let container = DependencyContainer()
        _container = State(initialValue: container)
        AppDelegate.sharedContainer = container
        Self.configureNavigationBarAppearance()
        #if DEBUG
        MainThreadWatchdog.shared.start()
        #endif
    }

    private static func configureNavigationBarAppearance() {
        let navy = UIColor(red: 0, green: 53.0 / 255.0, blue: 107.0 / 255.0, alpha: 1)
        let white = UIColor.white

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = navy
        appearance.titleTextAttributes = [.foregroundColor: white]
        appearance.largeTitleTextAttributes = [.foregroundColor: white]
        appearance.shadowColor = .clear

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = white
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
        }
    }
}
