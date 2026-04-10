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

    // Stats
    case getStats

    // Sessions
    case createSession(CreateSessionRequest)
    case listSessions
    case sessionHistory
    case getSession(id: UUID)
    case joinSession(id: UUID)
    case joinSessionCode(code: String)
    case startSession(id: UUID)
    case endSession(id: UUID)
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
        case .getMe, .updateMe:         return "/users/me"
        case .searchUsers(let q):       return "/users/search?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        case .registerDeviceToken:      return "/users/device-token"
        case .getStats:                 return "/users/me/stats"
        case .createSession, .listSessions:
            return "/sessions"
        case .sessionHistory:           return "/sessions/history"
        case .getSession(let id):       return "/sessions/\(id)"
        case .joinSession(let id):      return "/sessions/\(id)/join"
        case .joinSessionCode(let code): return "/sessions/\(code)/join"
        case .startSession(let id):     return "/sessions/\(id)/start"
        case .endSession(let id):       return "/sessions/\(id)/end"
        case .reportJailbreak(let id, _): return "/sessions/\(id)/jailbreaks"
        case .getRecap(let id):         return "/sessions/\(id)/recap"
        case .listFriends, .addFriend:  return "/friends"
        case .removeFriend(let id):     return "/friends/\(id)"
        case .acceptFriend(let id):     return "/friends/\(id)/accept"
        case .rejectFriend(let id):     return "/friends/\(id)/reject"
        case .nudgeFriend(let id):      return "/friends/\(id)/nudge"
        case .incomingFriendRequests:   return "/friends/requests/incoming"
        case .outgoingFriendRequests:   return "/friends/requests/outgoing"
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
             .reportJailbreak, .acceptFriend, .rejectFriend, .nudgeFriend,
             .createGroup, .addGroupMember:
            return .post
        case .registerDeviceToken:
            return .put
        case .getMe, .getStats, .listSessions, .sessionHistory, .getSession, .getRecap,
             .listFriends, .incomingFriendRequests, .outgoingFriendRequests,
             .listGroups, .getGroup, .searchUsers:
            return .get
        case .updateMe:
            return .patch
        case .removeFriend, .removeGroupMember, .deleteGroup:
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
        case .createSession(let r):     return r
        case .reportJailbreak(_, let r): return r
        case .addFriend(let r):         return r
        case .createGroup(let r):       return r
        case .addGroupMember(_, let r): return r
        default:                        return nil
        }
    }
}
