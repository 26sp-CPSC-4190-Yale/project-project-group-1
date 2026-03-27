//
//  HomeViewModel.swift
//  Unplugged.Features.Home
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Hold SessionOrchestrator reference for active session state across tab switches

import Foundation
import Observation

@MainActor
@Observable
class HomeViewModel {
    var showJoinRoom = false
    var showCreateRoom = false
    var activeRoom: MockRoom?
}
