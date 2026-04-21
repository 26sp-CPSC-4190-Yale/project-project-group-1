import Foundation

public enum ProximityConstants {
    /// Distance (meters) at which two phones are considered "touched" for auto-pairing.
    /// Calibrated to ~15 cm so the phones need to be actively held together; casual
    /// room proximity is not enough to trigger an implicit join.
    public static let touchThresholdMeters: Double = 0.15

    /// MultipeerConnectivity service type. Must be 1–15 alphanumeric/hyphen chars and
    /// MUST match the `NSBonjourServices` prefix in Info.plist (`_unplugged-rm._tcp`).
    public static let serviceType: String = "unplugged-rm"
}
