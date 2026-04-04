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
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIRouter {
    
    // Auth
    case login(LoginRequest)
    case register(RegisterRequest)

    // User
    case getMe
    case updateMe(UpdateUserRequest)

    // Sessions
    case createSession(CreateSessionRequest)
    case listSessions
    case getSession(id: UUID)

    // Friends
    case listFriends
    case addFriend(AddFriendRequest)
    case removeFriend(id: UUID)

    var path: String {
        switch self {
        case .login:             return "/auth/login"
        case .register:          return "/auth/register"
        case .getMe, .updateMe:  return "/users/me"
        case .createSession, .listSessions: return "/sessions"
        case .getSession(let id): return "/sessions/\(id)"
        case .listFriends, .addFriend: return "/friends"
        case .removeFriend(let id): return "/friends/\(id)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .login, .register, .createSession, .addFriend:
            return .post
        case .getMe, .listSessions, .getSession, .listFriends:
            return .get
        case .updateMe:
            return .patch
        case .removeFriend:
            return .delete
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .login, .register:
            return false
        default:
            return true
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .login(let r):          return r
        case .register(let r):       return r
        case .updateMe(let r):       return r
        case .createSession(let r):  return r
        case .addFriend(let r):      return r
        default:                     return nil
        }
    }
}
