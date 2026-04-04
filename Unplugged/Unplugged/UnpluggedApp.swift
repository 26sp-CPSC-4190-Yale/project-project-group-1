//
//  UnpluggedApp.swift
//  Unplugged
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

@main
struct UnpluggedApp: App {
    @State private var container = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
        }
    }
}
