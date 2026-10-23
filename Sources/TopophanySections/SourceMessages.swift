import Foundation

public enum SourceMessages {
    public static var templateLimit: String { tr("Too many pinned servers for one template. Choose fewer servers in Sections.") }
    public static var configurationApplying: String { tr("Applying source configuration…") }
    public static var configurationRejected: String { tr("Source configuration was not applied. Review Data sources in Settings.") }
    /// What went wrong, in the words of the adapter the source reads.
    public static func problem(_ code: String, adapter: String = "beszel") -> String {
        if adapter == "komari", let text = komari(code) { return text }
        return switch code {
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
    /// Komari takes an API key or none, from a server rather than a Hub.
    static func komari(_ code: String) -> String? {
        switch code {
        case "hub_changed": tr("Changing the server address requires its API key again. Choose API key or public servers only.")
        case "auth_required": tr("This Komari server didn’t accept the API key. Enter it again.")
        case "forbidden": tr("The Komari server denied this API key access to its servers.")
        case "auth_method_unsupported": tr("Komari reads with an API key, or its public servers without one. Choose one of them.")
        case "connection_failed": tr("Could not reach the Komari server. Check the address and try again.")
        case "tls_error": tr("The Komari server’s certificate could not be verified. Check its certificate or CA file.")
        case "rate_limited": tr("Komari is limiting requests. Wait before trying again.")
        case "upstream_incompatible": tr("This Komari server’s response is not supported. topo reads Komari 1.6.")
        case "discovery_limit": tr("This Komari server lists more than the 1,000 servers topo reads.")
        default: nil
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
