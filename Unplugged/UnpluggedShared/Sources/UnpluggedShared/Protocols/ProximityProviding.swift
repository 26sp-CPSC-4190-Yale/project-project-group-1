//
//  ProximityProviding.swift
//  UnpluggedShared.Protocols
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public protocol ProximityProviding: AnyObject, Sendable {
    var onDistanceUpdate: (@Sendable (Double?) -> Void)? { get set }
    func startSession(peerID: UUID)
    func stopSession()
}

