import SwiftUI
import PhotosUI
import UIKit
import UnpluggedShared

struct RecapView: View {
    let sessionID: UUID
    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RecapViewModel()
    @State private var selectedMemoryPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: .spacingLg) {
                    header(for: viewModel.recap)

                    if let recap = viewModel.recap {
                        ShareRecapCard(recap: recap)
                        actionRow(for: recap)
                        if let description = recap.description, !description.isEmpty {
                            textCard(title: "Description", value: description)
                        }
                        if let latitude = recap.latitude, let longitude = recap.longitude {
                            SessionMapView(latitude: latitude, longitude: longitude)
                        }
                        if !recap.memoryPhotos.isEmpty {
                            memoryPhotos(recap.memoryPhotos)
                        }
                        stats(for: recap)
                        participants(for: recap)
                        if !recap.jailbreaks.isEmpty {
                            jailbreaks(for: recap)
                        }
                    } else if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, .spacingXl)
                    } else if let error = viewModel.error {
                        Text(error)
                            .font(.bodyFont)
                            .foregroundColor(.tertiaryColor.opacity(0.7))
                            .padding(.top, .spacingXl)
                    }
                }
                .padding(.horizontal, .spacingLg)
                .padding(.vertical, .spacingLg)
            }
        }
        .task { await viewModel.load(sessionID: sessionID, service: deps.recap) }
        .onChange(of: selectedMemoryPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await uploadMemoryPhoto(newItem) }
        }
    }

    @ViewBuilder
    private func header(for recap: SessionRecapResponse?) -> some View {
        VStack(spacing: .spacingSm) {
            Image(systemName: (recap?.endedEarly ?? false)
                  ? "clock.badge.exclamationmark.fill"
                  : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.tertiaryColor)

            if let recap {
                Text(TimeInterval(recap.actualFocusedSeconds).humanReadable)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.tertiaryColor)
                    .monospacedDigit()
            }

            Text("Time Locked In")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor.opacity(0.8))

            if let recap, recap.endedEarly {
                Text("Ended early — \(plannedDurationLabel(for: recap)) planned")
                    .font(.captionFont)
                    .foregroundColor(.destructiveColor)
                    .padding(.horizontal, .spacingMd)
                    .padding(.vertical, 4)
                    .background(Color.destructiveColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if let title = recap?.title {
                Text(title)
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor.opacity(0.7))
            }
        }
        .padding(.top, .spacingXl)
    }

    private func stats(for recap: SessionRecapResponse) -> some View {
        HStack(spacing: .spacingMd) {
            StatBadge(
                value: plannedDurationLabel(for: recap),
                label: "Planned",
                valueSize: 22
            )
            StatBadge(
                value: "\(recap.participants.count)",
                label: "Members",
                valueSize: 22
            )
            StatBadge(
                value: "\(Int((recap.completionRate * 100).rounded()))%",
                label: "Completion",
                valueSize: 22
            )
        }
    }

    private func actionRow(for recap: SessionRecapResponse) -> some View {
        HStack(spacing: .spacingSm) {
            ShareLink(item: shareText(for: recap)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            PhotosPicker(selection: $selectedMemoryPhoto, matching: .images) {
                Label(isUploadingPhoto ? "Uploading" : "Add Photo", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isUploadingPhoto)
        }
    }

    private func participants(for recap: SessionRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Text("Who was here")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)

            ForEach(recap.participants) { participant in
                HStack(spacing: .spacingMd) {
                    ParticipantAvatar(name: participant.username, size: 40)
                    Text(participant.username)
                        .font(.bodyFont)
                        .foregroundColor(.tertiaryColor)
                    Spacer()
                    if participant.isHost {
                        Text("Host")
                            .font(.captionFont)
                            .foregroundColor(.tertiaryColor.opacity(0.6))
                    }
                }
                .padding(.spacingMd)
                .background(Color.surfaceColor)
                .cornerRadius(.cornerRadiusSm)
            }
        }
    }

    private func jailbreaks(for recap: SessionRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Text("Breaks from focus")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)

            ForEach(recap.jailbreaks) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.username)
                        .font(.bodyFont)
                        .foregroundColor(.tertiaryColor)
                    if let reason = entry.reason {
                        Text(reason)
                            .font(.captionFont)
                            .foregroundColor(.tertiaryColor.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.spacingMd)
                .background(Color.surfaceColor)
                .cornerRadius(.cornerRadiusSm)
            }
        }
    }

    private func plannedDurationLabel(for recap: SessionRecapResponse) -> String {
        guard let duration = recap.durationSeconds else { return "Unlimited" }
        return TimeInterval(duration).humanReadable
    }

    private func textCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Text(title)
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)
            Text(value)
                .font(.bodyFont)
                .foregroundColor(.tertiaryColor.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .cornerRadius(.cornerRadiusSm)
    }

    private func memoryPhotos(_ photos: [SessionMemoryPhotoResponse]) -> some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Text("Memories")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacingSm) {
                    ForEach(photos) { photo in
                        if let data = photo.thumbnailData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusSm))
                                .clipped()
                        }
                    }
                }
            }
        }
    }

    private func shareText(for recap: SessionRecapResponse) -> String {
        let title = recap.title ?? "Unplugged Session"
        let duration = TimeInterval(recap.actualFocusedSeconds).humanReadable
        return "I locked in for \(duration) on Unplugged: \(title)"
    }

    private func uploadMemoryPhoto(_ item: PhotosPickerItem) async {
        isUploadingPhoto = true
        defer {
            isUploadingPhoto = false
            selectedMemoryPhoto = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let upload = Self.makeUploadPayload(from: image) else {
                return
            }
            _ = try await deps.sessions.uploadPhoto(
                id: sessionID,
                imageData: upload.imageData,
                thumbnailData: upload.thumbnailData,
                mimeType: "image/jpeg"
            )
            await viewModel.load(sessionID: sessionID, service: deps.recap)
        } catch {
            viewModel.error = "Couldn't upload photo."
        }
    }

    private static func makeUploadPayload(from image: UIImage) -> (imageData: Data, thumbnailData: Data?)? {
        let full = resizedJPEGData(from: image, maxPixel: 1_400, maxBytes: InputValidation.maxPhotoBytes)
        let thumbnail = resizedJPEGData(from: image, maxPixel: 320, maxBytes: InputValidation.maxPhotoThumbnailBytes)
        guard let full else { return nil }
        return (full, thumbnail)
    }

    private static func resizedJPEGData(from image: UIImage, maxPixel: CGFloat, maxBytes: Int) -> Data? {
        let size = image.size
        let scale = min(1, maxPixel / max(size.width, size.height))
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        for quality in stride(from: 0.82, through: 0.42, by: -0.1) {
            if let data = rendered.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        guard let fallback = rendered.jpegData(compressionQuality: 0.35), fallback.count <= maxBytes else {
            return nil
        }
        return fallback
    }
}
