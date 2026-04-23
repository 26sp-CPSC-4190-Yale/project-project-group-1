import Foundation

public enum ProximityConstants {
    // 10 cm, must be actively pressed together, UWB spikes can drop readings well below arm's length for a frame
    public static let touchThresholdMeters: Double = 0.10

    // debounces UWB multipath spikes, single samples are noise, two in a row is the floor
    public static let consecutiveCloseSamples: Int = 2

    // must match NSBonjourServices prefix in Info.plist (_unplugged-rm._tcp), 1-15 alphanumeric or hyphen
    public static let serviceType: String = "unplugged-rm"
}
