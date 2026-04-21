import Foundation

public enum ProximityConstants {
    /// Distance (meters) at which two phones are considered "touched" for auto-pairing.
    /// 10 cm: phones must be actively pressed together. A looser threshold lets two phones
    /// in the same room auto-pair, which is exactly the "my friend joined from across the
    /// room" bug — UWB readings can spike well below arm's length momentarily, so the
    /// gate has to be tight AND debounced (see `consecutiveCloseSamples`).
    public static let touchThresholdMeters: Double = 0.10

    /// Number of *consecutive* sub-threshold UWB samples required before we pair.
    /// Single samples spike due to signal multipath; two in a row is the noise floor.
    public static let consecutiveCloseSamples: Int = 2

    /// MultipeerConnectivity service type. Must be 1–15 alphanumeric/hyphen chars and
    /// MUST match the `NSBonjourServices` prefix in Info.plist (`_unplugged-rm._tcp`).
    public static let serviceType: String = "unplugged-rm"
}
