//
//  ScreenTimeProviding.swift
//  UnpluggedShared.Protocols
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

public protocol ScreenTimeProviding: AnyObject, Sendable {
    func lockApps() async throws
    func unlockApps() async throws
}

