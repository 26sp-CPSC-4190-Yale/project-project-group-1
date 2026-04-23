//
//  UnpluggedTests.swift
//  UnpluggedTests
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Testing
@testable import Unplugged

struct UnpluggedTests {

    @Test func lockedProximityTransitionReasonsPreserveLastDistance() async throws {
        #expect(!TouchTipsService.shouldEmitLockedNoDistance(for: "monitor_started"))
        #expect(!TouchTipsService.shouldEmitLockedNoDistance(for: "mc_connecting"))
        #expect(!TouchTipsService.shouldEmitLockedNoDistance(for: "ni_update_without_distance"))

        #expect(TouchTipsService.shouldEmitLockedNoDistance(for: "mc_notConnected"))
        #expect(TouchTipsService.shouldEmitLockedNoDistance(for: "ni_invalidated"))
    }

    @Test func lockedProximityStaleWindowOutlastsLeaveCountdown() async throws {
        #expect(LockedSessionProximityPolicy.staleReadingInterval > TimeInterval(LockedSessionProximityPolicy.gracePeriodSeconds))
        #expect(LockedSessionProximityPolicy.staleRecoveryInterval > LockedSessionProximityPolicy.staleReadingInterval)
    }

    @MainActor
    @Test func onboardingAgeGateRemovalMigration() async throws {
        let defaults = UserDefaults.standard
        let stepKey = "onboarding.currentStep"
        let migrationKey = "onboarding.ageGateRemovedMigrationDone"
        let deniedMigrationKey = "onboarding.deniedStepsMigrationDone"
        let originalStep = defaults.object(forKey: stepKey)
        let originalMigration = defaults.object(forKey: migrationKey)
        let originalDeniedMigration = defaults.object(forKey: deniedMigrationKey)
        defer {
            restore(originalStep, forKey: stepKey, in: defaults)
            restore(originalMigration, forKey: migrationKey, in: defaults)
            restore(originalDeniedMigration, forKey: deniedMigrationKey, in: defaults)
        }

        defaults.set(1, forKey: stepKey)
        defaults.removeObject(forKey: migrationKey)

        let ageGateViewModel = OnboardingViewModel()

        #expect(ageGateViewModel.currentStep == .notifications)
        #expect(defaults.bool(forKey: migrationKey))

        defaults.set(4, forKey: stepKey)
        defaults.removeObject(forKey: migrationKey)

        let oldScreenTimeViewModel = OnboardingViewModel()

        #expect(oldScreenTimeViewModel.currentStep == .screenTime)
        #expect(defaults.integer(forKey: stepKey) == OnboardingViewModel.Step.screenTime.rawValue)

        defaults.removeObject(forKey: stepKey)
        defaults.removeObject(forKey: migrationKey)
        _ = OnboardingViewModel()

        defaults.set(OnboardingViewModel.Step.proximity.rawValue, forKey: stepKey)
        let freshInstallViewModel = OnboardingViewModel()

        #expect(freshInstallViewModel.currentStep == .proximity)
    }

    @MainActor
    @Test func onboardingAdvanceSkipsWarningPagesWhenPermissionsAreGranted() async throws {
        let defaults = UserDefaults.standard
        let stepKey = "onboarding.currentStep"
        let ageGateMigrationKey = "onboarding.ageGateRemovedMigrationDone"
        let deniedMigrationKey = "onboarding.deniedStepsMigrationDone"
        let originalStep = defaults.object(forKey: stepKey)
        let originalAgeGateMigration = defaults.object(forKey: ageGateMigrationKey)
        let originalDeniedMigration = defaults.object(forKey: deniedMigrationKey)
        defer {
            restore(originalStep, forKey: stepKey, in: defaults)
            restore(originalAgeGateMigration, forKey: ageGateMigrationKey, in: defaults)
            restore(originalDeniedMigration, forKey: deniedMigrationKey, in: defaults)
        }

        defaults.set(true, forKey: ageGateMigrationKey)
        defaults.set(true, forKey: deniedMigrationKey)
        defaults.set(OnboardingViewModel.Step.proximity.rawValue, forKey: stepKey)

        let viewModel = OnboardingViewModel()

        viewModel.proximityPermissionStatus = .granted
        viewModel.advance()

        #expect(viewModel.currentStep == .screenTime)

        viewModel.screenTimePermissionStatus = .granted
        viewModel.advance()

        #expect(viewModel.currentStep == .emergencyApps)
    }

    @MainActor
    @Test func onboardingAdvanceShowsWarningPagesWhenPermissionsAreDenied() async throws {
        let defaults = UserDefaults.standard
        let stepKey = "onboarding.currentStep"
        let ageGateMigrationKey = "onboarding.ageGateRemovedMigrationDone"
        let deniedMigrationKey = "onboarding.deniedStepsMigrationDone"
        let originalStep = defaults.object(forKey: stepKey)
        let originalAgeGateMigration = defaults.object(forKey: ageGateMigrationKey)
        let originalDeniedMigration = defaults.object(forKey: deniedMigrationKey)
        defer {
            restore(originalStep, forKey: stepKey, in: defaults)
            restore(originalAgeGateMigration, forKey: ageGateMigrationKey, in: defaults)
            restore(originalDeniedMigration, forKey: deniedMigrationKey, in: defaults)
        }

        defaults.set(true, forKey: ageGateMigrationKey)
        defaults.set(true, forKey: deniedMigrationKey)
        defaults.set(OnboardingViewModel.Step.proximity.rawValue, forKey: stepKey)

        let viewModel = OnboardingViewModel()

        viewModel.proximityPermissionStatus = .denied
        viewModel.advance()

        #expect(viewModel.currentStep == .proximityDenied)

        viewModel.advance()

        #expect(viewModel.currentStep == .screenTime)

        viewModel.screenTimePermissionStatus = .denied
        viewModel.advance()

        #expect(viewModel.currentStep == .screenTimeDenied)

        viewModel.advance()

        #expect(viewModel.currentStep == .emergencyApps)
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
