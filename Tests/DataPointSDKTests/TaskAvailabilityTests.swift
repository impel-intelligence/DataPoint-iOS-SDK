import XCTest
@testable import DataPointSDK

final class TaskAvailabilityTests: XCTestCase {

    func testParsesFullResponse() {
        let json: [String: Any] = [
            "task_available": false,
            "reason": "daily_limit_reached",
            "message": "This user has reached today's task limit."
        ]
        let parsed = TaskAvailability(json: json)
        XCTAssertEqual(parsed, TaskAvailability(
            isAvailable: false,
            reason: TaskAvailability.Reason.dailyLimitReached,
            message: "This user has reached today's task limit."
        ))
    }

    func testFallsBackWhenReasonAndMessageAreMissing() {
        XCTAssertEqual(
            TaskAvailability(json: ["task_available": true]),
            TaskAvailability(isAvailable: true, reason: TaskAvailability.Reason.available, message: "")
        )
        XCTAssertEqual(
            TaskAvailability(json: ["task_available": false]),
            TaskAvailability(isAvailable: false, reason: TaskAvailability.Reason.noTask, message: "")
        )
    }

    func testRejectsBodyWithoutTaskAvailable() {
        XCTAssertNil(TaskAvailability(json: ["reason": "available"]))
        XCTAssertNil(TaskAvailability(json: ["task_available": "yes"]))
        XCTAssertNil(TaskAvailability(json: [:]))
    }
}
