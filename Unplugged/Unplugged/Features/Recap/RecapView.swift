import CoreLocation
import SwiftUI
import PhotosUI
import UIKit
import UnpluggedShared

struct RecapView: View {
    let sessionID: UUID
    var onDone: (() -> Void)? = nil

    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RecapViewModel()
    @State private var selectedMemoryPhoto: PhotosPickerItem?
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var isUploadingPhoto = false
    @State private var isPreparingShareCard = false
    @State private var shareSheetItem: ShareSheetItem?
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
                        if attemptedBreakoutCount(for: recap) > 0 {
                            attemptedBreakouts(for: recap)
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
        .photosPicker(isPresented: $showingPhotoLibrary, selection: $selectedMemoryPhoto, matching: .images)
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView(
                onCapture: { image in
                    showingCamera = false
                    Task { await uploadCapturedMemoryPhoto(image) }
                },
                onCancel: {
                    showingCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $shareSheetItem) { item in
            ShareSheet(items: [item.url])
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
            if recap.durationSeconds == nil {
                StatBadge(
                    value: TimeInterval(recap.actualFocusedSeconds).humanReadable,
                    label: "Locked In",
                    valueSize: 22
                )
            } else {
                StatBadge(
                    value: plannedDurationLabel(for: recap),
                    label: "Planned",
                    valueSize: 22
                )
            }
            StatBadge(
                value: "\(recap.participants.count)",
                label: "Members",
                valueSize: 22
            )
            StatBadge(
                value: "\(attemptedBreakoutCount(for: recap))",
                label: "Attempted Breakouts",
                valueSize: 22
            )
            if recap.durationSeconds != nil {
                StatBadge(
                    value: "\(Int((recap.completionRate * 100).rounded()))%",
                    label: "Completion",
                    valueSize: 22
                )
            }
        }
    }

    private func actionRow(for recap: SessionRecapResponse) -> some View {
        Button {
            Task { await prepareShareCard(for: recap) }
        } label: {
            HStack(spacing: .spacingSm) {
                if isPreparingShareCard {
                    ProgressView()
                        .tint(.tertiaryColor)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isPreparingShareCard ? "Preparing Share Card" : "Share Card")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(isPreparingShareCard)
    }

    private func mementoEditor(for recap: SessionRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            HStack {
                Text("Add to Share Card")
                    .font(.headlineFont)
                    .foregroundColor(.tertiaryColor)
                Spacer()
                if isSavingMemento || isUploadingPhoto {
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

                Menu {
                    Button {
                        showingPhotoLibrary = true
                    } label: {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }

                    if Self.isCameraAvailable {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                        }
                    }
                } label: {
                    Label(isUploadingPhoto ? "Uploading" : "Add Photo", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isUploadingPhoto)
            }

            if canAddFreshLocation {
                mementoToggleRows()
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

    private func mementoToggleRows() -> some View {
        VStack(spacing: .spacingSm) {
            mementoToggleRow(
                title: "Location",
                subtitle: "Adds a map image to the share card",
                systemImage: "location.fill",
                isOn: Binding(
                    get: { includeLocation },
                    set: { setLocationIncluded($0) }
                )
            )
        }
    }

    private func mementoToggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.tertiaryColor)
                    Text(subtitle)
                        .font(.captionFont)
                        .foregroundStyle(Color.tertiaryColor.opacity(0.58))
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.secondaryColor)
                    .frame(width: 22)
            }
        }
        .toggleStyle(.switch)
        .tint(Color.secondaryColor)
        .disabled(isSavingMemento)
        .padding(.horizontal, .spacingMd)
        .padding(.vertical, 10)
        .background(Color.primaryColor.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusSm))
    }

    private func setLocationIncluded(_ newValue: Bool) {
        let previous = includeLocation
        includeLocation = newValue
        Task {
            let saved = await saveLocationPreference(newValue)
            if !saved {
                includeLocation = previous
            }
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

    private func attemptedBreakouts(for recap: SessionRecapResponse) -> some View {
        let entries = attemptedBreakoutEntries(for: recap)

        return VStack(alignment: .leading, spacing: .spacingSm) {
            HStack {
                Text("Attempted Breakouts")
                    .font(.headlineFont)
                    .foregroundColor(.tertiaryColor)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.tertiaryColor.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.surfaceColor)
                    .clipShape(Capsule())
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.username)
                        .font(.bodyFont)
                        .foregroundColor(.tertiaryColor)
                    if let reason = entry.reason {
                        Text(jailbreakReasonLabel(reason))
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

    private func attemptedBreakoutEntries(for recap: SessionRecapResponse) -> [JailbreakEntry] {
        recap.jailbreaks.filter { $0.reason == SessionExitReason.shieldActionAttempt }
    }

    private func attemptedBreakoutCount(for recap: SessionRecapResponse) -> Int {
        attemptedBreakoutEntries(for: recap).count
    }

    private var canAddFreshLocation: Bool {
        onDone != nil
    }

    private func plannedDurationLabel(for recap: SessionRecapResponse) -> String {
        guard let duration = recap.durationSeconds else { return "Unlimited" }
        return TimeInterval(duration).humanReadable
    }

    private func jailbreakReasonLabel(_ reason: String) -> String {
        switch reason {
        case SessionExitReason.leftVoluntarily:
            return "Left the room"
        case SessionExitReason.leftDueToProximity:
            return "Moved too far away"
        case SessionExitReason.screenTimeAuthorizationCleared:
            return "Cleared Screen Time permission"
        case SessionExitReason.shieldActionAttempt:
            return "Attempted breakout"
        default:
            return reason
                .split(separator: "_")
                .map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }
                .joined(separator: " ")
        }
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

    private func uploadCapturedMemoryPhoto(_ image: UIImage) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            guard let upload = Self.makeUploadPayload(from: image) else {
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
    }

    private func initializeMementoIfNeeded(from recap: SessionRecapResponse) {
        guard !didInitializeMemento else { return }
        mementoDescription = recap.description ?? ""
        includeLocation = recap.latitude != nil && recap.longitude != nil
        didInitializeMemento = true
    }

    private func saveDescription(for recap: SessionRecapResponse) async {
        let coordinate = includeLocation ? coordinate(from: recap) : nil
        await saveMemento(location: coordinate, notice: nil)
    }

    private func saveLocationPreference(_ enabled: Bool) async -> Bool {
        if enabled {
            do {
                let snapshot = try await deps.location.mementoSnapshot(requestPermissionIfNeeded: true)
                return await saveMemento(
                    location: snapshot.coordinate,
                    notice: "Location added."
                )
            } catch {
                viewModel.error = Self.errorMessage(for: error)
                return false
            }
        }

        return await saveMemento(
            location: nil,
            notice: "Location removed."
        )
    }

    @discardableResult
    private func saveMemento(
        location: CLLocationCoordinate2D?,
        notice: String?
    ) async -> Bool {
        guard !isSavingMemento else { return false }
        isSavingMemento = true
        defer { isSavingMemento = false }

        do {
            _ = try await deps.sessions.updateMetadata(
                id: sessionID,
                description: normalizedDescription,
                location: location
            )
            mementoNotice = notice
            await viewModel.load(sessionID: sessionID, service: deps.recap)
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

    private func coordinate(from recap: SessionRecapResponse?) -> CLLocationCoordinate2D? {
        guard let recap else { return nil }
        return coordinate(from: recap)
    }

    private func prepareShareCard(for recap: SessionRecapResponse) async {
        guard !isPreparingShareCard else { return }
        isPreparingShareCard = true
        defer { isPreparingShareCard = false }

        do {
            try? await Task.sleep(nanoseconds: 80_000_000)
            let data = try await ShareRecapImageRenderer.renderPNGData(for: recap)
            let url = try await Self.writeShareCardPNG(data, sessionID: recap.sessionID)
            shareSheetItem = ShareSheetItem(url: url)
        } catch {
            viewModel.error = "Couldn't prepare share card."
        }
    }

    private static func writeShareCardPNG(_ data: Data, sessionID: UUID) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("UnpluggedShareCards", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("unplugged-\(sessionID.uuidString).png")
            try data.write(to: url, options: .atomic)
            return url
        }.value
    }

    private static func errorMessage(for error: Error) -> String {
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? "Couldn't update memento." : message
    }

    private static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
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

private struct ShareSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = controller.view
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
