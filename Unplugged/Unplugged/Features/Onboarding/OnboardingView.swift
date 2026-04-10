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

            VStack(spacing: .spacingLg) {
                Spacer()
                switch viewModel.currentStep {
                case .welcome:       welcomeStep
                case .notifications: notificationsStep
                case .screenTime:    screenTimeStep
                case .emergencyApps: emergencyAppsStep
                }
                Spacer()
                footer
            }
            .padding(.horizontal, .spacingXl)
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: .spacingMd) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 72))
                .foregroundColor(.tertiaryColor)
            Text("UNPLUGGED")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.tertiaryColor)
                .tracking(2)
            Text("Put your phone down together. When a host starts a room, every member's phone is locked except for emergency apps.")
                .font(.bodyFont)
                .foregroundColor(.tertiaryColor.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private var notificationsStep: some View {
        VStack(spacing: .spacingMd) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundColor(.tertiaryColor)
            Text("Stay in sync")
                .font(.titleFont)
                .foregroundColor(.tertiaryColor)
            Text("Unplugged uses notifications to let you know when a friend starts a room and when your session ends.")
                .font(.bodyFont)
                .foregroundColor(.tertiaryColor.opacity(0.7))
                .multilineTextAlignment(.center)

            Button("Enable Notifications") {
                Task { await viewModel.requestNotifications() }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var screenTimeStep: some View {
        VStack(spacing: .spacingMd) {
            Image(systemName: "hourglass")
                .font(.system(size: 64))
                .foregroundColor(.tertiaryColor)
            Text("Allow Screen Time")
                .font(.titleFont)
                .foregroundColor(.tertiaryColor)
            Text("Unplugged uses Apple's Screen Time API to shield apps during your session. We never see what you use — iOS handles the block locally.")
                .font(.bodyFont)
                .foregroundColor(.tertiaryColor.opacity(0.7))
                .multilineTextAlignment(.center)

            if !deps.screenTime.isAvailable {
                Text("Screen Time is unavailable on this device. You can still use Unplugged, but apps won't be blocked during sessions.")
                    .font(.captionFont)
                    .foregroundColor(.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Button("Allow Screen Time") {
                    Task { await viewModel.requestScreenTime(service: deps.screenTime) }
                }
                .buttonStyle(PrimaryButtonStyle())
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
                    .foregroundColor(.tertiaryColor)
            }
            Spacer()
            Button(viewModel.currentStep == .emergencyApps ? "Done" : "Next") {
                if viewModel.currentStep == .emergencyApps {
                    viewModel.markCompleted()
                    onFinish()
                } else {
                    viewModel.advance()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.bottom, .spacingLg)
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environment(DependencyContainer())
}
