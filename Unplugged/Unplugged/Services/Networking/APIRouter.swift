//
//  APIRouter.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIRouter {

    // Auth
    case login(LoginRequest)
    case register(RegisterRequest)
    case signInWithApple(AppleSignInRequest)
    case signInWithGoogle(GoogleSignInRequest)

    // User
    case getMe
    case searchUsers(query: String)
    case updateMe(UpdateUserRequest)
    case registerDeviceToken(String)
    case deleteMe(DeleteAccountRequest)
    case blockUser(id: UUID)
    case unblockUser(id: UUID)
    case listBlocks
    case reportUser(id: UUID, body: ReportUserRequest)

    // Stats
    case getStats

    // Medals
    case getMyMedals
    case getMedalCatalog

    // Sessions
    case createSession(CreateSessionRequest)
    case listSessions
    case sessionHistory(limit: Int? = nil, before: Date? = nil)
    case getSession(id: UUID)
    case joinSession(id: UUID)
    case joinSessionCode(code: String)
    case startSession(id: UUID)
    case endSession(id: UUID)
    case reportProximityExit(id: UUID)
    case reportJailbreak(id: UUID, body: ReportJailbreakRequest)
    case getRecap(id: UUID)

    // Friends
    case listFriends
    case addFriend(AddFriendRequest)
    case removeFriend(id: UUID)
    case acceptFriend(id: UUID)
    case rejectFriend(id: UUID)
    case nudgeFriend(id: UUID)
    case incomingFriendRequests
    case outgoingFriendRequests
    case getFriendProfile(id: UUID)
    case getLeaderboard

    // Groups
    case createGroup(CreateGroupRequest)
    case listGroups
    case getGroup(id: UUID)
    case addGroupMember(id: UUID, body: AddGroupMemberRequest)
    case removeGroupMember(id: UUID, userID: UUID)
    case deleteGroup(id: UUID)

    var path: String {
        switch self {
        case .login:                    return "/auth/login"
        case .register:                 return "/auth/register"
        case .signInWithApple:          return "/auth/apple"
        case .signInWithGoogle:         return "/auth/google"
        case .getMe, .updateMe, .deleteMe: return "/users/me"
        case .searchUsers(let q):       return "/users/search?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        case .registerDeviceToken:      return "/users/device-token"
        case .listBlocks:               return "/users/blocks"
        case .blockUser(let id), .unblockUser(let id):
            return "/users/\(id)/block"
        case .reportUser(let id, _):    return "/users/\(id)/report"
        case .getStats:                 return "/users/me/stats"
        case .getMyMedals:              return "/users/me/medals"
        case .getMedalCatalog:          return "/medals/catalog"
        case .createSession, .listSessions:
            return "/sessions"
        case .sessionHistory(let limit, let before):
            var items: [URLQueryItem] = []
            if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
            if let before {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                items.append(URLQueryItem(name: "before", value: formatter.string(from: before)))
            }
            guard !items.isEmpty else { return "/sessions/history" }
            var comps = URLComponents()
            comps.queryItems = items
            return "/sessions/history" + (comps.string ?? "")
        case .getSession(let id):       return "/sessions/\(id)"
        case .joinSession(let id):      return "/sessions/\(id)/join"
        case .joinSessionCode(let code):
            let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
            return "/sessions/\(encoded)/join"
        case .startSession(let id):     return "/sessions/\(id)/start"
        case .endSession(let id):       return "/sessions/\(id)/end"
        case .reportProximityExit(let id): return "/sessions/\(id)/proximity-exit"
        case .reportJailbreak(let id, _): return "/sessions/\(id)/jailbreaks"
        case .getRecap(let id):         return "/sessions/\(id)/recap"
        case .listFriends, .addFriend:  return "/friends"
        case .removeFriend(let id):     return "/friends/\(id)"
        case .acceptFriend(let id):     return "/friends/\(id)/accept"
        case .rejectFriend(let id):     return "/friends/\(id)/reject"
        case .nudgeFriend(let id):      return "/friends/\(id)/nudge"
        case .incomingFriendRequests:   return "/friends/requests/incoming"
        case .outgoingFriendRequests:   return "/friends/requests/outgoing"
        case .getFriendProfile(let id): return "/friends/\(id)/profile"
        case .getLeaderboard:           return "/friends/leaderboard"
        case .createGroup, .listGroups: return "/groups"
        case .getGroup(let id), .deleteGroup(let id): return "/groups/\(id)"
        case .addGroupMember(let id, _): return "/groups/\(id)/members"
        case .removeGroupMember(let id, let userID): return "/groups/\(id)/members/\(userID)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .login, .register, .signInWithApple, .signInWithGoogle,
             .createSession, .addFriend, .joinSession, .joinSessionCode, .startSession, .endSession,
             .reportProximityExit, .reportJailbreak, .acceptFriend, .rejectFriend, .nudgeFriend,
             .createGroup, .addGroupMember, .blockUser, .reportUser:
            return .post
        case .registerDeviceToken:
            return .put
        case .getMe, .getStats, .getMyMedals, .getMedalCatalog, .listSessions, .sessionHistory, .getSession, .getRecap,
             .listFriends, .incomingFriendRequests, .outgoingFriendRequests,
             .getFriendProfile, .getLeaderboard,
             .listGroups, .getGroup, .searchUsers, .listBlocks:
            return .get
        case .updateMe:
            return .patch
        case .removeFriend, .removeGroupMember, .deleteGroup, .deleteMe, .unblockUser:
            return .delete
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .login, .register, .signInWithApple, .signInWithGoogle:
            return false
        default:
            return true
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .login(let r):             return r
        case .register(let r):          return r
        case .signInWithApple(let r):   return r
        case .signInWithGoogle(let r):  return r
        case .updateMe(let r):          return r
        case .registerDeviceToken(let token):
            return DeviceTokenRequest(deviceToken: token)
        case .deleteMe(let r):          return r
        case .reportUser(_, let r):     return r
        case .createSession(let r):     return r
        case .reportJailbreak(_, let r): return r
        case .addFriend(let r):         return r
        case .createGroup(let r):       return r
        case .addGroupMember(_, let r): return r
        case .startSession:             return StartSessionRequest()
        default:                        return nil
        }
    }
}
