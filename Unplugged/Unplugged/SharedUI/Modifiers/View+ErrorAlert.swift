import SwiftUI

extension View {
    func errorAlert(_ error: Binding<String?>) -> some View {
        self.alert(
            "Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            ),
            actions: { Button("OK", role: .cancel) { error.wrappedValue = nil } },
            message: { 
                if let errorMessage = error.wrappedValue {
                    Text(errorMessage)
                }
            }
        )
    }
}
