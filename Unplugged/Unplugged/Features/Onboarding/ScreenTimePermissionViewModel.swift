//
//  ScreenTimePermissionViewModel.swift
//  Unplugged.Features.Onboarding
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
#if canImport(FamilyControls)
import FamilyControls
#endif

@MainActor
@Observable
final class ScreenTimePermissionViewModel {
    #if canImport(FamilyControls)
    var selection = FamilyActivitySelection()
    #endif
    var showPicker = false
    var didConfirm = false

    func confirmSelection(service: ScreenTimeService) {
        #if canImport(FamilyControls)
        if let data = try? PropertyListEncoder().encode(selection) {
            service.setEmergencyAllowlist(data)
        }
        #endif
        didConfirm = true
    }
}
