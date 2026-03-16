import DiskArbitration
import Foundation

public protocol DeviceManaging {
    func unmountWholeDisk(_ device: DiskCandidate) async throws
    func mountPartition(_ bsdName: String) async throws
}

public final class DiskArbitrationManager: DeviceManaging, @unchecked Sendable {
    private let queue = DispatchQueue(label: "SwiftFlashCLI.DiskArbitration")

    public init() {}

    public func unmountWholeDisk(_ device: DiskCandidate) async throws {
        try await performDiskOperation(bsdName: device.bsdName) { disk, callback, context in
            DADiskUnmount(
                disk,
                DADiskUnmountOptions(kDADiskUnmountOptionWhole),
                callback,
                context
            )
        }
    }

    public func mountPartition(_ bsdName: String) async throws {
        try await performDiskOperation(bsdName: bsdName) { disk, callback, context in
            DADiskMount(
                disk,
                nil,
                DADiskMountOptions(kDADiskMountOptionDefault),
                callback,
                context
            )
        }
    }

    private func performDiskOperation(
        bsdName: String,
        operation: @escaping @Sendable (
            DADisk,
            @escaping @convention(c) (DADisk?, DADissenter?, UnsafeMutableRawPointer?) -> Void,
            UnsafeMutableRawPointer?
        ) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = self.queue
            queue.async {
                guard let session = DASessionCreate(kCFAllocatorDefault) else {
                    continuation.resume(throwing: FlashError.ioFailed("Failed to create DASession"))
                    return
                }
                DASessionSetDispatchQueue(session, queue)

                guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
                    continuation.resume(throwing: FlashError.deviceNotFound("/dev/\(bsdName)"))
                    DASessionSetDispatchQueue(session, nil)
                    return
                }

                let box = CallbackBox(continuation: continuation, session: session)
                let context = Unmanaged.passRetained(box).toOpaque()
                operation(disk, diskOperationCallback, context)
            }
        }
    }
}

private final class CallbackBox {
    let continuation: CheckedContinuation<Void, Error>
    let session: DASession

    init(continuation: CheckedContinuation<Void, Error>, session: DASession) {
        self.continuation = continuation
        self.session = session
    }
}

private let diskOperationCallback: @convention(c) (DADisk?, DADissenter?, UnsafeMutableRawPointer?) -> Void = { _, dissenter, context in
    guard let context else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(context).takeRetainedValue()
    DASessionSetDispatchQueue(box.session, nil)
    if let dissenter {
        let status = DADissenterGetStatus(dissenter)
        box.continuation.resume(
            throwing: FlashError.ioFailed("Disk Arbitration status \(status)")
        )
    } else {
        box.continuation.resume()
    }
}
