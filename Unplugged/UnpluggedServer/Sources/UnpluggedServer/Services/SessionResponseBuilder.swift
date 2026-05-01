import Fluent
import Foundation
import UnpluggedShared
import Vapor

enum SessionResponseBuilder {
    static func build(room: RoomModel, db: Database, includePhotos: Bool = true) async throws -> SessionResponse {
        guard let response = try await build(rooms: [room], db: db, includePhotos: includePhotos).first else {
            throw Abort(.internalServerError)
        }
        return response
    }

    static func build(rooms: [RoomModel], db: Database, includePhotos: Bool = true) async throws -> [SessionResponse] {
        let roomIDs = try rooms.map { try $0.requireID() }
        guard !roomIDs.isEmpty else { return [] }

        let members = try await MemberModel.query(on: db)
            .filter(\.$roomID ~~ roomIDs)
            .all()
        let membersByRoom = Dictionary(grouping: members, by: \.roomID)

        let users = try await UserVisibilityService.visibleUsers(members.map(\.userID), on: db)
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        let approvals = try await CoLockReleaseApprovalModel.query(on: db)
            .filter(\.$roomID ~~ roomIDs)
            .all()
        let approvalsByRoom = Dictionary(grouping: approvals, by: \.roomID)

        let photosByRoom: [UUID: [SessionMemoryPhotoResponse]]
        if includePhotos {
            let photos = try await SessionMemoryPhotoModel.query(on: db)
                .filter(\.$sessionID ~~ roomIDs)
                .sort(\.$createdAt, .ascending)
                .all()
            photosByRoom = Dictionary(grouping: photos, by: \.sessionID)
                .mapValues { $0.compactMap(photoResponse) }
        } else {
            photosByRoom = [:]
        }

        return try rooms.map { room in
            let roomID = try room.requireID()
            let roomMembers = membersByRoom[roomID] ?? []
            return SessionResponse(
                session: try session(
                    room: room,
                    members: roomMembers,
                    approvals: approvalsByRoom[roomID] ?? []
                ),
                participants: participantResponses(
                    room: room,
                    members: roomMembers,
                    userMap: userMap
                ),
                memoryPhotos: photosByRoom[roomID] ?? []
            )
        }
    }

    static func session(room: RoomModel, members: [MemberModel], db: Database) async throws -> UnpluggedShared.Session {
        let roomID = try room.requireID()
        let approvals = try await CoLockReleaseApprovalModel.query(on: db)
            .filter(\.$roomID == roomID)
            .all()
        return try session(room: room, members: members, approvals: approvals)
    }

    static func session(
        room: RoomModel,
        members: [MemberModel],
        approvals: [CoLockReleaseApprovalModel]
    ) throws -> UnpluggedShared.Session {
        let roomID = try room.requireID()
        let state: RoomState
        if room.endedAt != nil {
            state = .ended
        } else if room.lockedAt != nil {
            state = .locked
        } else {
            state = .idle
        }

        return UnpluggedShared.Session(
            id: roomID,
            code: room.code ?? legacyRoomCode(for: roomID),
            hostID: room.roomOwner,
            state: state,
            title: room.title,
            description: room.description,
            durationSeconds: room.durationSeconds,
            lockMode: room.lockMode,
            startedAt: room.startTime,
            lockedAt: room.lockedAt,
            endsAt: room.endsAt,
            endedAt: room.endedAt,
            latitude: room.latitude,
            longitude: room.longitude,
            weather: weather(from: room),
            coLockStatus: try coLockStatus(room: room, members: members, approvals: approvals)
        )
    }

    static func participantResponses(room: RoomModel, members: [MemberModel], db: Database) async throws -> [ParticipantResponse] {
        let users = try await UserVisibilityService.visibleUsers(members.map(\.userID), on: db)
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        return participantResponses(room: room, members: members, userMap: userMap)
    }

    static func participantResponses(
        room: RoomModel,
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
                isHost: room.lockMode == .coLock ? false : member.userID == room.roomOwner
            )
        }
    }

    static func photoResponses(roomID: UUID, db: Database) async throws -> [SessionMemoryPhotoResponse] {
        let photos = try await SessionMemoryPhotoModel.query(on: db)
            .filter(\.$sessionID == roomID)
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

    static func weather(from room: RoomModel) -> SessionWeatherSnapshot? {
        guard let summary = room.weatherSummary,
              let capturedAt = room.weatherCapturedAt else {
            return nil
        }
        return SessionWeatherSnapshot(
            summary: summary,
            temperatureFahrenheit: room.weatherTemperatureF,
            conditionSymbol: room.weatherSymbol,
            capturedAt: capturedAt
        )
    }

    static func apply(weather: SessionWeatherSnapshot?, to room: RoomModel) {
        room.weatherSummary = weather?.summary
        room.weatherTemperatureF = weather?.temperatureFahrenheit
        room.weatherSymbol = weather?.conditionSymbol
        room.weatherCapturedAt = weather?.capturedAt
    }

    static func legacyRoomCode(for roomID: UUID) -> String {
        String(roomID.uuidString
            .filter { $0.isLetter || $0.isNumber }
            .prefix(InputValidation.sessionCodeLength))
            .uppercased()
    }

    private static func coLockStatus(room: RoomModel, members: [MemberModel], db: Database) async throws -> SessionCoLockStatus? {
        let roomID = try room.requireID()
        let approvals = try await CoLockReleaseApprovalModel.query(on: db)
            .filter(\.$roomID == roomID)
            .all()
        return try coLockStatus(room: room, members: members, approvals: approvals)
    }

    private static func coLockStatus(
        room: RoomModel,
        members: [MemberModel],
        approvals: [CoLockReleaseApprovalModel]
    ) throws -> SessionCoLockStatus? {
        guard room.lockMode == .coLock else { return nil }
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
