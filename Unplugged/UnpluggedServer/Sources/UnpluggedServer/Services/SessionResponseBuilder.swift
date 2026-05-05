import Fluent
import Foundation
import UnpluggedShared
import Vapor

enum SessionResponseBuilder {
    static func build(session: SessionModel, db: Database, includePhotos: Bool = true) async throws -> SessionResponse {
        guard let response = try await build(sessions: [session], db: db, includePhotos: includePhotos).first else {
            throw Abort(.internalServerError)
        }
        return response
    }

    static func build(sessions: [SessionModel], db: Database, includePhotos: Bool = true) async throws -> [SessionResponse] {
        let sessionIDs = try sessions.map { try $0.requireID() }
        guard !sessionIDs.isEmpty else { return [] }

        let members = try await MemberModel.query(on: db)
            .filter(\.$sessionID ~~ sessionIDs)
            .all()
        let membersBySession = Dictionary(grouping: members, by: \.sessionID)

        let users = try await UserVisibilityService.visibleUsers(members.map(\.userID), on: db)
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        let approvals = try await CoLockReleaseApprovalModel.query(on: db)
            .filter(\.$sessionID ~~ sessionIDs)
            .all()
        let approvalsBySession = Dictionary(grouping: approvals, by: \.sessionID)

        let photosBySession: [UUID: [SessionMemoryPhotoResponse]]
        if includePhotos {
            let photos = try await SessionMemoryPhotoModel.query(on: db)
                .filter(\.$sessionID ~~ sessionIDs)
                .sort(\.$createdAt, .ascending)
                .all()
            photosBySession = Dictionary(grouping: photos, by: \.sessionID)
                .mapValues { $0.compactMap(photoResponse) }
        } else {
            photosBySession = [:]
        }

        return try sessions.map { session in
            let sessionID = try session.requireID()
            let sessionMembers = membersBySession[sessionID] ?? []
            return SessionResponse(
                session: try makeSessionDTO(
                    session: session,
                    members: sessionMembers,
                    approvals: approvalsBySession[sessionID] ?? []
                ),
                participants: participantResponses(
                    session: session,
                    members: sessionMembers,
                    userMap: userMap
                ),
                memoryPhotos: photosBySession[sessionID] ?? []
            )
        }
    }

    static func makeSessionDTO(session: SessionModel, members: [MemberModel], db: Database) async throws -> UnpluggedShared.Session {
        let sessionID = try session.requireID()
        let approvals = try await CoLockReleaseApprovalModel.query(on: db)
            .filter(\.$sessionID == sessionID)
            .all()
        return try makeSessionDTO(session: session, members: members, approvals: approvals)
    }

    static func makeSessionDTO(
        session: SessionModel,
        members: [MemberModel],
        approvals: [CoLockReleaseApprovalModel]
    ) throws -> UnpluggedShared.Session {
        let sessionID = try session.requireID()
        let state: RoomState
        if session.endedAt != nil {
            state = .ended
        } else if session.lockedAt != nil {
            state = .locked
        } else {
            state = .idle
        }

        return UnpluggedShared.Session(
            id: sessionID,
            code: session.code ?? legacySessionCode(for: sessionID),
            hostID: session.roomOwner,
            state: state,
            title: session.title,
            description: session.description,
            durationSeconds: session.durationSeconds,
            lockMode: session.lockMode,
            startedAt: session.startTime,
            lockedAt: session.lockedAt,
            endsAt: session.endsAt,
            endedAt: session.endedAt,
            latitude: session.latitude,
            longitude: session.longitude,
            coLockStatus: try coLockStatus(session: session, members: members, approvals: approvals)
        )
    }

    static func participantResponses(session: SessionModel, members: [MemberModel], db: Database) async throws -> [ParticipantResponse] {
        let users = try await UserVisibilityService.visibleUsers(members.map(\.userID), on: db)
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        return participantResponses(session: session, members: members, userMap: userMap)
    }

    static func participantResponses(
        session: SessionModel,
        members: [MemberModel],
        userMap: [UUID: UserModel]
    ) -> [ParticipantResponse] {
        return members.compactMap { member in
            guard let memberID = member.id,
                  let user = userMap[member.userID] else { return nil }
            return ParticipantResponse(
                id: memberID,
                userID: member.userID,
                username: user.username,
                status: member.participantStatus,
                joinedAt: member.joinedAt,
                isHost: session.lockMode == .coLock ? false : member.userID == session.roomOwner
            )
        }
    }

    static func photoResponses(sessionID: UUID, db: Database) async throws -> [SessionMemoryPhotoResponse] {
        let photos = try await SessionMemoryPhotoModel.query(on: db)
            .filter(\.$sessionID == sessionID)
            .sort(\.$createdAt, .ascending)
            .all()
        return photos.compactMap(photoResponse)
    }

    static func photoResponse(_ photo: SessionMemoryPhotoModel) -> SessionMemoryPhotoResponse? {
        guard let id = photo.id else { return nil }
        return SessionMemoryPhotoResponse(
            id: id,
            sessionID: photo.sessionID,
            uploaderID: photo.uploaderID,
            mimeType: photo.mimeType,
            byteCount: photo.imageData.count,
            thumbnailData: photo.thumbnailData,
            createdAt: photo.createdAt ?? Date()
        )
    }

    static func legacySessionCode(for sessionID: UUID) -> String {
        String(sessionID.uuidString
            .filter { $0.isLetter || $0.isNumber }
            .prefix(InputValidation.sessionCodeLength))
            .uppercased()
    }

    private static func coLockStatus(session: SessionModel, members: [MemberModel], db: Database) async throws -> SessionCoLockStatus? {
        let sessionID = try session.requireID()
        let approvals = try await CoLockReleaseApprovalModel.query(on: db)
            .filter(\.$sessionID == sessionID)
            .all()
        return try coLockStatus(session: session, members: members, approvals: approvals)
    }

    private static func coLockStatus(
        session: SessionModel,
        members: [MemberModel],
        approvals: [CoLockReleaseApprovalModel]
    ) throws -> SessionCoLockStatus? {
        guard session.lockMode == .coLock else { return nil }
        let activeMembers = members.filter { $0.participantStatus == .active }
        let requesterID = approvals.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }.first?.requesterID
        return SessionCoLockStatus(
            requiredApprovals: activeMembers.count,
            startReadyUserIDs: activeMembers.filter(\.coLockReady).map(\.userID),
            releaseRequestedBy: requesterID,
            releaseApprovalUserIDs: approvals.map(\.approverID)
        )
    }
}
