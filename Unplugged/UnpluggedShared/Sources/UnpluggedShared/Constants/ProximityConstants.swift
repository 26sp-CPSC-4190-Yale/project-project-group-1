import Foundation

public enum ProximityConstants {
    // 15 cm, must be actively held together, but leaves room for real-device UWB jitter in TestFlight builds
    public static let touchThresholdMeters: Double = 0.15

    // debounces UWB multipath spikes, single samples are noise, two in a row is the floor
    public static let consecutiveCloseSamples: Int = 2

    // must match NSBonjourServices prefix in Info.plist (_unplugged-rm._tcp), 1-15 alphanumeric or hyphen
    public static let serviceType: String = "unplugged-rm"
}
