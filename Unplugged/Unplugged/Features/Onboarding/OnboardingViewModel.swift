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

        // denied pages are conditional branches, not progress milestones
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
        // resume from last step, re-check system state rather than trusting persisted permission bools
        let raw = UserDefaults.standard.object(forKey: Self.stepKey) as? Int
        let didMigrateAgeGate = UserDefaults.standard.bool(forKey: Self.ageGateRemovalMigrationKey)
        let didMigrateDeniedSteps = UserDefaults.standard.bool(forKey: Self.deniedStepsMigrationKey)

        if let raw, !didMigrateAgeGate {
            // first migration, 6-step with ageGate to 5-step without
            let migrated = Self.migratedStepRemovingAgeGate(from: raw)
            self.currentStep = Self.migratedStepAddingDeniedPages(from: migrated)
            UserDefaults.standard.set(currentStep.rawValue, forKey: Self.stepKey)
            UserDefaults.standard.set(true, forKey: Self.ageGateRemovalMigrationKey)
            UserDefaults.standard.set(true, forKey: Self.deniedStepsMigrationKey)
        } else if let raw, !didMigrateDeniedSteps {
            // second migration, add proximityDenied and screenTimeDenied pages to the 5-step enum
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
            if proximityPermissionStatus == .denied {
                currentStep = .proximityDenied
            } else {
                currentStep = .screenTime
            }
        case .proximityDenied:
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
            currentStep = .proximity
        case .screenTimeDenied:
            currentStep = .screenTime
        case .screenTime:
            currentStep = .proximity
        default:
            if let prev = Step(rawValue: currentStep.rawValue - 1) {
                currentStep = prev
            }
        }
    }

    // NI/UWB permission cannot be pre-prompted, it only fires on NISession.run, onboarding copy sets expectations
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
            // status can lag via KVO after requestAuthorization returns, do not route to the warning page on an immediate false read
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
        switch raw {
        case 0:      return 0
        case 1, 2:   return 1  // ageGate collapsed into notifications
        case 3:      return 2
        case 4:      return 3
        case 5:      return 4
        default:     return 0
        }
    }

    private nonisolated static func migratedStepAddingDeniedPages(from raw: Int) -> Step {
        // denied pages are never resume targets, remap to the parent permission step so the user re-prompts
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
