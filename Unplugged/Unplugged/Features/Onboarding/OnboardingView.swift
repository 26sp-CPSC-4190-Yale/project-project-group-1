//
//  OnboardingView.swift
//  Unplugged.Features.Onboarding
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = OnboardingViewModel()
    var onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(OnboardingViewModel.Step.progressSteps, id: \.self) { step in
                        Circle()
                            .fill(isProgressDotActive(step) ? Color.tertiaryColor : Color.tertiaryColor.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, .spacingLg)

                Spacer()

                // Step content
                Group {
                    switch viewModel.currentStep {
                    case .welcome:         welcomeStep
                    case .notifications:   notificationsStep
                    case .proximity:       proximityStep
                    case .proximityDenied: proximityDeniedStep
                    case .screenTime:      screenTimeStep
                    case .screenTimeDenied: screenTimeDeniedStep
                    case .emergencyApps:   emergencyAppsStep
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                Spacer()

                // Footer
                footer
            }
            .padding(.horizontal, .spacingXl)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
        }
        .task(id: viewModel.currentStep) {
            await handleStepEntry(viewModel.currentStep)
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 72))
                .foregroundStyle(Color.tertiaryColor)

            VStack(spacing: .spacingMd) {
                Text("UNPLUGGED")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.tertiaryColor)
                    .tracking(2)

                Text("Put your phone down together. When a host starts a room, every member's phone is locked except for emergency apps.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var notificationsStep: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.tertiaryColor)

            VStack(spacing: .spacingMd) {
                Text("Stay in Sync")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                Text("Get notified when friends start a room and when your session ends.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            permissionStatusView(
                status: viewModel.notificationPermissionStatus,
                waitingText: "iOS will ask if Unplugged can send notifications.",
                grantedText: "Notifications enabled.",
                deniedText: "Notifications are off. This may hinder your app experience — you won't know when sessions start or end."
            )

            if viewModel.notificationPermissionStatus == .denied {
                Text("To enable later, go to:\nSettings → Notifications → Unplugged")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var proximityStep: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(Color.tertiaryColor)

            VStack(spacing: .spacingMd) {
                Text("Pair by Proximity")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                // Be explicit about the distance so users don't expect "same room"
                // pairing. The UWB gate requires phones pressed together (~10 cm).
                Text("To join a friend's room, hold your phones back-to-back — about 4 inches apart. iOS will ask for Local Network access before your first proximity pair.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            permissionStatusView(
                status: viewModel.proximityPermissionStatus,
                waitingText: "iOS may ask for Local Network access.",
                grantedText: "Local Network access granted.",
                deniedText: "Local Network access was denied."
            )

            Text("You can still join rooms by entering a 6-character code if proximity isn't available.")
                .font(.caption)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    private var proximityDeniedStep: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(Color.destructiveColor)

            VStack(spacing: .spacingMd) {
                Text("Proximity Pairing Unavailable")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                Text("Without Local Network access, you won't be able to pair with friends by bringing your phones together. You can still join rooms using a 6-character code.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)

                Text("To enable proximity pairing later, go to:\nSettings → Privacy & Security → Local Network → Unplugged")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.spacingMd)
                    .background(Color.surfaceColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var screenTimeStep: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "hourglass")
                .font(.system(size: 64))
                .foregroundStyle(Color.tertiaryColor)

            VStack(spacing: .spacingMd) {
                Text("Screen Time Access")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                Text("Unplugged uses Apple's Screen Time API to shield apps during your session. We never see what you use — iOS handles the block locally.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            permissionStatusView(
                status: viewModel.screenTimePermissionStatus,
                waitingText: "iOS will ask for Screen Time access.",
                grantedText: "Screen Time access granted.",
                deniedText: "Screen Time permission was denied.",
                unavailableText: "Screen Time is unavailable on this device."
            )

            if viewModel.screenTimeAuthFailed {
                Text("Check that Screen Time restrictions aren't enabled.")
                    .font(.caption)
                    .foregroundStyle(Color.destructiveColor)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var screenTimeDeniedStep: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.destructiveColor)

            VStack(spacing: .spacingMd) {
                Text("App Locking Unavailable")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                Text("Without Screen Time access, Unplugged can't lock apps during your session. The room will still work, but your phone won't be blocked.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)

                Text("This significantly reduces the effectiveness of Unplugged sessions.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.destructiveColor.opacity(0.8))
                    .multilineTextAlignment(.center)

                Text("To enable later, go to:\nSettings → Screen Time → Unplugged")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.spacingMd)
                    .background(Color.surfaceColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var emergencyAppsStep: some View {
        ScreenTimePermissionView(
            screenTime: deps.screenTime,
            onDone: { viewModel.emergencyAllowlistSelected = true }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if viewModel.currentStep != .welcome {
                Button("Back") { viewModel.back() }
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .disabled(isWaitingForPermission)
            }
            Spacer()
            if showsPrimaryFooterButton {
                Button {
                    if viewModel.currentStep == .emergencyApps {
                        viewModel.markCompleted()
                        onFinish()
                    } else {
                        viewModel.advance()
                    }
                } label: {
                    Text(primaryFooterTitle)
                        .fontWeight(.semibold)
                        .padding(.horizontal, .spacingLg)
                        .padding(.vertical, 12)
                        .background(Color.tertiaryColor)
                        .foregroundStyle(Color.primaryColor)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
            }
        }
        .padding(.bottom, .spacingLg)
    }

    private var showsPrimaryFooterButton: Bool {
        switch viewModel.currentStep {
        case .welcome, .emergencyApps, .proximityDenied, .screenTimeDenied:
            true
        case .notifications, .proximity, .screenTime:
            false
        }
    }

    private var primaryFooterTitle: String {
        switch viewModel.currentStep {
        case .welcome:
            "Get Started"
        case .emergencyApps:
            "Get Started"
        case .proximityDenied, .screenTimeDenied:
            "Continue Anyway"
        default:
            "Continue"
        }
    }

    private var isWaitingForPermission: Bool {
        switch viewModel.currentStep {
        case .notifications:
            viewModel.notificationPermissionStatus == .notStarted ||
                viewModel.notificationPermissionStatus == .requesting
        case .proximity:
            viewModel.proximityPermissionStatus == .notStarted ||
                viewModel.proximityPermissionStatus == .requesting
        case .screenTime:
            viewModel.screenTimePermissionStatus == .notStarted ||
                viewModel.screenTimePermissionStatus == .requesting
        case .welcome, .emergencyApps, .proximityDenied, .screenTimeDenied:
            false
        }
    }

    @MainActor
    private func handleStepEntry(_ step: OnboardingViewModel.Step) async {
        switch step {
        case .welcome, .emergencyApps, .proximityDenied, .screenTimeDenied:
            return
        case .notifications:
            switch viewModel.notificationPermissionStatus {
            case .notStarted:
                guard await waitBeforePromptIfNeeded(true) else { return }
                _ = await viewModel.requestNotifications()
                await pauseThenAdvanceIfStillCurrent(step)
            case .requesting:
                return
            case .granted, .denied, .unavailable:
                await pauseThenAdvanceIfStillCurrent(step)
            }
        case .proximity:
            switch viewModel.proximityPermissionStatus {
            case .notStarted:
                guard await waitBeforePromptIfNeeded(true) else { return }
                _ = await viewModel.primeProximityPermissions(touchTips: deps.touchTips)
                await pauseThenAdvanceIfStillCurrent(step)
            case .requesting:
                return
            case .granted, .denied, .unavailable:
                await pauseThenAdvanceIfStillCurrent(step)
            }
        case .screenTime:
            switch viewModel.screenTimePermissionStatus {
            case .notStarted:
                guard await waitBeforePromptIfNeeded(true) else { return }
                _ = await viewModel.requestScreenTime(service: deps.screenTime)
                await pauseThenAdvanceIfStillCurrent(step)
            case .requesting:
                return
            case .granted, .denied, .unavailable:
                await pauseThenAdvanceIfStillCurrent(step)
            }
        }
    }

    private func waitBeforePromptIfNeeded(_ shouldWait: Bool) async -> Bool {
        guard shouldWait else { return true }
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    @MainActor
    private func advanceIfStillCurrent(_ step: OnboardingViewModel.Step) {
        guard !Task.isCancelled, viewModel.currentStep == step else { return }
        viewModel.advance()
    }

    @MainActor
    private func pauseThenAdvanceIfStillCurrent(_ step: OnboardingViewModel.Step) async {
        // Brief pause so the user sees the granted/denied status before
        // the page transitions.
        try? await Task.sleep(nanoseconds: 600_000_000)
        advanceIfStillCurrent(step)
    }

    /// Maps the current step to its progress-dot milestone so that denied
    /// sub-pages light up the same dot as the parent permission step.
    private func isProgressDotActive(_ dotStep: OnboardingViewModel.Step) -> Bool {
        let current = viewModel.currentStep
        switch current {
        case .proximityDenied: return dotStep == .proximity
        case .screenTimeDenied: return dotStep == .screenTime
        default: return dotStep == current
        }
    }

    @ViewBuilder
    private func permissionStatusView(
        status: OnboardingViewModel.PermissionPromptStatus,
        waitingText: String,
        grantedText: String,
        deniedText: String,
        unavailableText: String? = nil
    ) -> some View {
        switch status {
        case .notStarted, .requesting:
            HStack(spacing: .spacingSm) {
                ProgressView()
                    .tint(Color.tertiaryColor)
                Text(waitingText)
            }
            .permissionStatusStyle(color: Color.tertiaryColor.opacity(0.7))
        case .granted:
            Label(grantedText, systemImage: "checkmark.circle.fill")
                .permissionStatusStyle(color: Color.tertiaryColor)
        case .denied:
            Label(deniedText, systemImage: "exclamationmark.circle.fill")
                .permissionStatusStyle(color: Color.destructiveColor)
        case .unavailable:
            Label(unavailableText ?? deniedText, systemImage: "info.circle.fill")
                .permissionStatusStyle(color: Color.tertiaryColor.opacity(0.7))
        }
    }
}

private extension View {
    func permissionStatusStyle(color: Color) -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, .spacingMd)
            .padding(.vertical, 12)
            .background(Color.tertiaryColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environment(DependencyContainer())
}
