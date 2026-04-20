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
        VStack(spacing: .spacingLg) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.tertiaryColor)

            VStack(spacing: .spacingMd) {
                Text("Emergency Apps")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                Text("Pick the apps that should stay available during a session — Phone, Messages, Maps, anything you need in an emergency.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            if !screenTime.isAvailable {
                Text("Screen Time is unavailable on this device, so there's nothing to pick here. You can continue.")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Button("Pick Emergency Apps") {
                    viewModel.showPicker = true
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.tertiaryColor)
                .foregroundStyle(Color.primaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if viewModel.didConfirm {
                    Label("Selection saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.tertiaryColor)
                        .font(.caption)
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
