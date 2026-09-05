import Foundation
import Testing

@testable import CloudCore

@Suite("Home Tests")
struct HomeTests {
    @Test("Local home recognizes a missing data file")
    func localMissingItem() {
        let missingFile = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadNoSuchFile.rawValue
        )
        let permissionFailure = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadNoPermission.rawValue
        )

        #expect(LocalHome().isItemNotFoundError(missingFile))
        #expect(LocalHome().isItemNotFoundError(permissionFailure) == false)
    }
}
