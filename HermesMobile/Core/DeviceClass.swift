import SwiftUI

// MARK: - Device Class

/// Detects whether the current device is an iPad or iPhone.
/// Use this instead of raw idiom checks so the detection is centralised and testable.
enum DeviceClass {
    case phone
    case pad

    /// The device class for the current device.
    static let current: DeviceClass = {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:  return .pad
        case .phone: return .phone
        default:    return .phone
        }
    }()

    /// `true` when running on an iPad.
    static var isPad: Bool { current == .pad }

    /// `true` when running on an iPhone (or iPod touch).
    static var isPhone: Bool { current == .phone }
}
