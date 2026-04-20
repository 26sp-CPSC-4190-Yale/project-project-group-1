//
//  SessionLocation.swift
//  UnpluggedShared.Models
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct SessionLocation: Codable, Sendable {
    public let sessionID: UUID
    public let latitude: Double
    public let longitude: Double
    public var locationName: String?
    public var metadata: String?
    
    public init(sessionID: UUID, latitude: Double, longitude: Double, locationName: String? = nil, metadata: String? = nil) {
        self.sessionID = sessionID
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.metadata = metadata
    }
}
