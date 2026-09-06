import Foundation

nonisolated struct RequestHeader: Codable, Hashable, Sendable {
    var name: String
    var value: String

    var validationIssue: RequestHeaderValidationIssue? {
        guard name.isEmpty == false else {
            return .missingName
        }

        guard name.unicodeScalars.allSatisfy(Self.allowedNameCharacters.contains) else {
            return .invalidName
        }

        guard value.unicodeScalars.contains(where: Self.isDisallowedValueCharacter) == false else {
            return .invalidValue
        }

        return nil
    }

    /// Identifies Cookie and Authorization headers that require torrent disclosure.
    var triggersSensitiveTorrentWarning: Bool {
        let fieldName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return fieldName.caseInsensitiveCompare("Cookie") == .orderedSame
            || fieldName.caseInsensitiveCompare("Authorization") == .orderedSame
    }

    var aria2HeaderValue: String {
        "\(name): \(value)"
    }

    private static let allowedNameCharacters = CharacterSet(
        charactersIn: "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    )

    private static func isDisallowedValueCharacter(_ character: Unicode.Scalar) -> Bool {
        (character.value < 0x20 && character.value != 0x09) // 0x09: horizontal tab
            || character.value == 0x7F // 0x7F: delete
    }
}

nonisolated enum RequestHeaderValidationIssue: Equatable, Sendable {
    case missingName
    case invalidName
    case invalidValue
}

nonisolated extension Collection where Element == RequestHeader {
    var triggersSensitiveTorrentWarning: Bool {
        contains(where: \.triggersSensitiveTorrentWarning)
    }

    func apply(to request: inout URLRequest) {
        var appliedFieldNames = Set<String>()

        for header in self {
            let normalizedName = header.name.lowercased()
            if appliedFieldNames.insert(normalizedName).inserted {
                request.setValue(header.value, forHTTPHeaderField: header.name)
            } else {
                request.addValue(header.value, forHTTPHeaderField: header.name)
            }
        }
    }

    func apply(
        toSameOriginRedirect request: inout URLRequest,
        originatingAt sourceURL: URL
    ) {
        guard let redirectedURL = request.url,
              let sourceOrigin = HTTPOrigin(sourceURL),
              let redirectedOrigin = HTTPOrigin(redirectedURL),
              sourceOrigin == redirectedOrigin else {
            for header in self {
                request.setValue(nil, forHTTPHeaderField: header.name)
            }
            return
        }

        apply(to: &request)
    }
}

private nonisolated struct HTTPOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return nil
        }

        self.scheme = scheme
        self.host = host
        self.port = url.port ?? (scheme == "http" ? 80 : 443)
    }
}
