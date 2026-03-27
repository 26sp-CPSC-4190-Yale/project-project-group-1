//
//  ActiveRoomViewModel.swift
//  Unplugged.Features.Room
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Replace MockParticipant with real WebSocket data; wire kick to SessionAPIService; add countdown state

import Foundation
import Observation

struct MockParticipant: Identifiable {
    let id: String
    let name: String
    let isHost: Bool
}

@MainActor
@Observable
class ActiveRoomViewModel {
    let room: MockRoom
    let isHost: Bool
    var participants: [MockParticipant]
    var showEndConfirmation = false

    init(room: MockRoom, isHost: Bool = true) {
        self.room = room
        self.isHost = isHost
        self.participants = [
            MockParticipant(id: "1", name: "You", isHost: true),
            MockParticipant(id: "2", name: "Sean", isHost: false),
            MockParticipant(id: "3", name: "Michael", isHost: false),
        ]
    }

    func kickParticipant(_ participant: MockParticipant) {
        participants.removeAll { $0.id == participant.id }
    }
}
