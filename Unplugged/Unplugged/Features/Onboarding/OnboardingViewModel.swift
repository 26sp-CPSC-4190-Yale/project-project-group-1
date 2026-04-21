//
//  OnboardingViewModel.swift
//  Unplugged.Features.Onboarding
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case welcome
        case ageGate
        case notifications
        case proximity
        case screenTime
        case emergencyApps
    }

    nonisolated private static let stepKey = "onboarding.currentStep"
    nonisolated private static let completedKey = "onboarding.completed"

    var currentStep: Step {
        didSet { UserDefaults.standard.set(currentStep.rawValue, forKey: Self.stepKey) }
    }
    var notificationsGranted = false
    var proximityPrimed = false
    var screenTimeGranted = false
    var screenTimeAuthFailed = false
    var emergencyAllowlistSelected = false

    // §23 / COPPA: require the user to confirm they're 13+ before any account
    // is created. `.underThirteen` is a terminal state — the UI refuses to
    // advance and shows a polite "not available" message. Confirmation is
    // persisted so reopening the app doesn't re-prompt, but a single "no"
    // locks the device out of onboarding completion.
    enum AgeGateState: Int {
        case unanswered = 0
        case overThirteen = 1
        case underThirteen = 2
    }
    var ageGateState: AgeGateState = .unanswered

    nonisolated private static let ageGateKey = "onboarding.ageGate"

    init() {
        // §48: resume from the last step the user reached. If they force-quit
        // during onboarding (phone ringing, App Switcher kill), picking back up
        // where they left off is less jarring than restarting from the welcome
        // screen. Permission-granted flags stay at their defaults — we
        // re-check system state on-screen rather than trusting persisted bools.
        let raw = UserDefaults.standard.object(forKey: Self.stepKey) as? Int
        self.currentStep = raw.flatMap(Step.init(rawValue:)) ?? .welcome
        let gateRaw = UserDefaults.standard.object(forKey: Self.ageGateKey) as? Int
        self.ageGateState = gateRaw.flatMap(AgeGateState.init(rawValue:)) ?? .unanswered
    }

    nonisolated static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    func markCompleted() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        UserDefaults.standard.removeObject(forKey: Self.stepKey)
    }

    func advance() {
        if currentStep == .ageGate, ageGateState != .overThirteen { return }
        if let next = Step(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    func setAgeGate(_ state: AgeGateState) {
        ageGateState = state
        UserDefaults.standard.set(state.rawValue, forKey: Self.ageGateKey)
    }

    func back() {
        if let prev = Step(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }

    /// Prime the Local Network permission prompt by briefly starting MultipeerConnectivity.
    /// Without this, the first real pairing attempt silently fails because the user has
    /// never been prompted for Local Network access. NearbyInteraction (UWB) permission
    /// is prompted lazily on first `NISession.run(...)`; we can't pre-prompt that one,
    /// so the onboarding copy sets expectations.
    func primeProximityPermissions(touchTips: TouchTipsService) async {
        await touchTips.primeLocalNetworkPermission()
        proximityPrimed = true
    }

    func requestNotifications() async {
        do {
            notificationsGranted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            notificationsGranted = false
        }
    }

    func requestScreenTime(service: ScreenTimeService) async {
        screenTimeAuthFailed = false
        guard service.isAvailable else {
            // Free dev plan or simulator — degrade gracefully.
            screenTimeGranted = false
            screenTimeAuthFailed = true
            return
        }
        do {
            try await service.requestAuthorization()
            screenTimeGranted = service.isAuthorized
            if !screenTimeGranted {
                screenTimeAuthFailed = true
            }
        } catch {
            screenTimeGranted = false
            screenTimeAuthFailed = true
        }
    }
}
