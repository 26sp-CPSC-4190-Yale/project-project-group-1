//
//  SessionHistoryViewModel.swift
//  Unplugged.Features.History
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Replace MockSession array with SessionAPIService.getHistory()

import Foundation
import Observation

struct MockSession: Identifiable {
    let id: String
    let title: String
    let duration: String
    let date: String
}

@MainActor
@Observable
class SessionHistoryViewModel {
    var sessions: [MockSession] = [
        MockSession(id: "1", title: "Unplugged in Bass", duration: "2 Hrs", date: "Mar 20"),
        MockSession(id: "2", title: "Unplugged at Sebastian's Dinner", duration: "1 Hr", date: "Mar 18"),
        MockSession(id: "3", title: "Unplugged at Jonathan's House", duration: "3 Hrs", date: "Mar 15"),
        MockSession(id: "4", title: "Unplugged in Marx", duration: "10 Hrs", date: "Mar 12"),
    ]
}
