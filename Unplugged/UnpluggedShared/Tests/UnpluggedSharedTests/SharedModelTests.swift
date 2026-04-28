import XCTest
@testable import UnpluggedShared

final class SharedModelTests: XCTestCase {
    func testUsernameValidationHonorsBoundsAndCharset() {
        XCTAssertTrue(InputValidation.isValidUsername("abc"))
        XCTAssertTrue(InputValidation.isValidUsername("user_name_123"))
        XCTAssertTrue(InputValidation.isValidUsername(String(repeating: "a", count: InputValidation.usernameMaxLength)))

        XCTAssertFalse(InputValidation.isValidUsername("ab"))
        XCTAssertFalse(InputValidation.isValidUsername(String(repeating: "a", count: InputValidation.usernameMaxLength + 1)))
        XCTAssertFalse(InputValidation.isValidUsername("name-with-dash"))
        XCTAssertFalse(InputValidation.isValidUsername("name with space"))
    }

    func testPasswordValidationRequiresLengthAndThreeCharacterClasses() {
        XCTAssertTrue(InputValidation.isValidPassword("Password1"))
        XCTAssertTrue(InputValidation.isValidPassword("password1!"))
        XCTAssertTrue(InputValidation.isValidPassword("PASSWORD1!"))

        XCTAssertFalse(InputValidation.isValidPassword("Pass1!"))
        XCTAssertFalse(InputValidation.isValidPassword("password"))
        XCTAssertFalse(InputValidation.isValidPassword("password1"))
        XCTAssertFalse(InputValidation.isValidPassword("PASSWORD!"))
    }

    func testSessionCodeValidationRequiresExactSixAlphanumericCharacters() {
        XCTAssertTrue(InputValidation.isValidSessionCode("ABC123"))
        XCTAssertTrue(InputValidation.isValidSessionCode("ZZZZZZ"))

        XCTAssertFalse(InputValidation.isValidSessionCode("ABC12"))
        XCTAssertFalse(InputValidation.isValidSessionCode("ABC1234"))
        XCTAssertFalse(InputValidation.isValidSessionCode("AB-123"))
    }

    func testUserStatsResponseDecodesLegacyPayloadWithoutOptionalFields() throws {
        let json = """
        {
          "hoursUnplugged": 12,
          "rank": 3,
          "totalSessions": 8,
          "longestStreak": 4,
          "currentStreak": 2,
          "avgSessionLengthMinutes": 47.5,
          "friendsCount": 5,
          "totalMinutes": 720
        }
        """

        let decoded = try JSONDecoder().decode(UserStatsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.hoursUnplugged, 12)
        XCTAssertEqual(decoded.rank, 3)
        XCTAssertEqual(decoded.totalSessions, 8)
        XCTAssertEqual(decoded.plannedMinutes, 0)
        XCTAssertEqual(decoded.avgPlannedMinutes, 0)
        XCTAssertEqual(decoded.earlyLeaveCount, 0)
        XCTAssertEqual(decoded.points, 0)
    }
}
