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
        #if DEBUG
        MainThreadWatchdog.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
        }
    }
}
