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
                    ForEach(OnboardingViewModel.Step.allCases, id: \.self) { step in
                        Circle()
                            .fill(step == viewModel.currentStep ? Color.tertiaryColor : Color.tertiaryColor.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, .spacingLg)

                Spacer()

                // Step content
                Group {
                    switch viewModel.currentStep {
                    case .welcome:       welcomeStep
                    case .ageGate:       ageGateStep
                    case .notifications: notificationsStep
                    case .proximity:     proximityStep
                    case .screenTime:    screenTimeStep
                    case .emergencyApps: emergencyAppsStep
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

    private var ageGateStep: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "person.fill.checkmark")
                .font(.system(size: 64))
                .foregroundStyle(Color.tertiaryColor)

            VStack(spacing: .spacingMd) {
                Text("Quick Check")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                Text("Unplugged is for ages 13 and up. Are you at least 13 years old?")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: .spacingSm) {
                Button {
                    viewModel.setAgeGate(.overThirteen)
                } label: {
                    Text("Yes, I'm 13 or older")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(viewModel.ageGateState == .overThirteen ? Color.tertiaryColor.opacity(0.6) : Color.tertiaryColor)
                        .foregroundStyle(Color.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    viewModel.setAgeGate(.underThirteen)
                } label: {
                    Text("No, I'm under 13")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.tertiaryColor.opacity(0.4), lineWidth: 1)
                        )
                        .foregroundStyle(Color.tertiaryColor)
                }
            }

            if viewModel.ageGateState == .underThirteen {
                Text("Sorry — Unplugged isn't available for users under 13. Ask a parent or guardian to review our Terms of Service.")
                    .font(.caption)
                    .foregroundStyle(Color.destructiveColor)
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

            Button("Enable Notifications") {
                Task { await viewModel.requestNotifications() }
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.tertiaryColor)
            .foregroundStyle(Color.primaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                Text("To join a friend's room, hold your phones back-to-back — about 4 inches apart. iOS will ask for Local Network and Nearby Interaction access; both are required for proximity pairing.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.primeProximityPermissions(touchTips: deps.touchTips) }
            } label: {
                Text(viewModel.proximityPrimed ? "Allowed" : "Allow Nearby")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(viewModel.proximityPrimed ? Color.tertiaryColor.opacity(0.5) : Color.tertiaryColor)
                    .foregroundStyle(Color.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.proximityPrimed)

            Text("You can still join rooms by entering a 6-character code if proximity isn't available.")
                .font(.caption)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                .multilineTextAlignment(.center)
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

            if !deps.screenTime.isAvailable {
                Text("Screen Time is unavailable on this device. You can still use Unplugged, but apps won't be blocked.")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Button("Allow Screen Time") {
                    Task { await viewModel.requestScreenTime(service: deps.screenTime) }
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.tertiaryColor)
                .foregroundStyle(Color.primaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if viewModel.screenTimeAuthFailed {
                    Text("Couldn't get Screen Time permission. Check that restrictions aren't enabled. You can skip this step.")
                        .font(.caption)
                        .foregroundStyle(Color.destructiveColor)
                        .multilineTextAlignment(.center)
                }
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

    private var continueDisabled: Bool {
        // Age gate is the only hard block. Other steps all accept "continue"
        // so users can skip optional permissions.
        viewModel.currentStep == .ageGate && viewModel.ageGateState != .overThirteen
    }

    private var footer: some View {
        HStack {
            if viewModel.currentStep != .welcome {
                Button("Back") { viewModel.back() }
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
            }
            Spacer()
            Button {
                if viewModel.currentStep == .emergencyApps {
                    viewModel.markCompleted()
                    onFinish()
                } else {
                    viewModel.advance()
                }
            } label: {
                Text(viewModel.currentStep == .emergencyApps ? "Get Started" : "Continue")
                    .fontWeight(.semibold)
                    .padding(.horizontal, .spacingLg)
                    .padding(.vertical, 12)
                    .background(continueDisabled ? Color.tertiaryColor.opacity(0.3) : Color.tertiaryColor)
                    .foregroundStyle(Color.primaryColor)
                    .clipShape(Capsule())
            }
            .disabled(continueDisabled)
        }
        .padding(.bottom, .spacingLg)
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environment(DependencyContainer())
}
