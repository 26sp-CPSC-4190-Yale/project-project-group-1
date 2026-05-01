import MapKit
import SwiftUI

struct SessionMapView: View {
    let latitude: Double
    let longitude: Double

    private var region: Binding<MKCoordinateRegion> {
        .constant(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
    }

    var body: some View {
        Map(coordinateRegion: region)
            .allowsHitTesting(false)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: .cornerRadius))
            .overlay(alignment: .center) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.destructiveColor)
                    .shadow(radius: 2)
            }
    }
}
