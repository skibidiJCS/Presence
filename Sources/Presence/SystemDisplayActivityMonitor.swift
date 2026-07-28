import Foundation
import IOKit.pwr_mgt

struct SystemDisplayActivityMonitor {
    private static let displayAssertionTypes = Set([
        kIOPMAssertionTypePreventUserIdleDisplaySleep,
        kIOPMAssertionTypeNoDisplaySleep
    ])

    func isDisplayKeptAwakeByAnotherProcess() -> Bool? {
        var unmanagedAssertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanagedAssertions) == kIOReturnSuccess,
              let assertionsByProcess = unmanagedAssertions?.takeRetainedValue()
                as? [NSNumber: [NSDictionary]] else {
            return nil
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier

        for (pid, assertions) in assertionsByProcess
        where pid.int32Value != currentPID {
            for assertion in assertions {
                let type = assertion[kIOPMAssertionTypeKey] as? String
                let level = assertion[kIOPMAssertionLevelKey] as? NSNumber
                if let type,
                   let level,
                   Self.displayAssertionTypes.contains(type),
                   level.uint32Value == kIOPMAssertionLevelOn {
                    return true
                }
            }
        }

        return false
    }
}
