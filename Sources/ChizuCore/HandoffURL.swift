import Foundation

/// A link handed off from a browser as `chizu-http:` or `chizu-https:`.
public enum HandoffURL {
    public static let schemePrefix = "chizu-"

    /// Removes the `chizu-` prefix once and returns other URLs unchanged.
    /// The caller still rejects results that are not HTTP or HTTPS.
    public static func unwrap(_ url: URL) throws -> URL {
        guard let scheme = url.scheme, scheme.lowercased().hasPrefix(schemePrefix) else {
            return url
        }
        let value = url.absoluteString
        guard let unwrapped = URL(string: String(value.dropFirst(schemePrefix.count))) else {
            throw ChizuError.unsupportedURL(value)
        }
        return unwrapped
    }
}
