import Foundation

/// What the user should know about a target medium before choosing or erasing it:
/// whether it is a remembered medium and what is currently on it.
public struct DeviceOverview: Equatable, Sendable {
    /// Name to show for the medium (custom name if the medium is remembered).
    public var title: String
    /// Indented detail lines, e.g. `Known medium: …`, `Currently on it: …`.
    public var details: [String]

    public init(title: String, details: [String]) {
        self.title = title
        self.details = details
    }

    /// One line describing the current content, used in the erase confirmation.
    public var currentContent: String? {
        details.first { $0.hasPrefix(Self.contentPrefix) }.map { String($0.dropFirst(Self.contentPrefix.count)) }
    }

    static let contentPrefix = "Currently on it: "

    public static func make(
        device: DiskCandidate,
        identityStatus: DeviceIdentityStatus,
        knownDevice: KnownPhysicalDevice?,
        imageIdentity: ImageIdentity?,
        formatDate: (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) }
    ) -> DeviceOverview {
        var details: [String] = []
        let metadata = identityStatus.resolvedIdentity?.metadata

        switch identityStatus {
        case .identified(let identity):
            if let knownDevice {
                let name = knownDevice.customName ?? "unnamed"
                let mediaType = knownDevice.mediaTypeName.map { " [\($0)]" } ?? ""
                details.append("Known medium: \(name)\(mediaType), device-uuid \(identity.metadata.deviceUUID)")
            } else {
                details.append("Identified medium, device-uuid \(identity.metadata.deviceUUID)")
            }
        case .trailerRequiresSudo:
            details.append("Unknown medium (sudo required to read trailer metadata)")
        case .unassigned:
            details.append("Unknown medium")
        }

        if let metadata, metadata.flashUUID != nil, !metadata.imageName.isEmpty {
            let label = (metadata.image ?? imageIdentity)?.displayLabel
            let image = label.map { "\($0) (\(metadata.imageName))" } ?? metadata.imageName
            details.append("\(contentPrefix)\(image), flashed \(formatDate(metadata.flashedAt))")
        } else if let label = (metadata?.image ?? imageIdentity)?.displayLabel {
            details.append("\(contentPrefix)\(label)")
        } else {
            let volumes = device.partitions.compactMap(\.volumeName).filter { !$0.isEmpty }
            if !volumes.isEmpty {
                details.append("\(contentPrefix)volumes \(volumes.joined(separator: ", "))")
            }
        }

        return DeviceOverview(title: knownDevice?.customName ?? device.displayName, details: details)
    }
}
