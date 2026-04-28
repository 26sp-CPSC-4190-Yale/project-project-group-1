import SwiftUI
import WidgetKit

@main
struct UnpluggedLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LockedSessionLiveActivity()
    }
}
