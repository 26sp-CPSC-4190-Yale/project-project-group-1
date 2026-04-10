//
//  ScreenTimePermissionView.swift
//  Unplugged.Features.Onboarding
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

struct ScreenTimePermissionView: View {
    let screenTime: ScreenTimeService
    var onDone: () -> Void

    @State private var viewModel = ScreenTimePermissionViewModel()

    var body: some View {
        VStack(spacing: .spacingMd) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(.tertiaryColor)

            Text("Emergency apps")
                .font(.titleFont)
                .foregroundColor(.tertiaryColor)

            Text("Pick the apps that should stay available during a session — Phone, Messages, Maps, your hospital app, anything you need in an emergency.")
                .font(.bodyFont)
                .foregroundColor(.tertiaryColor.opacity(0.7))
                .multilineTextAlignment(.center)

            if !screenTime.isAvailable {
                Text("Screen Time is unavailable on this device, so there's nothing to pick here. You can continue.")
                    .font(.captionFont)
                    .foregroundColor(.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Button("Pick Emergency Apps") {
                    viewModel.showPicker = true
                }
                .buttonStyle(PrimaryButtonStyle())

                if viewModel.didConfirm {
                    Label("Selection saved", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.tertiaryColor)
                        .font(.captionFont)
                }
            }
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $viewModel.showPicker, selection: $viewModel.selection)
        .onChange(of: viewModel.showPicker) { _, isShowing in
            if !isShowing {
                viewModel.confirmSelection(service: screenTime)
                onDone()
            }
        }
        #endif
    }
}
