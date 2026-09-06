import Foundation

/// Which network path Harbor binds torrent traffic to.
///
/// A service is stored by its SystemConfiguration identifier because a VPN
/// service such as ProtonVPN has no fixed BSD interface: it appears as a
/// different `utunN` on every connection.
nonisolated enum NetworkBindingSelection: Hashable, Sendable {
    case any
    case service(id: String)
    case interface(name: String)

    private enum Prefix {
        static let service = "service:"
        static let interface = "interface:"
    }

    /// The `UserDefaults` representation. `.any` is stored as an empty string so
    /// an absent preference and an explicit "Automatic" agree.
    var storageValue: String {
        switch self {
        case .any:
            ""
        case let .service(id):
            Prefix.service + id
        case let .interface(name):
            Prefix.interface + name
        }
    }

    init(storageValue: String) {
        if storageValue.hasPrefix(Prefix.service) {
            let id = String(storageValue.dropFirst(Prefix.service.count))
            self = id.isEmpty ? .any : .service(id: id)
        } else if storageValue.hasPrefix(Prefix.interface) {
            let name = String(storageValue.dropFirst(Prefix.interface.count))
            self = name.isEmpty ? .any : .interface(name: name)
        } else {
            self = .any
        }
    }
}

nonisolated enum NetworkBindingTargetKind: Equatable, Sendable {
    case any
    case service
    case interface
}

/// What a target carries its traffic over. The case order is the order the
/// picker groups by: a VPN is the reason this setting exists, so it leads.
nonisolated enum NetworkBindingMedium: Int, Comparable, Sendable {
    case vpn
    case wireless
    case wired
    case other

    var symbolName: String {
        switch self {
        case .vpn:
            "lock.shield"
        case .wireless:
            "wifi"
        case .wired:
            "cable.connector"
        case .other:
            "network"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct NetworkBindingTarget: Identifiable, Equatable, Sendable {
    let selection: NetworkBindingSelection
    let displayName: String
    let kind: NetworkBindingTargetKind
    let medium: NetworkBindingMedium

    var id: String { selection.storageValue }

    /// Tells a VPN apart from an ordinary connection at a glance.
    var symbolName: String {
        kind == .any ? "circle.dashed" : medium.symbolName
    }

    init(
        selection: NetworkBindingSelection,
        displayName: String,
        kind: NetworkBindingTargetKind,
        medium: NetworkBindingMedium = .other
    ) {
        self.selection = selection
        self.displayName = displayName
        self.kind = kind
        self.medium = medium
    }

    static let any = NetworkBindingTarget(
        selection: .any,
        displayName: String(
            localized: "network.binding.any",
            defaultValue: "Automatic",
            comment: "Torrent network binding option that applies no interface restriction."
        ),
        kind: .any
    )

    /// Groups entries by what they run over and sorts each group the way the
    /// Finder sorts names, so `en2` stays ahead of `en10`.
    static func sortedByMedium(_ targets: [NetworkBindingTarget]) -> [NetworkBindingTarget] {
        targets.sorted { lhs, rhs in
            guard lhs.medium == rhs.medium else {
                return lhs.medium < rhs.medium
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}

/// The interface a selection currently points at.
///
/// aria2 resolves `--interface` to an address once at startup and caches it, so
/// a changed address matters as much as a changed interface name: both require
/// a daemon restart.
nonisolated struct ResolvedNetworkBinding: Equatable, Sendable {
    let interfaceName: String
    let ipv4Address: String?
}

nonisolated enum NetworkBindingStatus: Equatable, Sendable {
    case unrestricted
    case bound(displayName: String, binding: ResolvedNetworkBinding)
    case unavailable(displayName: String)

    var isAvailable: Bool {
        if case .unavailable = self {
            return false
        }
        return true
    }

    var errorMessage: String? {
        guard case let .unavailable(displayName) = self else {
            return nil
        }
        return TorrentEngineError.networkInterfaceUnavailable(displayName).localizedDescription
    }
}
