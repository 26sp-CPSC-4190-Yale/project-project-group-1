//
//  JoinRoomViewModel.swift
//  Unplugged.Features.Room
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Replace hardcoded rooms with SessionAPIService.listOpenRooms(); add pull-to-refresh

import Foundation
import Observation

struct MockRoom: Identifiable {
    let id: String
    let name: String
    let host: String
    let participantCount: Int
    let duration: Int
}

@MainActor
@Observable
class JoinRoomViewModel {
    var openRooms: [MockRoom] = [
        MockRoom(id: "1", name: "Sean's Room", host: "Sean", participantCount: 3, duration: 60),
        MockRoom(id: "2", name: "Michael's Room", host: "Michael", participantCount: 2, duration: 120),
        MockRoom(id: "3", name: "Jeff's Room", host: "Jeff", participantCount: 4, duration: 90),
        MockRoom(id: "4", name: "McDonald's Room", host: "McDonald", participantCount: 1, duration: 30),
        MockRoom(id: "5", name: "Joseph's Room", host: "Joseph", participantCount: 5, duration: 60),
        MockRoom(id: "6", name: "William's Room", host: "William", participantCount: 2, duration: 45),
        MockRoom(id: "7", name: "Edward's Room", host: "Edward", participantCount: 3, duration: 60),
    ]
}
