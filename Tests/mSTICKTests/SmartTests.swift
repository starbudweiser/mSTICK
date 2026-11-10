import XCTest
@testable import mSTICKCore

final class SmartTests: XCTestCase {
    func testCalcTrailingEquals() {
        XCTAssertEqual(SmartCalc.evaluate("567+45 =")[0], "612")
        XCTAssertNil(SmartCalc.evaluate("567+45 = 612")[0])
        XCTAssertNil(SmartCalc.evaluate("567+45")[0])
        XCTAssertEqual(SmartCalc.resultIfTrailingEquals("2*(3+4) =", line: 0), "14")
    }

    func testCalcNamedValuesAndPercent() {
        let r = SmartCalc.evaluate("price = $129\ndiscount = 27%\nsale price = price - discount")
        XCTAssertNil(r[0]); XCTAssertNil(r[1])
        XCTAssertEqual(r[2], "$94.17")
        let g = SmartCalc.evaluate("golf = $25\nhotel = $150\ntotal = golf + hotel")
        XCTAssertEqual(g[2], "$175")
        XCTAssertEqual(SmartCalc.evaluate("gas = $68 × 3")[0], "$204")
        XCTAssertEqual(SmartCalc.evaluate("a = 10\nb = a x 4")[1], "40")
    }

    func testCalcIgnoresProse() {
        XCTAssertTrue(SmartCalc.evaluate("Appeler Léa demain\nvoir 3 amis\n12-05-2024").isEmpty)
        XCTAssertNil(SmartCalc.evaluate("10 / 0 =")[0])
    }

    private func cal() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date { cal().date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))! }

    func testReminders() {
        let now = date(2026, 11, 10, 14) // mardi
        let c = cal()
        var p = ReminderParser.parse("remind me at 8 p.m. tomorrow to pick up lunch", now: now, calendar: c)
        XCTAssertEqual(p?.date, date(2026, 11, 11, 20)); XCTAssertEqual(p?.text, "pick up lunch")
        p = ReminderParser.parse("remind me tomorrow at 8:15 to call Léa", now: now, calendar: c)
        XCTAssertEqual(p?.date, date(2026, 11, 11, 8, 15)); XCTAssertEqual(p?.text, "call Léa")
        p = ReminderParser.parse("rappelle-moi demain à 9h de payer le loyer", now: now, calendar: c)
        XCTAssertEqual(p?.date, date(2026, 11, 11, 9)); XCTAssertEqual(p?.text, "payer le loyer")
        p = ReminderParser.parse("remind me friday to send the invoice", now: now, calendar: c)
        XCTAssertEqual(p?.date, date(2026, 11, 13, 9))
        p = ReminderParser.parse("remind me in 2 hours to stretch", now: now, calendar: c)
        XCTAssertEqual(p?.date, date(2026, 11, 10, 16)); XCTAssertEqual(p?.text, "stretch")
        p = ReminderParser.parse("remind me at 8am to run", now: now, calendar: c)
        XCTAssertEqual(p?.date, date(2026, 11, 11, 8)) // 8h est passé : demain
        XCTAssertNil(ReminderParser.parse("remind me to buy 2 apples", now: now, calendar: c))
        XCTAssertNil(ReminderParser.parse("buy milk tomorrow", now: now, calendar: c))
    }

    func testOldNoteJSONStillDecodes() throws {
        let json = #"{"id":"7B1E9E0A-0000-4000-8000-000000000001","title":"t","emoji":"","body":"b","color":"yellow","pinned":false,"archived":false,"createdAt":0,"updatedAt":0,"order":0}"#
        let n = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        XCTAssertNil(n.reminders); XCTAssertNil(n.allDesktops)
        XCTAssertEqual(NoteColor.darkBackground("yellow").count, 7)
    }
}
