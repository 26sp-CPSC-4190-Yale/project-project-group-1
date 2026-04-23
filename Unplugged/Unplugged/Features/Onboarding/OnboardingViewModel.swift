//
//  OnboardingViewModel.swift
//  Unplugged.Features.Onboarding
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class OnboardingViewModel {
    enum PermissionPromptStatus: Equatable {
        case notStarted
        case requesting
        case granted
        case denied
        case unavailable
    }

    enum Step: Int, CaseIterable {
        case welcome
        case notifications
        case proximity
        case proximityDenied
        case screenTime
        case screenTimeDenied
        case emergencyApps

        /// Steps shown as progress dots — denied pages are conditional branches,
        /// not distinct progress milestones.
        static var progressSteps: [Step] {
            [.welcome, .notifications, .proximity, .screenTime, .emergencyApps]
        }
    }

    nonisolated private static let stepKey = "onboarding.currentStep"
    nonisolated private static let completedKey = "onboarding.completed"
    nonisolated private static let ageGateRemovalMigrationKey = "onboarding.ageGateRemovedMigrationDone"
    nonisolated private static let deniedStepsMigrationKey = "onboarding.deniedStepsMigrationDone"

    var currentStep: Step {
        didSet { UserDefaults.standard.set(currentStep.rawValue, forKey: Self.stepKey) }
    }
    var notificationsGranted = false
    var proximityPrimed = false
    var screenTimeGranted = false
    var screenTimeAuthFailed = false
    var emergencyAllowlistSelected = false
    var notificationPermissionStatus: PermissionPromptStatus = .notStarted
    var proximityPermissionStatus: PermissionPromptStatus = .notStarted
    var screenTimePermissionStatus: PermissionPromptStatus = .notStarted

    init() {
        // §48: resume from the last step the user reached. If they force-quit
        // during onboarding (phone ringing, App Switcher kill), picking back up
        // where they left off is less jarring than restarting from the welcome
        // screen. Permission-granted flags stay at their defaults — we
        // re-check system state on-screen rather than trusting persisted bools.
        let raw = UserDefaults.standard.object(forKey: Self.stepKey) as? Int
        let didMigrateAgeGate = UserDefaults.standard.bool(forKey: Self.ageGateRemovalMigrationKey)
        let didMigrateDeniedSteps = UserDefaults.standard.bool(forKey: Self.deniedStepsMigrationKey)

        if let raw, !didMigrateAgeGate {
            // First migration: remap the old 6-step enum (with ageGate) to the
            // 5-step enum (without ageGate), then fall through to the denied-steps
            // migration below.
            let migrated = Self.migratedStepRemovingAgeGate(from: raw)
            self.currentStep = Self.migratedStepAddingDeniedPages(from: migrated)
            UserDefaults.standard.set(currentStep.rawValue, forKey: Self.stepKey)
            UserDefaults.standard.set(true, forKey: Self.ageGateRemovalMigrationKey)
            UserDefaults.standard.set(true, forKey: Self.deniedStepsMigrationKey)
        } else if let raw, !didMigrateDeniedSteps {
            // Second migration: remap the old 5-step enum (post-ageGate) to the
            // new 7-step enum that includes proximityDenied and screenTimeDenied.
            // Old: 0=welcome, 1=notifications, 2=proximity, 3=screenTime, 4=emergencyApps
            // New: 0=welcome, 1=notifications, 2=proximity, 3=proximityDenied,
            //      4=screenTime, 5=screenTimeDenied, 6=emergencyApps
            self.currentStep = Self.migratedStepAddingDeniedPages(from: raw)
            UserDefaults.standard.set(currentStep.rawValue, forKey: Self.stepKey)
            UserDefaults.standard.set(true, forKey: Self.deniedStepsMigrationKey)
        } else {
            self.currentStep = raw.flatMap(Step.init(rawValue:)) ?? .welcome
            if !didMigrateAgeGate {
                UserDefaults.standard.set(true, forKey: Self.ageGateRemovalMigrationKey)
            }
            if !didMigrateDeniedSteps {
                UserDefaults.standard.set(true, forKey: Self.deniedStepsMigrationKey)
            }
        }
    }

    nonisolated static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    func markCompleted() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        UserDefaults.standard.removeObject(forKey: Self.stepKey)
    }

    func advance() {
        switch currentStep {
        case .proximity:
            // Route to the denied explanation page if permission was denied.
            if proximityPermissionStatus == .denied {
                currentStep = .proximityDenied
            } else {
                currentStep = .screenTime
            }
        case .proximityDenied:
            // Skip straight to the next real permission step.
            currentStep = .screenTime
        case .screenTime:
            if screenTimePermissionStatus == .denied || screenTimePermissionStatus == .unavailable {
                currentStep = .screenTimeDenied
            } else {
                currentStep = .emergencyApps
            }
        case .screenTimeDenied:
            currentStep = .emergencyApps
        default:
            if let next = Step(rawValue: currentStep.rawValue + 1) {
                currentStep = next
            }
        }
    }

    func back() {
        switch currentStep {
        case .proximityDenied:
            // Go back to the proximity permission step, not the raw previous.
            currentStep = .proximity
        case .screenTimeDenied:
            currentStep = .screenTime
        case .screenTime:
            // Skip over proximityDenied if it was never visited.
            currentStep = .proximity
        default:
            if let prev = Step(rawValue: currentStep.rawValue - 1) {
                currentStep = prev
            }
        }
    }

    /// Prime the Local Network permission prompt before the first real pairing attempt.
    /// Without this, the first real pairing attempt silently fails because the user has
    /// never been prompted for Local Network access. NearbyInteraction (UWB) permission
    /// is prompted lazily on first `NISession.run(...)`; we can't pre-prompt that one,
    /// so the onboarding copy sets expectations.
    func primeProximityPermissions(touchTips: TouchTipsService) async -> Bool {
        if proximityPermissionStatus == .requesting { return false }
        if proximityPrimed {
            proximityPermissionStatus = .granted
            return true
        }

        proximityPermissionStatus = .requesting
        let allowed = await touchTips.primeLocalNetworkPermission()
        proximityPrimed = allowed
        proximityPermissionStatus = allowed ? .granted : .denied
        return allowed
    }

    func requestNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsGranted = true
            notificationPermissionStatus = .granted
            registerForRemoteNotifications()
            return true
        case .denied:
            notificationsGranted = false
            notificationPermissionStatus = .denied
            return false
        case .notDetermined:
            break
        @unknown default:
            notificationsGranted = false
            notificationPermissionStatus = .denied
            return false
        }

        notificationPermissionStatus = .requesting
        do {
            notificationsGranted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notificationPermissionStatus = notificationsGranted ? .granted : .denied
            if notificationsGranted {
                registerForRemoteNotifications()
            }
            return notificationsGranted
        } catch {
            AppLogger.onboarding.error("UNUserNotificationCenter.requestAuthorization threw", error: error)
            notificationsGranted = false
            notificationPermissionStatus = .denied
            return false
        }
    }

    func requestScreenTime(service: ScreenTimeService) async -> Bool {
        screenTimeAuthFailed = false
        guard service.isAvailable else {
            // Free dev plan or simulator — degrade gracefully.
            screenTimeGranted = false
            screenTimePermissionStatus = .unavailable
            return false
        }

        if service.isAuthorized {
            screenTimeGranted = true
            screenTimePermissionStatus = .granted
            return true
        }

        screenTimePermissionStatus = .requesting
        do {
            try await service.requestAuthorization()
            // requestAuthorization() returns without throwing when the user approves.
            // AuthorizationCenter.shared.authorizationStatus can lag behind via KVO,
            // so do not route to the warning page based on an immediate false read.
            screenTimeGranted = true
            screenTimePermissionStatus = .granted
            return true
        } catch {
            AppLogger.onboarding.warning("screen time authorization request denied/failed", context: ["error": String(describing: error)])
            screenTimeGranted = false
            screenTimePermissionStatus = .denied
            screenTimeAuthFailed = true
            return false
        }
    }

    private func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    private nonisolated static func migratedStepRemovingAgeGate(from raw: Int) -> Int {
        // Old 6-step enum: 0=welcome, 1=ageGate, 2=notifications, 3=proximity,
        // 4=screenTime, 5=emergencyApps.
        // Intermediate 5-step: 0=welcome, 1=notifications, 2=proximity,
        // 3=screenTime, 4=emergencyApps.
        switch raw {
        case 0:      return 0  // welcome
        case 1, 2:   return 1  // notifications (ageGate collapsed into notifications)
        case 3:      return 2  // proximity
        case 4:      return 3  // screenTime
        case 5:      return 4  // emergencyApps
        default:     return 0  // welcome fallback
        }
    }

    private nonisolated static func migratedStepAddingDeniedPages(from raw: Int) -> Step {
        // Intermediate 5-step: 0=welcome, 1=notifications, 2=proximity,
        // 3=screenTime, 4=emergencyApps.
        // New 7-step: 0=welcome, 1=notifications, 2=proximity, 3=proximityDenied,
        // 4=screenTime, 5=screenTimeDenied, 6=emergencyApps.
        // Denied pages are never persisted as resume targets — remap to the
        // parent permission step so the user re-prompts.
        switch raw {
        case 0:  return .welcome
        case 1:  return .notifications
        case 2:  return .proximity
        case 3:  return .screenTime
        case 4:  return .emergencyApps
        default: return .welcome
        }
    }
}
