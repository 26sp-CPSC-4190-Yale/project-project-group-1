//
//  CreateRoomViewModel.swift
//  Unplugged.Features.Room
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Replace mock createRoom() with async SessionAPIService.createRoom(); return real server room

import Foundation
import Observation

@MainActor
@Observable
class CreateRoomViewModel {
    var roomName = ""
    var selectedDuration: Int = 60
    let durationOptions = [30, 60, 90, 120]

    var canCreate: Bool { !roomName.isEmpty }

    func createRoom() -> MockRoom {
        MockRoom(
            id: UUID().uuidString,
            name: roomName,
            host: "You",
            participantCount: 1,
            duration: selectedDuration
        )
    }
}
