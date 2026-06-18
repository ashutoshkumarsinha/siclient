import Foundation

// MARK: - File Overview
// Stable accessibility identifiers for GUI controls. Used by UI tests and automation
// to find buttons, text fields, and labels without relying on visible text.

/// Accessibility identifier strings for SICLient GUI elements.
public enum AccessibilityID {
    public static let profilePathField = "gui.profilePath"
    public static let loadProfileButton = "gui.loadProfile"
    public static let registerButton = "gui.register"
    public static let deregisterButton = "gui.deregister"
    public static let callDestinationField = "gui.callDestination"
    public static let placeCallButton = "gui.placeCall"
    public static let hangUpButton = "gui.hangUp"
    public static let holdButton = "gui.hold"
    public static let resumeButton = "gui.resume"
    public static let dtmfField = "gui.dtmf"
    public static let sendDTMFButton = "gui.sendDTMF"
    public static let smsDestinationField = "gui.smsDestination"
    public static let smsTextField = "gui.smsText"
    public static let sendSMSButton = "gui.sendSMS"
    public static let emergencyCallButton = "gui.emergencyCall"
    public static let fetchForwardingButton = "gui.fetchForwarding"
    public static let statusLabel = "gui.status"
    public static let logView = "gui.log"
}
