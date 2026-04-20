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
        case notifications
        case screenTime
        case emergencyApps
    }

    var currentStep: Step = .welcome
    var notificationsGranted = false
    var screenTimeGranted = false
    var screenTimeAuthFailed = false
    var emergencyAllowlistSelected = false

    nonisolated static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: "onboarding.completed")
    }

    func markCompleted() {
        UserDefaults.standard.set(true, forKey: "onboarding.completed")
    }

    func advance() {
        if let next = Step(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    func back() {
        if let prev = Step(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
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
