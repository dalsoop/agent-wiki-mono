import Foundation
import Testing
@testable import PermissionKit

@Test func fullDiskAccessMapsProbeWithoutClaimingExactAuthorization() {
    #expect(FullDiskAccess.status { true } == .likelyGranted)
    #expect(FullDiskAccess.status { false } == .likelyDenied)
    #expect(FullDiskAccess.status { nil } == .unknown)
}

@Test func fullDiskAccessUsesAllFilesSettingsPane() {
    #expect(FullDiskAccess.settingsURLString.contains("Privacy_AllFiles"))
}

@Test func relaunchTerminatesOnlyAfterSuccessfulOpen() {
    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)

    #expect(FullDiskAccess.shouldTerminateAfterRelaunch(
        hasRunningApplication: true,
        error: nil
    ))
    #expect(!FullDiskAccess.shouldTerminateAfterRelaunch(
        hasRunningApplication: false,
        error: nil
    ))
    #expect(!FullDiskAccess.shouldTerminateAfterRelaunch(
        hasRunningApplication: true,
        error: error
    ))
}
