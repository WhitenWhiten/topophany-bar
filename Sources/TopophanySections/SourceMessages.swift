import Foundation

public enum SourceMessages {
    public static var templateLimit: String { tr("Too many pinned servers for one template. Choose fewer servers in Sections.") }
    public static var configurationApplying: String { tr("Applying source configuration…") }
    public static var configurationRejected: String { tr("Source configuration was not applied. Review Data sources in Settings.") }
    public static func problem(_ code: String) -> String {
        switch code {
        case "hub_changed": tr("Changing the Hub address requires signing in again. Choose account and password or token.")
        case "auth_required": tr("Sign in again to this Beszel source.")
        case "forbidden": tr("This account cannot access the requested systems.")
        case "mfa_required": tr("This account requires MFA. Use an API token in Advanced.")
        case "auth_method_unsupported": tr("This sign-in method is not supported. Use an API token in Advanced.")
        case "invalid_request": tr("Check the source address and advanced settings, then test again.")
        case "connection_failed": tr("Could not reach the Beszel Hub. Check the address and try again.")
        case "tls_error": tr("The Hub certificate could not be verified. Check its certificate or CA file.")
        case "rate_limited": tr("Beszel is limiting requests. Wait before trying again.")
        case "profile_conflict": tr("This profile changed elsewhere. Review the saved profile before retrying.")
        case "selection_limit", "state_budget": tr("This selection exceeds the supported limit. Select fewer servers.")
        case "selection_invalid": tr("Some selected systems are no longer accessible. Test the connection again.")
        case "discovery_limit": tr("Discovery exceeded its limit. Try a smaller source.")
        case "command_timeout": tr("The operation timed out. The saved profile will be checked before retrying.")
        case "profile_unavailable", "storage_error", "credential_storage_error": tr("The profile could not be read or saved. Check local storage access.")
        case "profile_not_found", "source_not_found": tr("This profile or source is no longer available. Refresh the sources list.")
        case "upstream_incompatible": tr("This Beszel Hub response is not supported.")
        default: tr("The source could not be configured. Refresh the sources list and try again.")
        }
    }
    /// The status card's headline: the state, short enough for one line.
    public static func headline(_ state: String) -> String {
        state == "partial" ? tr("Needs attention") : Self.state(state)
    }
    public static func state(_ state: String) -> String {
        switch state {
        case "loading": tr("Connecting")
        case "ready", "connected": tr("Connected")
        case "partial": tr("Some sources need attention")
        case "no_data": tr("No resource samples")
        case "retrying": tr("Retrying")
        case "auth_required": tr("Sign-in required")
        case "forbidden": tr("Access denied")
        case "unavailable", "error": tr("Source unavailable")
        default: tr("Unknown source state")
        }
    }
}
