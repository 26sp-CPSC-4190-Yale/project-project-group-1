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
    case login(LoginRequest)
    case register(RegisterRequest)
    case signInWithApple(AppleSignInRequest)
    case signInWithGoogle(GoogleSignInRequest)

    case getMe
    case reportPresence(PresenceUpdateRequest)
    case searchUsers(query: String)
    case updateMe(UpdateUserRequest)
    case registerDeviceToken(String)
    case clearDeviceToken
    case deleteMe(DeleteAccountRequest)
    case blockUser(id: UUID)
    case unblockUser(id: UUID)
    case listBlocks
    case reportUser(id: UUID, body: ReportUserRequest)

    case getStats

    case getMyMedals
    case getMedalCatalog

    case createSession(CreateSessionRequest)
    case listSessions
    case sessionHistory(limit: Int? = nil, before: Date? = nil)
    case getSession(id: UUID)
    case joinSession(id: UUID)
    case joinSessionCode(code: String)
    case startSession(id: UUID)
    case endSession(id: UUID)
    case leaveSession(id: UUID)
    case updateSessionMetadata(id: UUID, body: SessionMetadataRequest)
    case setCoLockReady(id: UUID, body: CoLockReadyRequest)
    case requestCoLockRelease(id: UUID)
    case approveCoLockRelease(id: UUID)
    case listSessionPhotos(id: UUID)
    case uploadSessionPhoto(id: UUID, body: UploadSessionPhotoRequest)
    case deleteSessionPhoto(id: UUID, photoID: UUID)
    case reportProximityExit(id: UUID)
    case reportJailbreak(id: UUID, body: ReportJailbreakRequest)
    case reportShieldAttempt(id: UUID, body: ShieldActionAttemptRequest)
    case getRecap(id: UUID)

    case listFriends
    case addFriend(AddFriendRequest)
    case removeFriend(id: UUID)
    case acceptFriend(id: UUID)
    case rejectFriend(id: UUID)
    case acceptFriendRequest(id: UUID)
    case rejectFriendRequest(id: UUID)
    case nudgeFriend(id: UUID)
    case incomingFriendRequests
    case outgoingFriendRequests
    case getFriendProfile(id: UUID)
    case getLeaderboard

    var path: String {
        switch self {
        case .login:                    return "/auth/login"
        case .register:                 return "/auth/register"
        case .signInWithApple:          return "/auth/apple"
        case .signInWithGoogle:         return "/auth/google"
        case .getMe, .updateMe, .deleteMe: return "/users/me"
        case .reportPresence:           return "/users/me/presence"
        case .searchUsers(let q):
            return queryPath("/users/search", [URLQueryItem(name: "q", value: q)])
        case .registerDeviceToken, .clearDeviceToken: return "/users/device-token"
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
        case .leaveSession(let id):     return "/sessions/\(id)/leave"
        case .updateSessionMetadata(let id, _): return "/sessions/\(id)/metadata"
        case .setCoLockReady(let id, _): return "/sessions/\(id)/co-lock/ready"
        case .requestCoLockRelease(let id): return "/sessions/\(id)/co-lock/release"
        case .approveCoLockRelease(let id): return "/sessions/\(id)/co-lock/release/approve"
        case .listSessionPhotos(let id), .uploadSessionPhoto(let id, _): return "/sessions/\(id)/photos"
        case .deleteSessionPhoto(let id, let photoID): return "/sessions/\(id)/photos/\(photoID)"
        case .reportProximityExit(let id): return "/sessions/\(id)/proximity-exit"
        case .reportJailbreak(let id, _): return "/sessions/\(id)/jailbreaks"
        case .reportShieldAttempt(let id, _): return "/sessions/\(id)/shield-attempt"
        case .getRecap(let id):         return "/sessions/\(id)/recap"
        case .listFriends, .addFriend:  return "/friends"
        case .removeFriend(let id):     return "/friends/\(id)"
        case .acceptFriend(let id):     return "/friends/\(id)/accept"
        case .rejectFriend(let id):     return "/friends/\(id)/reject"
        case .acceptFriendRequest(let id): return "/friends/requests/\(id)/accept"
        case .rejectFriendRequest(let id): return "/friends/requests/\(id)/reject"
        case .nudgeFriend(let id):      return "/friends/\(id)/nudge"
        case .incomingFriendRequests:   return "/friends/requests/incoming"
        case .outgoingFriendRequests:   return "/friends/requests/outgoing"
        case .getFriendProfile(let id): return "/friends/\(id)/profile"
        case .getLeaderboard:           return "/friends/leaderboard"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .login, .register, .signInWithApple, .signInWithGoogle,
             .createSession, .addFriend, .joinSession, .joinSessionCode, .startSession, .endSession,
             .leaveSession, .setCoLockReady, .requestCoLockRelease, .approveCoLockRelease,
             .uploadSessionPhoto, .reportProximityExit, .reportJailbreak, .reportShieldAttempt,
             .acceptFriend, .rejectFriend, .acceptFriendRequest, .rejectFriendRequest, .nudgeFriend,
             .blockUser, .reportUser, .reportPresence:
            return .post
        case .registerDeviceToken:
            return .put
        case .getMe, .getStats, .getMyMedals, .getMedalCatalog, .listSessions, .sessionHistory, .getSession, .getRecap,
             .listSessionPhotos,
             .listFriends, .incomingFriendRequests, .outgoingFriendRequests,
             .getFriendProfile, .getLeaderboard,
             .searchUsers, .listBlocks:
            return .get
        case .updateMe, .updateSessionMetadata:
            return .patch
        case .removeFriend, .deleteMe, .unblockUser, .clearDeviceToken, .deleteSessionPhoto:
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
        case .reportPresence(let r):    return r
        case .reportUser(_, let r):     return r
        case .createSession(let r):     return r
        case .updateSessionMetadata(_, let r): return r
        case .setCoLockReady(_, let r): return r
        case .uploadSessionPhoto(_, let r): return r
        case .reportJailbreak(_, let r): return r
        case .reportShieldAttempt(_, let r): return r
        case .addFriend(let r):         return r
        case .startSession:             return StartSessionRequest()
        default:                        return nil
        }
    }

    private func queryPath(_ path: String, _ items: [URLQueryItem]) -> String {
        var comps = URLComponents()
        comps.path = path
        comps.queryItems = items
        return comps.string ?? path
    }
}
