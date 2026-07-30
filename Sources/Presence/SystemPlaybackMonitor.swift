import Foundation
import IOKit.pwr_mgt
import PresenceCore

struct SystemPlaybackMonitor {
    private static let displayAssertionTypes = Set([
        kIOPMAssertionTypePreventUserIdleDisplaySleep,
        kIOPMAssertionTypeNoDisplaySleep
    ])
    private let classifier = PlaybackActivityClassifier()

    func activity() -> PlaybackActivity? {
        var unmanagedAssertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanagedAssertions) == kIOReturnSuccess,
              let assertionsByProcess = unmanagedAssertions?.takeRetainedValue()
                as? [NSNumber: [NSDictionary]] else {
            return nil
        }

        let signals = assertionsByProcess.flatMap { pid, assertions in
            assertions.compactMap { assertion -> PlaybackSignal? in
                guard let type = assertion[kIOPMAssertionTypeKey] as? String,
                      let level = assertion[kIOPMAssertionLevelKey] as? NSNumber else {
                    return nil
                }

                return PlaybackSignal(
                    ownerProcessID: pid.int32Value,
                    isActive: level.uint32Value == kIOPMAssertionLevelOn,
                    preventsDisplaySleep: Self.displayAssertionTypes.contains(type),
                    preventsIdleSystemSleep:
                        type == kIOPMAssertionTypePreventUserIdleSystemSleep,
                    resources: Set(assertion["ResourcesUsed"] as? [String] ?? [])
                )
            }
        }

        return classifier.activity(
            from: signals,
            excluding: ProcessInfo.processInfo.processIdentifier
        )
    }
}
