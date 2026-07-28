import Foundation
import IOKit.pwr_mgt

struct SystemDisplayActivityMonitor {
    func anotherProcessPreventsDisplaySleep() -> Bool {
        var unmanagedAssertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanagedAssertions) == kIOReturnSuccess,
              let assertionsByProcess = unmanagedAssertions?.takeRetainedValue()
                as? [NSNumber: [NSDictionary]] else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let displayAssertionTypes = Set([
            kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionTypeNoDisplaySleep
        ])

        for (pid, assertions) in assertionsByProcess
        where pid.int32Value != currentPID {
            for assertion in assertions {
                let type = assertion[kIOPMAssertionTypeKey] as? String
                let level = assertion[kIOPMAssertionLevelKey] as? NSNumber
                if let type,
                   let level,
                   displayAssertionTypes.contains(type),
                   level.uint32Value == kIOPMAssertionLevelOn {
                    return true
                }
            }
        }

        return false
    }
}
