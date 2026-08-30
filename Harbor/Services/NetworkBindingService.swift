import Darwin
import Dispatch
import Foundation
import SystemConfiguration

nonisolated protocol NetworkBindingCataloging: Sendable {
    /// Everything the user can pick, starting with `.any`.
    func availableTargets() -> [NetworkBindingTarget]

    /// The interface a selection points at right now, or `nil` when the
    /// selection carries no restriction (`.any`) or has no usable IPv4
    /// interface at the moment.
    func resolve(_ selection: NetworkBindingSelection) -> ResolvedNetworkBinding?
}

nonisolated struct SystemNetworkBindingCatalog: NetworkBindingCataloging {
    func availableTargets() -> [NetworkBindingTarget] {
        [.any] + serviceTargets() + interfaceTargets()
    }

    func resolve(_ selection: NetworkBindingSelection) -> ResolvedNetworkBinding? {
        switch selection {
        case .any:
            nil
        case let .service(id):
            resolveService(id: id)
        case let .interface(name):
            Self.activeIPv4Address(forInterface: name).map {
                ResolvedNetworkBinding(interfaceName: name, ipv4Address: $0)
            }
        }
    }

    private func serviceTargets() -> [NetworkBindingTarget] {
        guard let preferences = SCPreferencesCreate(
            nil,
            "Harbor.NetworkBindingCatalog" as CFString,
            nil
        ),
        let currentSet = SCNetworkSetCopyCurrent(preferences),
        let services = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService] else {
            return []
        }

        let targets = services.compactMap { service -> NetworkBindingTarget? in
            guard SCNetworkServiceGetEnabled(service),
                  let id = SCNetworkServiceGetServiceID(service) as String?,
                  let name = SCNetworkServiceGetName(service) as String?,
                  name.isEmpty == false else {
                return nil
            }

            let interfaceType = SCNetworkServiceGetInterface(service)
                .flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? }

            return NetworkBindingTarget(
                selection: .service(id: id),
                displayName: name,
                kind: .service,
                medium: Self.medium(forInterfaceType: interfaceType)
            )
        }

        return NetworkBindingTarget.sortedByMedium(targets)
    }

    /// macOS reports what a service runs over, which is the only reliable way
    /// to tell a VPN from an ordinary connection: a VPN has no BSD name until
    /// it connects, and its flags match a real adapter's once it does.
    static func medium(forInterfaceType interfaceType: String?) -> NetworkBindingMedium {
        guard let interfaceType else {
            return .other
        }

        // SystemConfiguration exports no constant for the type a
        // NetworkExtension VPN or a Thunderbolt bridge reports, so those two
        // are matched by the value macOS returns. PPTP is left out: macOS
        // dropped it in 10.12, long before this app's deployment target.
        let tunnelTypes: Set<String> = [
            "VPN",
            kSCNetworkInterfaceTypeIPSec as String,
            kSCNetworkInterfaceTypePPP as String,
            kSCNetworkInterfaceTypeL2TP as String
        ]
        let wiredTypes: Set<String> = [
            "Bridge",
            kSCNetworkInterfaceTypeEthernet as String,
            kSCNetworkInterfaceTypeBond as String,
            kSCNetworkInterfaceTypeVLAN as String
        ]

        if tunnelTypes.contains(interfaceType) {
            return .vpn
        }
        if interfaceType == kSCNetworkInterfaceTypeIEEE80211 as String {
            return .wireless
        }
        if wiredTypes.contains(interfaceType) {
            return .wired
        }
        return .other
    }

    private func interfaceTargets() -> [NetworkBindingTarget] {
        let mediums = Self.interfaceMediums()

        let targets = Self.interfaceNames().map { name in
            NetworkBindingTarget(
                selection: .interface(name: name),
                displayName: name,
                kind: .interface,
                medium: mediums[name] ?? Self.medium(forInterfaceName: name)
            )
        }

        return NetworkBindingTarget.sortedByMedium(targets)
    }

    /// What every adapter macOS knows about runs over, keyed by BSD name. This
    /// is what tells `en0` (Wi-Fi) from `en5` (a USB Ethernet adapter), which
    /// the name alone never reveals.
    private static func interfaceMediums() -> [String: NetworkBindingMedium] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return [:]
        }

        return interfaces.reduce(into: [:]) { mediums, interface in
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else {
                return
            }

            mediums[bsdName] = medium(
                forInterfaceType: SCNetworkInterfaceGetInterfaceType(interface) as String?
            )
        }
    }

    /// A tunnel has no SCNetworkInterface — it exists only while it is up — so
    /// its name is all there is to classify it by.
    static func medium(forInterfaceName name: String) -> NetworkBindingMedium {
        let tunnelBaseNames: Set<String> = ["utun", "ipsec", "ppp", "tun", "tap"]
        let baseName = String(name.prefix { $0.isNumber == false })
        return tunnelBaseNames.contains(baseName) ? .vpn : .other
    }

    /// A service has no BSD interface until it is up, and a VPN lands on a
    /// different `utunN` on every connection.
    private func resolveService(id: String) -> ResolvedNetworkBinding? {
        dynamicStoreBinding(serviceID: id) ?? vpnConnectionBinding(serviceID: id)
    }

    /// Wired and wireless services publish their live address under their own
    /// configured identifier.
    private func dynamicStoreBinding(serviceID: String) -> ResolvedNetworkBinding? {
        guard let store = SCDynamicStoreCreate(
            nil,
            "Harbor.NetworkBindingCatalog" as CFString,
            nil,
            nil
        ),
        let entry = SCDynamicStoreCopyValue(
            store,
            "State:/Network/Service/\(serviceID)/IPv4" as CFString
        ) as? [String: Any] else {
            return nil
        }

        return Self.binding(fromIPv4Entry: entry)
    }

    /// A VPN publishes its address under a per-session identifier that has no
    /// link back to the configured service, so the dynamic store cannot answer
    /// for it. SCNetworkConnection reports the same information for the stable
    /// service identifier the selection stores.
    private func vpnConnectionBinding(serviceID: String) -> ResolvedNetworkBinding? {
        guard let connection = SCNetworkConnectionCreateWithServiceID(
            nil,
            serviceID as CFString,
            nil,
            nil
        ),
        let status = SCNetworkConnectionCopyExtendedStatus(connection) as? [String: Any],
        let ipv4Entry = status["IPv4"] as? [String: Any] else {
            return nil
        }

        return Self.binding(fromIPv4Entry: ipv4Entry)
    }

    static func binding(fromIPv4Entry entry: [String: Any]) -> ResolvedNetworkBinding? {
        guard let interfaceName = entry["InterfaceName"] as? String,
              interfaceName.isEmpty == false else {
            return nil
        }

        return ResolvedNetworkBinding(
            interfaceName: interfaceName,
            ipv4Address: (entry["Addresses"] as? [String])?.first
        )
    }

    /// Apple's own link-layer devices. `getifaddrs` reports them alongside real
    /// adapters, but none of them can carry a user's traffic, and their flags
    /// are indistinguishable from a real adapter's.
    private static let hiddenInterfaceBaseNames: Set<String> = [
        "anpi", // Apple network processor
        "ap", // Wi-Fi access point
        "awdl", // Apple Wireless Direct Link
        "gif", // generic tunnel pseudo-device
        "llw", // low-latency companion link
        "lo", // loopback
        "nan", // Neighbor Awareness Networking
        "stf" // 6to4 pseudo-device
    ]

    static func isOfferableInterfaceName(_ name: String) -> Bool {
        let baseName = name.prefix { $0.isNumber == false }
        return hiddenInterfaceBaseNames.contains(String(baseName)) == false
    }

    static func interfaceNames() -> [String] {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else {
            return []
        }
        defer { freeifaddrs(addressList) }

        var names: Set<String> = []
        for address in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: address.pointee.ifa_name)
            guard isOfferableInterfaceName(name) else {
                continue
            }
            names.insert(name)
        }

        return names.sorted()
    }

    static func activeIPv4Address(forInterface interfaceName: String) -> String? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else {
            return nil
        }
        defer { freeifaddrs(addressList) }

        for address in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: address.pointee.ifa_name) == interfaceName,
                  let socketAddress = address.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(address.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_RUNNING == IFF_RUNNING else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                continue
            }

            return String(cString: host)
        }

        return nil
    }
}

private let networkBindingStoreCallback: SCDynamicStoreCallBack = { _, _, info in
    guard let info else {
        return
    }

    // The store delivers on the queue set below, which is the main queue.
    MainActor.assumeIsolated {
        Unmanaged<NetworkBindingMonitor>
            .fromOpaque(info)
            .takeUnretainedValue()
            .scheduleRefresh()
    }
}

/// Watches the selected network path and reports whether torrent traffic can be
/// bound to it right now.
@MainActor
final class NetworkBindingMonitor {
    private let catalog: any NetworkBindingCataloging
    private let debounceInterval: TimeInterval

    private var selection: NetworkBindingSelection = .any
    private var displayName = ""
    private var dynamicStore: SCDynamicStore?
    private var debounceWorkItem: DispatchWorkItem?

    private(set) var status: NetworkBindingStatus = .unrestricted {
        didSet {
            guard status != oldValue else {
                return
            }
            statusDidChange?(status)
        }
    }

    var statusDidChange: ((NetworkBindingStatus) -> Void)? {
        didSet {
            statusDidChange?(status)
        }
    }

    init(
        catalog: (any NetworkBindingCataloging)? = nil,
        debounceInterval: TimeInterval = 0.4
    ) {
        self.catalog = catalog ?? SystemNetworkBindingCatalog()
        self.debounceInterval = debounceInterval
    }

    deinit {
        debounceWorkItem?.cancel()
        if let dynamicStore {
            SCDynamicStoreSetDispatchQueue(dynamicStore, nil)
        }
    }

    func start(selection: NetworkBindingSelection, displayName: String) {
        stopObserving()
        self.selection = selection
        self.displayName = displayName

        // The owner acts on this status even when it did not change, because a
        // different selection can resolve to the same interface.
        publish(resolvedStatus(), alwaysNotify: true)

        guard selection != .any else {
            return
        }
        beginObserving()
    }

    func stop() {
        stopObserving()
        selection = .any
        displayName = ""
        publish(.unrestricted, alwaysNotify: false)
    }

    fileprivate func scheduleRefresh() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    /// Re-resolves the current selection and reports the result.
    func refreshStatus() {
        publish(resolvedStatus(), alwaysNotify: false)
    }

    private func resolvedStatus() -> NetworkBindingStatus {
        guard selection != .any else {
            return .unrestricted
        }

        guard let binding = catalog.resolve(selection) else {
            return .unavailable(displayName: displayName)
        }

        return .bound(displayName: displayName, binding: binding)
    }

    private func publish(_ newStatus: NetworkBindingStatus, alwaysNotify: Bool) {
        let didChange = status != newStatus
        status = newStatus
        if alwaysNotify, didChange == false {
            statusDidChange?(status)
        }
    }

    private func beginObserving() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(
            nil,
            "Harbor.NetworkBindingMonitor" as CFString,
            networkBindingStoreCallback,
            &context
        ) else {
            return
        }

        SCDynamicStoreSetNotificationKeys(
            store,
            ["State:/Network/Global/IPv4"] as CFArray,
            [
                "State:/Network/Service/[^/]+/IPv4",
                "State:/Network/Interface/[^/]+/Link"
            ] as CFArray
        )
        SCDynamicStoreSetDispatchQueue(store, .main)
        dynamicStore = store
    }

    private func stopObserving() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let dynamicStore {
            SCDynamicStoreSetDispatchQueue(dynamicStore, nil)
        }
        dynamicStore = nil
    }
}
