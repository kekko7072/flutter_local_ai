import Flutter
import ObjectiveC
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  /// `objc_copyClassList` realizes every class in the process, Swift classes
  /// included. A class whose stored properties name a FoundationModels value
  /// type cannot complete its metadata below OS 26 (the weak-linked
  /// framework's metadata accessors are null), so realizing it crashes the
  /// app with EXC_BAD_ACCESS at 0x0. Apps hit this at launch whenever an SDK
  /// or Dart's Objective-C interop lists the classes. On an iOS < 26
  /// simulator this covers the old-OS path; on OS 26+ it must pass as well.
  func testListingEveryClassDoesNotCrash() {
    var count: UInt32 = 0
    guard let classes = objc_copyClassList(&count) else {
      return XCTFail("objc_copyClassList returned nil")
    }
    // Only the call matters: the crash happens inside it, while the runtime
    // realizes the classes. Reading the elements back from Swift would
    // message classes that do not answer Objective-C messages, so don't.
    free(UnsafeMutableRawPointer(classes))
    XCTAssertGreaterThan(count, 0)
  }

}
