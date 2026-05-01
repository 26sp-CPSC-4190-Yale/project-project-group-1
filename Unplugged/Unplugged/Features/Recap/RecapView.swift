import CoreLocation
import CoreTransferable
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import UnpluggedShared

struct RecapView: View {
    let sessionID: UUID
    var onDone: (() -> Void)? = nil

    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RecapViewModel()
    @State private var selectedMemoryPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var renderedShareCard: RenderedShareCard?
    @State private var mementoDescription = ""
    @State private var includeLocation = false
    @State private var didInitializeMemento = false
    @State private var isSavingMemento = false
    @State private var mementoNotice: String?

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
                        mementoEditor(for: recap)
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
        .safeAreaInset(edge: .top) {
            if onDone != nil {
                HStack {
                    Spacer()
                    Button("Done") {
                        onDone?()
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(Color.tertiaryColor)
                    .padding(.horizontal, .spacingLg)
                    .padding(.vertical, .spacingSm)
                }
                .background(Color.primaryColor.opacity(0.95))
            }
        }
        .errorAlert($viewModel.error)
        .task { await loadRecap() }
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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacingMd) {
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
                value: "\(recap.jailbreaks.count)",
                label: "Breaks",
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
            if let renderedShareCard {
                ShareLink(
                    item: renderedShareCard.item,
                    preview: SharePreview(
                        recap.title ?? "Unplugged Session",
                        image: Image(uiImage: renderedShareCard.preview)
                    )
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {} label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(true)
            }

            PhotosPicker(selection: $selectedMemoryPhoto, matching: .images) {
                Label(isUploadingPhoto ? "Uploading" : "Add Photo", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isUploadingPhoto)
        }
    }

    private func mementoEditor(for recap: SessionRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            HStack {
                Text("Memento")
                    .font(.headlineFont)
                    .foregroundColor(.tertiaryColor)
                Spacer()
                if isSavingMemento {
                    ProgressView()
                        .tint(.tertiaryColor)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $mementoDescription)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 86, maxHeight: 120)
                    .foregroundStyle(Color.tertiaryColor)
                    .tint(Color.tertiaryColor)
                    .padding(10)

                if mementoDescription.isEmpty {
                    Text("Add a note")
                        .foregroundStyle(Color.tertiaryColor.opacity(0.35))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.primaryColor.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusSm))

            HStack(spacing: .spacingSm) {
                Button {
                    Task { await saveDescription(for: recap) }
                } label: {
                    Label("Save Note", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSavingMemento)

                locationToggle()
            }

            if let mementoNotice {
                Label(mementoNotice, systemImage: "info.circle")
                    .font(.captionFont)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius))
        .onAppear {
            initializeMementoIfNeeded(from: recap)
        }
    }

    private func locationToggle() -> some View {
        Toggle(isOn: Binding(
            get: { includeLocation },
            set: { newValue in
                let previous = includeLocation
                includeLocation = newValue
                Task {
                    let saved = await saveLocationPreference(newValue)
                    if !saved {
                        includeLocation = previous
                    }
                }
            }
        )) {
            Label("Location & Weather", systemImage: "location.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .toggleStyle(.button)
        .tint(includeLocation ? Color.secondaryColor : Color.surfaceColor)
        .disabled(isSavingMemento)
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
                viewModel.error = "Couldn't read that photo."
                return
            }
            _ = try await deps.sessions.uploadPhoto(
                id: sessionID,
                imageData: upload.imageData,
                thumbnailData: upload.thumbnailData,
                mimeType: "image/jpeg"
            )
            await loadRecap()
        } catch {
            viewModel.error = "Couldn't upload photo."
        }
    }

    private func loadRecap() async {
        await viewModel.load(sessionID: sessionID, service: deps.recap)
        guard let recap = viewModel.recap else { return }
        initializeMementoIfNeeded(from: recap)
        renderShareCard(for: recap)
    }

    private func initializeMementoIfNeeded(from recap: SessionRecapResponse) {
        guard !didInitializeMemento else { return }
        mementoDescription = recap.description ?? ""
        includeLocation = recap.latitude != nil && recap.longitude != nil
        didInitializeMemento = true
    }

    private func saveDescription(for recap: SessionRecapResponse) async {
        let coordinate = includeLocation ? coordinate(from: recap) : nil
        let weather = includeLocation ? recap.weather : nil
        await saveMemento(location: coordinate, weather: weather, notice: nil)
    }

    private func saveLocationPreference(_ enabled: Bool) async -> Bool {
        if enabled {
            do {
                let snapshot = try await deps.location.mementoSnapshot(requestPermissionIfNeeded: true)
                return await saveMemento(
                    location: snapshot.coordinate,
                    weather: snapshot.weather,
                    notice: snapshot.warning
                )
            } catch {
                viewModel.error = Self.errorMessage(for: error)
                return false
            }
        }

        return await saveMemento(location: nil, weather: nil, notice: "Location and weather removed.")
    }

    @discardableResult
    private func saveMemento(
        location: CLLocationCoordinate2D?,
        weather: SessionWeatherSnapshot?,
        notice: String?
    ) async -> Bool {
        guard !isSavingMemento else { return false }
        isSavingMemento = true
        defer { isSavingMemento = false }

        do {
            _ = try await deps.sessions.updateMetadata(
                id: sessionID,
                description: normalizedDescription,
                location: location,
                weather: weather
            )
            mementoNotice = notice
            await viewModel.load(sessionID: sessionID, service: deps.recap)
            if let recap = viewModel.recap {
                renderShareCard(for: recap)
            }
            return true
        } catch {
            viewModel.error = "Couldn't save memento."
            return false
        }
    }

    private var normalizedDescription: String? {
        let trimmed = mementoDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func coordinate(from recap: SessionRecapResponse) -> CLLocationCoordinate2D? {
        guard let latitude = recap.latitude, let longitude = recap.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func renderShareCard(for recap: SessionRecapResponse) {
        let renderer = ImageRenderer(
            content: ShareRecapCard(recap: recap)
                .frame(width: 390)
                .padding(24)
                .background(Color.primaryColor)
        )
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            renderedShareCard = nil
            return
        }
        renderedShareCard = RenderedShareCard(
            item: ShareRecapCardImage(data: data),
            preview: image
        )
    }

    private static func errorMessage(for error: Error) -> String {
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? "Couldn't update location and weather." : message
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

private struct RenderedShareCard {
    let item: ShareRecapCardImage
    let preview: UIImage
}

private struct ShareRecapCardImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            card.data
        }
    }
}
