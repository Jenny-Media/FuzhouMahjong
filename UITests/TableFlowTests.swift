import FuzhouCore
import XCTest

@MainActor
final class TableFlowTests: XCTestCase {
    func testFaceAndMaterialCombinationsAtPlaySize() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let base = try savedMatchArguments(match(seed: 29, after: 0))
        let combinations = [
            (board: "jadeWalnut", material: "porcelain", face: "photoMatched"),
            (board: "jadeWalnut", material: "porcelain", face: "minimal"),
            (board: "redwoodSuede", material: "paleJade", face: "traditional"),
            (board: "bronzeLeather", material: "creamBakelite", face: "minimal"),
            (board: "redwoodSuede", material: "redwood", face: "photoMatched"),
            (board: "snowWhite", material: "redwood", face: "minimal"),
            (board: "jadeWalnut", material: "redwood", face: "traditional"),
            (board: "jadeWalnut", material: "frostedGlass", face: "photoMatched"),
            (board: "jadeWalnut", material: "bambooPorcelain", face: "photoMatched"),
            (board: "jadeWalnut", material: "blackLacquer", face: "photoMatched"),
        ]
        for combination in combinations {
            app.launchArguments = base + [
                "-appearance.mode", "dark", "-table.boardStyle", combination.board,
                "-table.tileStyle", combination.material, "-table.tileFaceStyle", combination.face,
            ]
            app.launch()
            let practice = app.buttons["practice-entry"]
            XCTAssertTrue(practice.waitForExistence(timeout: 5))
            practice.tap()
            XCTAssertTrue(element("table-rack", in: app).waitForExistence(timeout: 5))
            XCTAssertTrue(element("latest-discard", in: app).waitForExistence(timeout: 5))
            capture("play-\(combination.face)-\(combination.material)")
            app.terminate()
        }
    }

    func testAppearanceChoicesAreIndependentAcrossModesAndRelaunch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let launchArguments = try savedMatchArguments(match(seed: 29, after: 0))
        app.launchArguments = launchArguments + [
            "-table.boardStyle", "charcoal", "-table.tileStyle", "modern", "-table.tileFaceStyle", "unknown",
        ]
        app.launch()

        func openSettings() {
            app.buttons["home-more"].tap()
            app.buttons["设置"].tap()
            XCTAssertTrue(element("table-appearance-preview", in: app).waitForExistence(timeout: 5))
        }

        func choose(_ option: String, using id: String) {
            let picker = element(id, in: app)
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            if picker.value as? String != option {
                reveal(picker, in: app)
                picker.tap()
                let selection = app.buttons[option]
                XCTAssertTrue(selection.waitForExistence(timeout: 5))
                selection.tap()
            }
            XCTAssertEqual(picker.value as? String, option)
        }

        func settingsBrightness(capturing name: String) throws -> Int {
            let bar = app.navigationBars["设置"].frame
            let screenshot = XCUIScreen.main.screenshot()
            capture(name, screenshot: screenshot)
            let image = try XCTUnwrap(screenshot.image.cgImage)
            let scale = CGFloat(image.width) / app.frame.width
            // Sample the empty area between the leading edge and the centered title.
            let blank = CGRect(x: bar.minX + bar.width * 0.2, y: bar.midY, width: 4, height: 4)
            let sample = try XCTUnwrap(image.cropping(to: blank.applying(CGAffineTransform(scaleX: scale, y: scale))))
            var pixel = [UInt8](repeating: 0, count: 4)
            try pixel.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                                    bitsPerComponent: 8, bytesPerRow: 4,
                                                    space: CGColorSpaceCreateDeviceRGB(),
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return pixel.prefix(3).map(Int.init).reduce(0, +) / 3
        }

        let display = "appearance-picker"
        let board = "board-style-picker"
        let material = "tile-material-picker"
        let face = "tile-face-style-picker"
        openSettings()
        XCTAssertEqual(element(board, in: app).value as? String, "自动")
        XCTAssertEqual(element(material, in: app).value as? String, "白釉瓷")
        XCTAssertEqual(element(face, in: app).value as? String, "实物经典")
        app.terminate()
        app.launchArguments = launchArguments
        app.launch()

        openSettings()
        choose("跟随系统", using: display)
        choose("自动", using: board)
        choose("自动", using: material)
        choose("实物经典", using: face)
        let systemBrightness = try settingsBrightness(capturing: "appearance-system-settings")
        choose("浅色", using: display)
        XCTAssertGreaterThan(try settingsBrightness(capturing: "appearance-light-settings"), 150)
        choose("深色", using: display)
        XCTAssertLessThan(try settingsBrightness(capturing: "appearance-dark-settings"), 110,
                          "An open Settings sheet should switch to Dark immediately.")
        choose("跟随系统", using: display)
        XCTAssertEqual(try settingsBrightness(capturing: "appearance-restored-system-settings"),
                       systemBrightness, accuracy: 20)

        choose("深色", using: display)
        choose("碧玉胡桃木", using: board)
        choose("白釉瓷", using: material)
        capture("settings-photoMatched-porcelain")
        choose("极简", using: face)
        XCTAssertEqual(element(material, in: app).value as? String, "白釉瓷")
        XCTAssertEqual(element(board, in: app).value as? String, "碧玉胡桃木")
        capture("settings-minimal-porcelain")
        choose("传统雕花", using: face)
        capture("settings-traditional-porcelain")
        choose("青白玉", using: material)
        choose("紫檀 · 烟灰绒", using: board)
        XCTAssertEqual(element(face, in: app).value as? String, "传统雕花")
        capture("settings-traditional-paleJade")
        choose("紫檀", using: material)
        capture("settings-traditional-redwood")

        choose("浅色", using: display)
        XCTAssertEqual(element(board, in: app).value as? String, "紫檀 · 烟灰绒")
        XCTAssertEqual(element(material, in: app).value as? String, "紫檀")
        XCTAssertEqual(element(face, in: app).value as? String, "传统雕花")
        app.terminate()
        app.launch()
        openSettings()
        XCTAssertEqual(element(display, in: app).value as? String, "浅色")
        XCTAssertEqual(element(board, in: app).value as? String, "紫檀 · 烟灰绒")
        XCTAssertEqual(element(material, in: app).value as? String, "紫檀")
        XCTAssertEqual(element(face, in: app).value as? String, "传统雕花")
    }

    func testAppearanceRowsSupportSingleAndMultiChoiceSwipes() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        app.buttons["home-more"].tap()
        app.buttons["设置"].tap()

        let preview = element("table-appearance-preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(preview.frame.height, 150)
        capture("turntables-ready")

        let pickers = [
            (id: "appearance-picker", options: ["跟随系统", "浅色", "深色"]),
            (id: "board-style-picker", options: ["自动", "碧玉胡桃木", "雪白 · 白瓷", "墨蓝 · 枪灰金属",
                                                "紫檀 · 烟灰绒", "古铜 · 马鞍革"]),
            (id: "tile-material-picker", options: ["自动", "暖白", "白釉瓷", "牙白 · 紫檀拼", "紫檀", "青白玉",
                                                  "奶油电木", "冰蓝琉璃", "竹背瓷面", "缎面黑漆"]),
            (id: "tile-face-style-picker", options: ["实物经典", "极简", "传统雕花"]),
        ]
        for (id, options) in pickers {
            let picker = element(id, in: app)
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            reveal(picker, in: app)
            if picker.value as? String != options[0] {
                picker.tap()
                app.buttons[options[0]].tap()
            }
            XCTAssertEqual(picker.value as? String, options[0])

            let hasArc = id != "appearance-picker"
            let swipeArea = element("\(id)-\(hasArc ? "arc" : "swipe")", in: app)
            reveal(swipeArea, in: app)
            let previewFrame = preview.frame
            let span: CGFloat = hasArc ? 0.24 : 0.28
            swipeChoice(swipeArea, forward: false, span: span, velocity: .slow)
            expectValue(of: picker, in: [options[options.count - 1]])
            swipeChoice(swipeArea, forward: true, span: span, velocity: .slow)
            expectValue(of: picker, in: [options[0]])
            swipeChoice(swipeArea, forward: true, span: span, velocity: .slow)
            expectValue(of: picker, in: [options[1]])
            swipeChoice(swipeArea, forward: false, span: 0.72, velocity: .fast)
            expectValue(of: picker, in: Array(options.dropFirst(2)))
            XCTAssertEqual(preview.frame, previewFrame, "Turning \(id) should keep the preview in place.")

            if hasArc {
                guard let current = options.firstIndex(of: picker.value as? String ?? "") else {
                    XCTFail("Unknown selection for \(id).")
                    return
                }
                XCTAssertFalse(app.buttons["\(id)-previous"].exists)
                XCTAssertFalse(app.buttons["\(id)-next"].exists)
                swipeArea.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
                expectValue(of: picker, in: [options[(current + 1) % options.count]])
            }
        }

        let faceArc = element("tile-face-style-picker-arc", in: app)
        capture("turntables-selected")
        let faceValue = faceArc.value as? String
        let startY = faceArc.frame.midY
        let start = faceArc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)))
        XCTAssertLessThan(faceArc.frame.midY, startY - 30, "Vertical swipes should scroll settings.")
        XCTAssertEqual(faceArc.value as? String, faceValue)
    }

    func testChangeAppearanceWithoutLeavingTheTable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let fixture = try match(seed: 1, after: 1)
        let app = try launchSavedMatch(fixture)
        let settings = app.buttons["table-settings"]
        let table = element("table-surface", in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let discard = app.buttons["discard-action"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        let boardFrame = table.frame
        let handTile = try XCTUnwrap(fixture.table(for: .south).hand.first)

        settings.tap()
        let title = app.navigationBars["设置"]
        let face = element("tile-face-style-picker", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        reveal(face, in: app)
        let selection = face.value as? String == "极简" ? "传统雕花" : "极简"
        face.tap()
        app.buttons[selection].tap()
        expectValue(of: face, in: [selection])
        capture("settings-from-table")

        title.buttons["完成"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(table.exists)
        XCTAssertTrue(app.buttons["tile-\(handTile.id)"].exists)
        XCTAssertTrue(discard.isHittable)
        assertFrames([table.frame], match: [boardFrame], labels: ["board"])
        capture("table-after-settings")

        settings.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(face.value as? String, selection)
    }

    private func reveal(_ control: XCUIElement, in app: XCUIApplication) {
        let top = app.frame.minY + 95
        let bottom = app.frame.maxY - 40
        for _ in 0..<4 {
            let y = control.frame.midY
            if control.isHittable && (top...bottom).contains(y) { return }
            let below = y > (top + bottom) / 2
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.77 : 0.30))
            start.press(forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: below ? -120 : 120)),
                        withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(control.isHittable && (top...bottom).contains(control.frame.midY))
    }

    private func expectValue(of picker: XCUIElement, in values: [String]) {
        let selected = expectation(for: NSPredicate(format: "value IN %@", values), evaluatedWith: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed,
                       "Expected \(picker.identifier) to select one of \(values), got \(picker.value ?? "none").")
    }

    private func swipeChoice(_ picker: XCUIElement, forward: Bool, span: CGFloat, velocity: XCUIGestureVelocity) {
        let left = picker.coordinate(withNormalizedOffset: CGVector(dx: (1 - span) / 2, dy: 0.5))
        let right = picker.coordinate(withNormalizedOffset: CGVector(dx: (1 + span) / 2, dy: 0.5))
        let (start, end) = forward ? (right, left) : (left, right)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0)
    }

    func testCustomRulesPreviewUpdatesForDraftChoices() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", "", "-table.custom-rulesets.v1", "<5b5d>", "-solo.ruleset", "pureSuit"]
        app.launch()

        app.buttons["practice-entry"].tap()
        let menu = app.buttons["custom-rules-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["manage-custom-rules"].tap()
        app.buttons["add-custom-rules"].tap()

        let indicators = element("custom-gold-indicators", in: app)
        XCTAssertTrue(indicators.waitForExistence(timeout: 5))
        indicators.tap()
        app.buttons["万筒条与风牌"].tap()
        XCTAssertTrue(element("custom-gold-explanation", in: app).label.contains("东、南、西、北"))

        let payment = element("custom-discard-payment", in: app)
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
        for _ in 0..<3 where !payment.isHittable { app.swipeUp() }
        payment.tap()
        app.buttons["其余三家各付分"].tap()
        XCTAssertTrue(element("custom-payment-example", in: app).label.contains("赢家得 60 分"))

        let flush = element("custom-flush-rule", in: app)
        for _ in 0..<3 where !flush.isHittable { app.swipeUp() }
        XCTAssertTrue(flush.isHittable)
        let initialEstimate = element("custom-flush-estimate", in: app).label
        flush.tap()
        app.buttons["金按牌面"].tap()
        XCTAssertNotEqual(element("custom-flush-estimate", in: app).label, initialEstimate)

        let stacking = app.switches["叠加特殊加分"]
        for _ in 0..<3 where !stacking.isHittable { app.swipeUp() }
        XCTAssertTrue(stacking.isHittable)
        stacking.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        capture("custom-rules-examples")
        let bonus = element("custom-bonus-example", in: app)
        let combined = expectation(for: NSPredicate(format: "label CONTAINS %@", "加 300 分"), evaluatedWith: bonus)
        XCTAssertEqual(XCTWaiter.wait(for: [combined], timeout: 4), .completed, bonus.label)
        let reference = app.buttons["custom-rules-reference"]
        for _ in 0..<3 where !reference.isHittable { app.swipeUp() }
        reference.tap()
        let title = app.staticTexts["ruleset-details-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "自定义规则预览")
        let method = app.staticTexts["rule-odds-method"]
        for _ in 0..<3 where !method.isHittable { app.swipeUp() }
        XCTAssertTrue(method.label.contains("17 张随机牌"))
        XCTAssertTrue(app.staticTexts["ruleset-gold-detail"].label.contains("东、南、西、北"))
        XCTAssertTrue(element("rule-odds-robGold", in: app).exists)
        XCTAssertTrue(element("rule-odds-pureSuit", in: app).exists)
        capture("custom-rules-odds")
    }

    func testCreateAndReuseTwoCustomRulesets() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let existing = (1...3).map { FuzhouHouseRules(name: "Existing \($0)") }
        let fixture = try JSONEncoder().encode(existing).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-play-access.archive.v1", "", "-table.custom-rulesets.v1", "<\(fixture)>"]
        let suffix = UUID().uuidString.prefix(4)
        let family = "Family \(suffix)"
        let friends = "Friends \(suffix)"
        app.launch()

        app.buttons["practice-entry"].tap()
        let menu = app.buttons["custom-rules-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["manage-custom-rules"].tap()
        let add = app.buttons["add-custom-rules"]
        for name in [family, friends] {
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
            let field = app.textFields["custom-rules-name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
            if name == family { app.switches["流局连庄"].tap() }
            app.buttons["save-custom-rules"].tap()
        }
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)
        XCTAssertTrue(app.staticTexts["custom-rules-limit"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(menu.label.contains(friends))
        let bonus = app.switches["pure-suit-bonus"]
        XCTAssertFalse(bonus.exists)
        menu.tap()
        app.buttons["use-standard-rules"].tap()
        XCTAssertTrue(bonus.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-play-access.archive.v1", ""]
        app.launch()
        app.buttons["practice-entry"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(app.buttons[friends].exists)
        app.buttons[family].tap()
        app.buttons["start-solo-setup"].tap()
        let skip = app.buttons["skip-opening"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["table-rules"].tap()
        let activeRules = app.staticTexts["active-ruleset"]
        XCTAssertTrue(activeRules.waitForExistence(timeout: 5))
        XCTAssertTrue(activeRules.label.contains(family))
    }

    func testNewSoloRulesetSelectionDoesNotChangeAnActiveMatch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", "", "-solo.customRulesetID", ""]
        app.launch()

        XCTAssertTrue(app.buttons["practice-entry"].waitForExistence(timeout: 5))
        let bonus = app.switches["pure-suit-bonus"]
        XCTAssertFalse(bonus.exists)
        capture("home-new-player")
        app.buttons["practice-entry"].tap()
        XCTAssertTrue(bonus.waitForExistence(timeout: 5))
        let bonusSwitch = bonus.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
        let start = app.buttons["start-solo-setup"]
        let rulesDetails = app.buttons["selected-ruleset-details"]
        let cancelSetup = app.buttons["cancel-solo-setup"]
        XCTAssertTrue(start.isHittable)
        XCTAssertGreaterThanOrEqual(start.frame.height, 50)
        XCTAssertLessThan(start.frame.minY - rulesDetails.frame.maxY, 36)
        XCTAssertGreaterThan(cancelSetup.frame.midY, app.frame.height * 0.35)
        if bonus.value as? String == "1" { bonusSwitch.tap() }
        XCTAssertEqual(bonus.value as? String, "0")
        capture("compact-solo-setup")
        rulesDetails.tap()
        let title = app.staticTexts["ruleset-details-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "清一色不加分")
        let details = app.staticTexts["ruleset-pattern-detail"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.label.contains("清一色按普通胡牌计分"))
        app.buttons["完成"].tap()
        start.tap()
        let skip = app.buttons["skip-opening"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["table-rules"].tap()
        let activeRules = app.staticTexts["active-ruleset"]
        XCTAssertTrue(activeRules.waitForExistence(timeout: 5))
        XCTAssertTrue(activeRules.label.contains("清一色不加分"))
        app.buttons["完成"].tap()
        app.buttons["BackButton"].tap()

        let newGame = app.buttons["new-solo-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        for button in [app.buttons["practice-entry"], newGame, app.buttons["nearby-entry"]] {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 60)
        }
        capture("home-saved-game")
        newGame.tap()
        XCTAssertTrue(bonus.waitForExistence(timeout: 5))
        XCTAssertEqual(bonus.value as? String, "0")
        bonusSwitch.tap()
        XCTAssertEqual(bonus.value as? String, "1")
        app.buttons["selected-ruleset-details"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "清一色加分")
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.label.contains("清一色有特殊加分"))
        app.buttons["完成"].tap()
        cancelSetup.tap()
        XCTAssertTrue(cancelSetup.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice-entry"].label.contains("清一色不加分"))
        app.buttons["practice-entry"].tap()
        app.buttons["table-rules"].tap()
        XCTAssertTrue(activeRules.waitForExistence(timeout: 5))
        XCTAssertTrue(activeRules.label.contains("清一色不加分"))
        app.buttons["rule-contents"].tap()
        app.buttons["tutorial-ruleset-details"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "清一色不加分")
    }

    func testAuditRegressionSavedTableRuleDetailsDistinguishNewGameRules() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(FuzhouMatch())) as? [String: Any])
        archive.removeValue(forKey: "resetsStreakOnPassingDraw")
        let older = try JSONDecoder().decode(FuzhouMatch.self, from: JSONSerialization.data(withJSONObject: archive))
        app.launchArguments = try savedMatchArguments(older) + ["-solo.customRulesetID", ""]
        app.launch()

        let savedRules = app.buttons["saved-solo-rules"]
        XCTAssertTrue(savedRules.waitForExistence(timeout: 5))
        savedRules.tap()
        let oldText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "两种情况都把连庄次数加一")).firstMatch
        XCTAssertTrue(oldText.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        app.buttons["new-solo-game"].tap()
        app.buttons["selected-ruleset-details"].tap()
        let newText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "流局换下家坐庄，连庄次数归零")).firstMatch
        XCTAssertTrue(newText.waitForExistence(timeout: 5))
    }

    func testLegacySaveIsClearedAndNewTableRulesAreAvailable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = try savedMatchArguments(FuzhouMatch(ruleset: .legacy)) +
            ["-solo.ruleset", "legacy", "-solo.customRulesetID", ""]
        app.launch()

        let notice = app.alerts["旧版单机牌局已清除"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.buttons["好"].tap()
        let practice = app.buttons["practice-entry"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        XCTAssertTrue(practice.label.contains("开始新牌局"))
        XCTAssertFalse(app.buttons["saved-solo-rules"].exists)
        practice.tap()
        let bonus = app.switches["pure-suit-bonus"]
        XCTAssertTrue(bonus.waitForExistence(timeout: 5))
        XCTAssertEqual(bonus.value as? String, "1")
        let newDetails = app.buttons["selected-ruleset-details"]
        newDetails.tap()
        let title = app.staticTexts["ruleset-details-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "清一色加分")
    }

    func testTwoSavedTablesRemainUntilThePlayerConfirmsWhichToKeep() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let first = FuzhouMatch(ruleset: .oldThree)
        let second = try olderSaveWithDecidedDiscard(houseRules: .init(name: "Family", discardPayment: .allOpponents))
        var settled = second
        XCTAssertTrue(settled.settleRestoredDiscard())
        let expectedScore = settled.scores[Seat.south.id]
        XCTAssertLessThan(expectedScore, 0)
        let secondSave = try JSONEncoder().encode(second).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = try savedMatchArguments(first) + ["-solo-match.second.v1", "<\(secondSave)>"]
        app.launch()

        let keepFirst = app.buttons["keep-first-solo"]
        let keepSecond = app.buttons["keep-second-solo"]
        XCTAssertTrue(keepFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(keepFirst.label.contains("清一色不加分"))
        XCTAssertTrue(keepSecond.label.contains("Family"))
        XCTAssertTrue(keepSecond.label.contains("\(expectedScore)分"))
        XCTAssertFalse(app.buttons["practice-entry"].exists)
        keepFirst.tap()
        let prompt = app.alerts["保留这张牌桌？"]
        let confirm = prompt.buttons["confirm-save-choice"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        prompt.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 5))
        XCTAssertTrue(keepFirst.exists && keepSecond.exists)
        keepSecond.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let resume = app.buttons["practice-entry"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(resume.label.contains("Family"))
        XCTAssertTrue(app.buttons["new-solo-game"].exists)
        XCTAssertFalse(keepFirst.exists || keepSecond.exists)
        resume.tap()
        XCTAssertTrue(app.buttons["view-scorecard"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["table-score-delta"].label, "本局积分变化 \(expectedScore)")
    }

    func testThrowKeepsRackInPlaceAndConfirmsGoldBeforeDiscarding() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let fixture = try match(seed: 1, after: 1)
        let state = fixture.table(for: .south)
        let drawn = try XCTUnwrap(state.drawn)
        let heldGold = try XCTUnwrap(state.hand.dropFirst(8).first(where: state.isGold))
        let app = try launchSavedMatch(fixture)
        let table = element("table-surface", in: app)
        let rack = element("table-rack", in: app)
        let actions = element("table-actions", in: app)
        let dock = element("drawn-tile-dock", in: app)
        let discard = app.buttons["discard-action"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        let anchors = [table, rack] + Seat.allCases.map { element("seat-score-\($0.id)", in: app) }
        let frames = anchors.map(\.frame)
        let isSplit = element("table-region", in: app).exists
        assertContains(table.frame, actions.frame)
        if isSplit {
            assertContains(app.windows.firstMatch.frame, dock.frame)
            XCTAssertFalse(table.frame.intersects(dock.frame))
        } else {
            assertContains(table.frame, dock.frame)
        }
        let handCenterX = isSplit ? rack.frame.midX : table.frame.midX
        XCTAssertGreaterThan(dock.frame.midX, handCenterX)
        XCTAssertLessThan(dock.frame.maxY, rack.frame.minY)
        capture("turn-actions-and-drawn-dock")

        let drawnTile = app.buttons["tile-\(drawn.id)"]
        let drawnCenter = drawnTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drawnCenter.press(forDuration: 0.1, thenDragTo: drawnCenter.withOffset(CGVector(dx: 0, dy: -16)))
        XCTAssertTrue(drawnTile.exists)
        let horizontalSwipe = CGVector(dx: -100, dy: -10)
        drawnCenter.press(forDuration: 0.1, thenDragTo: drawnCenter.withOffset(horizontalSwipe))
        XCTAssertTrue(drawnTile.exists)
        XCTAssertTrue(discard.isHittable)

        let goldTile = app.buttons["tile-\(heldGold.id)"]
        let goldCenter = goldTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        goldCenter.press(forDuration: 0.1, thenDragTo: goldCenter.withOffset(CGVector(dx: 0, dy: -142)))
        let confirm = app.alerts.buttons["confirm-gold-discard"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(goldTile.exists)

        let inward = handCenterX - drawnTile.frame.midX
        let inwardSwipe = CGVector(dx: inward, dy: -abs(inward) * 0.62)
        drawnCenter.press(forDuration: 0.1, thenDragTo: drawnCenter.withOffset(inwardSwipe),
                          withVelocity: .slow, thenHoldForDuration: 0.15)
        XCTAssertTrue(drawnTile.waitForNonExistence(timeout: 3))
        XCTAssertTrue(element("latest-discard", in: app).label.contains("你打出"))
        XCTAssertTrue(discard.waitForNonExistence(timeout: 3))
        assertFrames(anchors.map(\.frame), match: frames,
                     labels: ["board", "rack"] + Seat.allCases.map { "seat \($0.id)" })
    }

    func testKongPreviewLocksOrdinaryDiscardAndKeepsMeldSwipe() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let fixture = try match(seed: 233662, after: 4)
        let table = fixture.table(for: .south)
        let drawn = try XCTUnwrap(table.drawn)
        let kongs = table.moves.compactMap { move -> [Tile.ID]? in
            if case .meld(.concealedKong, let ids) = move { return ids }
            return nil
        }
        XCTAssertEqual(kongs.count, 2)
        XCTAssertFalse(kongs.joined().contains(drawn.id))

        let app = try launchSavedMatch(fixture)
        let discard = app.buttons["discard-action"]
        let kong = app.buttons["table-move-杠"]
        let drawnTile = app.buttons["tile-\(drawn.id)"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(discard.isEnabled)
        kong.tap()
        XCTAssertFalse(discard.isEnabled)
        app.buttons["meld-option-1"].tap()
        XCTAssertFalse(discard.isEnabled)
        XCTAssertFalse(drawnTile.isEnabled)
        assertHighlighted(Set(kongs[1]), in: table.hand, app: app)

        let drawnCenter = drawnTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drawnCenter.press(forDuration: 0.08, thenDragTo: drawnCenter.withOffset(CGVector(dx: 0, dy: -90)))
        XCTAssertTrue(drawnTile.exists)
        XCTAssertTrue(app.buttons["confirm-meld"].isEnabled)
        app.buttons["cancel-meld-preview"].tap()
        XCTAssertTrue(discard.isEnabled)

        kong.tap()
        app.buttons["meld-option-1"].tap()
        let tile = app.buttons["tile-\(try XCTUnwrap(kongs[1].first))"]
        let tileCenter = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        tileCenter.press(forDuration: 0.08, thenDragTo: tileCenter.withOffset(CGVector(dx: 0, dy: -90)))
        let meldID = try XCTUnwrap(kongs[1].min())
        XCTAssertTrue(element("table-meld-\(meldID)", in: app).waitForExistence(timeout: 5))
    }

    func testMultipleClaimActionsLeaveTheDiscardVisibleInBothOrientations() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let fixture = try match(seed: 193, after: 1)
        let state = fixture.table(for: .south)
        let app = try launchSavedMatch(fixture)
        let table = element("table-surface", in: app)
        let actions = element("table-actions", in: app)
        let discard = element("latest-discard", in: app)
        let seatScores = Seat.allCases.map { element("seat-score-\($0.id)", in: app) }
        let pass = app.buttons["table-move-过"]
        XCTAssertTrue(pass.waitForExistence(timeout: 5))

        // A folded Duo can present a wide window when the device is upright.
        let window = app.windows.firstMatch
        let portraitFrame = window.frame
        let portraitIsWide = portraitFrame.width > portraitFrame.height
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation == .landscapeLeft
            let resized = NSPredicate { _, _ in
                let frame = window.frame
                return (frame.width > frame.height) == (landscape != portraitIsWide)
            }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: resized, evaluatedWith: app)], timeout: 5), .completed)
            for label in ["吃", "碰", "杠", "过"] {
                XCTAssertTrue(app.buttons["table-move-\(label)"].isHittable, label)
            }
            assertContains(table.frame, actions.frame)
            XCTAssertTrue(discard.exists)
            XCTAssertFalse(actions.frame.intersects(discard.frame))
            capture(landscape ? "multiple-claims-landscape" : "multiple-claims-portrait")

            let anchors = [table, element("table-rack", in: app), discard] + seatScores
            let labels = ["board", "rack", "discard"] + Seat.allCases.map { "seat \($0.id)" }
            let before = anchors.map(\.frame)
            app.buttons["table-move-碰"].tap()
            XCTAssertTrue(app.buttons["confirm-meld"].waitForExistence(timeout: 5))
            assertFrames(anchors.map(\.frame), match: before, labels: labels)
            app.buttons["cancel-meld-preview"].tap()
            assertFrames(anchors.map(\.frame), match: before, labels: labels)
        }
        func rackIDs(for kind: MeldKind) throws -> [Tile.ID] {
            try XCTUnwrap(state.moves.compactMap { move -> [Tile.ID]? in
                if case .meld(let candidate, let ids) = move, candidate == kind { return ids }
                return nil
            }.first)
        }
        let pungIDs = try rackIDs(for: .pung)
        let kongIDs = try rackIDs(for: .openKong)
        let passFrame = pass.frame
        for (label, ids, count) in [("碰", pungIDs, 2), ("杠", kongIDs, 3)] {
            XCTAssertEqual(ids.count, count)
            app.buttons["table-move-\(label)"].tap()
            let confirm = app.buttons["confirm-meld"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            assertContains(table.frame, actions.frame)
            XCTAssertFalse(actions.frame.intersects(discard.frame))
            assertFrames([pass.frame], match: [passFrame], labels: ["pass control"])
            assertHighlighted(Set(ids), in: state.hand, app: app)
            app.buttons["cancel-meld-preview"].tap()
        }

        let third = try XCTUnwrap(kongIDs.first { !pungIDs.contains($0) })
        let duplicate = app.buttons["tile-\(third)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        duplicate.press(forDuration: 0.08, thenDragTo: duplicate.withOffset(CGVector(dx: 0, dy: -80)))
        XCTAssertTrue(app.buttons["meld-option-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirm-meld"].isEnabled)
        let labels = ["meld-option-0", "meld-option-1"].map { app.buttons[$0].firstMatch.label }
        XCTAssertTrue(labels.contains { $0.hasPrefix("碰") }, "Options: \(labels)")
        XCTAssertTrue(labels.contains { $0.hasPrefix("明杠") }, "Options: \(labels)")
    }

    func testChoosingAnotherChowHighlightsExactlyItsTwoTiles() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let fixture = try match(seed: 56, after: 47)
        let state = fixture.table(for: .south)
        let options = state.moves.compactMap { move -> [Tile.ID]? in
            if case .meld(.chow, let ids) = move { return ids }
            return nil
        }
        XCTAssertEqual(options.count, 3)
        let eligible = state.moves.flatMap { move -> [Tile.ID] in
            if case .meld(_, let ids) = move { return ids }
            return []
        }
        let app = try launchSavedMatch(fixture)
        assertHighlighted(Set(eligible), in: state.hand, app: app)
        let pass = app.buttons["table-move-过"]
        let passFrame = pass.frame
        app.buttons["table-move-吃"].tap()
        XCTAssertTrue(app.buttons["meld-option-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meld-option-1"].isHittable)
        XCTAssertTrue(app.buttons["meld-option-2"].isHittable)
        XCTAssertFalse(app.buttons["confirm-meld"].isEnabled)
        assertFrames([pass.frame], match: [passFrame], labels: ["pass control"])
        assertHighlighted(Set(options.flatMap { $0 }), in: state.hand, app: app)
        app.buttons["meld-option-2"].firstMatch.tap()
        assertHighlighted(Set(options[2]), in: state.hand, app: app)
        capture("selected-chow-tiles")
        app.buttons["confirm-meld"].tap()
        XCTAssertTrue(app.buttons["discard-action"].waitForExistence(timeout: 5))
        for id in options[2] { XCTAssertFalse(app.buttons["tile-\(id)"].exists) }
        var claimed = fixture
        XCTAssertTrue(claimed.apply(.meld(.chow, options[2]), by: .south))
        let meld = try XCTUnwrap(claimed.table(for: .south).players[Seat.south.id].melds.last)
        XCTAssertTrue(element("table-meld-\(meld.id)", in: app).exists)
    }

    func testOpponentMeldsAndRemainingRackCanBeInspectedInBothOrientations() throws {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        let fixture = try match(seed: 35, after: 41)
        let table = fixture.table(for: .south)
        let player = try XCTUnwrap(table.players.first { $0.seat != .south && !$0.melds.isEmpty && $0.rackCount > 0 })
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = try launchSavedMatch(fixture)
            let rack = element("table-rack", in: app)
            let original = rack.frame
            let backs = element("concealed-rack-\(player.seat.id)", in: app)
            XCTAssertEqual(backs.label, "手牌 \(player.rackCount) 张")
            let seat = element("seat-score-\(player.seat.id)", in: app)
            XCTAssertTrue(seat.isHittable)
            capture("live-melds-\(orientation.rawValue)")
            seat.tap()
            for meld in player.melds {
                let shown = element("inspected-meld-\(meld.id)", in: app)
                XCTAssertTrue(shown.waitForExistence(timeout: 5))
                XCTAssertGreaterThanOrEqual(shown.frame.width, CGFloat(meld.tiles.count * 40))
            }
            capture("seat-inspector-\(orientation.rawValue)")
            app.buttons["完成"].tap()
            assertFrames([rack.frame], match: [original], labels: ["rack"])
            XCTAssertTrue(app.buttons["declare-win"].isHittable)
            app.terminate()
        }
    }

    func testOverriddenPungExplainsTheResultOnTheTable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var match = try match(seed: 662, after: 24)
        let pung = try XCTUnwrap(match.legalMoves(for: .south).first {
            if case .meld(.pung, _) = $0 { true } else { false }
        })
        XCTAssertTrue(match.apply(pung, by: .south))
        for seat in Seat.allCases where seat != .south {
            let moves = match.legalMoves(for: seat)
            if moves.contains(.win) { XCTAssertTrue(match.apply(.win, by: seat)) }
            else if moves.contains(.pass) { XCTAssertTrue(match.apply(.pass, by: seat)) }
        }
        XCTAssertEqual(match.result?.kind, .discard)

        let app = try launchSavedMatch(match)
        let status = app.staticTexts["table-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "有人胡牌，这次没碰成")
        XCTAssertTrue(app.buttons["view-scorecard"].isHittable)
        capture("overridden-pung-feedback")
    }

    func testResumingAnOlderSaveSettlesTheDiscardWithoutAskingForPung() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let oldSave = try olderSaveWithDecidedDiscard()
        XCTAssertTrue(oldSave.legalMoves(for: .south).contains(.pass))
        XCTAssertFalse(oldSave.hasComputerMove(excluding: [.south]))

        let app = try launchSavedMatch(oldSave)
        XCTAssertTrue(app.buttons["view-scorecard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["table-move-过"].exists)
    }

    func testClaimThenDiscardInBothOrientations() throws {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        let fixture = try match(seed: 56, after: 47)
        let chows = fixture.legalMoves(for: .south).filter { if case .meld(.chow, _) = $0 { true } else { false } }
        var claimed = fixture
        XCTAssertTrue(claimed.apply(try XCTUnwrap(chows.last), by: .south))
        let table = claimed.table(for: .south)
        let meld = try XCTUnwrap(table.players[Seat.south.id].melds.last)
        let expectedDiscard = try XCTUnwrap(table.moves.compactMap { if case .discard(let id) = $0 { id } else { nil } }.first)
        XCTAssertFalse(table.hand.contains { $0.id == expectedDiscard && table.isGold($0) })

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = try launchSavedMatch(fixture)
            app.buttons["table-move-吃"].tap()
            app.buttons["meld-option-\(chows.count - 1)"].tap()
            app.buttons["confirm-meld"].tap()
            app.buttons["discard-action"].tap()
            XCTAssertTrue(app.buttons["tile-\(expectedDiscard)"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(element("table-meld-\(meld.id)", in: app).exists)
            app.terminate()
        }
    }

    func testMarkedTilesPreviewAndSwipeToClaimAChow() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let fixture = try match(seed: 56, after: 47)
        let state = fixture.table(for: .south)
        let groups = state.moves.compactMap { move -> [Tile.ID]? in
            if case .meld(_, let ids) = move { return ids }
            return nil
        }
        let chows = state.moves.compactMap { move -> [Tile.ID]? in
            if case .meld(.chow, let ids) = move { return ids }
            return nil
        }
        XCTAssertEqual(chows.count, 3)
        let target = chows[2]
        let shared = try XCTUnwrap(target.first { chows[1].contains($0) })
        let unique = try XCTUnwrap(target.first { id in groups.filter { $0.contains(id) }.count == 1 })
        let related = groups.filter { $0.contains(shared) }
        XCTAssertGreaterThan(related.count, 1)

        for startsWithSharedTile in [true, false] {
            let app = try launchSavedMatch(fixture)
            let confirm = app.buttons["confirm-meld"]
            let sharedTile = app.buttons["tile-\(shared)"]
            let uniqueTile = app.buttons["tile-\(unique)"]
            let swipe = CGVector(dx: 0, dy: -92)
            let center = CGVector(dx: 0.5, dy: 0.5)
            let start = (startsWithSharedTile ? sharedTile : uniqueTile).coordinate(withNormalizedOffset: center)
            if !startsWithSharedTile {
                XCTAssertTrue(app.buttons["table-move-过"].waitForExistence(timeout: 5))
                let rack = element("table-rack", in: app)
                let rackFrame = rack.frame
                start.press(forDuration: 0.08, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -18)),
                            withVelocity: .slow, thenHoldForDuration: 0.2)
                XCTAssertTrue(uniqueTile.exists)
                XCTAssertFalse(confirm.exists)
                assertFrames([rack.frame], match: [rackFrame], labels: ["rack"])
            }
            start.press(forDuration: 0.08, thenDragTo: start.withOffset(swipe),
                        withVelocity: .default, thenHoldForDuration: 0.9)

            if startsWithSharedTile {
                XCTAssertTrue(app.buttons["meld-option-0"].waitForExistence(timeout: 5))
                XCTAssertFalse(confirm.isEnabled)
                assertHighlighted(Set(related.flatMap { $0 }), in: state.hand, app: app)
                uniqueTile.tap()
                XCTAssertTrue(confirm.waitForExistence(timeout: 5))
                assertHighlighted(Set(target), in: state.hand, app: app)
                let selected = sharedTile.coordinate(withNormalizedOffset: center)
                selected.press(forDuration: 0.08, thenDragTo: selected.withOffset(swipe),
                               withVelocity: .default, thenHoldForDuration: 0.9)
            }

            XCTAssertTrue(app.buttons["discard-action"].waitForExistence(timeout: 5))
            for id in target { XCTAssertFalse(app.buttons["tile-\(id)"].exists) }
            app.terminate()
        }
    }

    func testDrawnWindJoinsTheVisibleFlowersAndTheReplacementReachesTheRack() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let fixture = try match(seed: 12, after: 12)
        let before = fixture.table(for: .south)
        var resolved = fixture
        XCTAssertTrue(resolved.apply(.pass, by: .south))
        let after = resolved.table(for: .south)
        let tile = try XCTUnwrap(after.drawn)
        XCTAssertEqual(after.lastDraw?.flowersReplaced, 1)
        XCTAssertEqual(after.players[Seat.south.id].exposedFlowers?.last?.kind, TileKind(.wind, 3))

        let app = try launchSavedMatch(fixture)
        let flowers = element("seat-flowers-\(Seat.south.id)", in: app)
        XCTAssertTrue(flowers.waitForExistence(timeout: 5))
        XCTAssertTrue(flowers.label.contains("花牌 \(before.players[Seat.south.id].flowerCount) 张"))
        let pass = app.buttons["table-move-过"]
        XCTAssertTrue(pass.waitForExistence(timeout: 3))
        pass.tap()

        let received = app.buttons["tile-\(tile.id)"]
        XCTAssertTrue(received.waitForExistence(timeout: 5))
        XCTAssertTrue(received.isHittable)
        XCTAssertTrue(flowers.label.contains("花牌 \(after.players[Seat.south.id].flowerCount) 张"))
        XCTAssertTrue(flowers.label.hasSuffix("、西"))
        capture("flowers-after-draw")

        element("seat-score-\(Seat.south.id)", in: app).tap()
        let inspected = element("inspected-flowers-\(Seat.south.id)", in: app)
        XCTAssertTrue(inspected.waitForExistence(timeout: 5))
        XCTAssertTrue(inspected.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "西")).firstMatch.exists)
        capture("flowers-inspector")
    }

    func testOpeningAndSkippingKeepTheBoardAndRackInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", ""]
        defer { XCUIDevice.shared.orientation = .portrait }

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            app.launch()
            openFreshSoloGame(app)
            let skip = app.buttons["skip-opening"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            let table = element("table-surface", in: app)
            let rack = element("table-rack", in: app)
            let actions = element("table-actions", in: app)
            let openingFrames = [table.frame, rack.frame]
            XCTAssertFalse(actions.exists)
            XCTAssertTrue(openingFrames.allSatisfy { $0.width > 0 && $0.height > 0 })
            capture("opening-\(orientation.rawValue)")

            skip.tap()
            XCTAssertTrue(skip.waitForNonExistence(timeout: 3))
            capture("settled-\(orientation.rawValue)")
            assertFrames([table.frame, rack.frame], match: openingFrames, labels: ["board", "rack"])
            if let actionFrame = try? actions.snapshot().frame {
                assertContains(table.frame, actionFrame)
            }
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-"))
                .firstMatch.waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    func testOpeningFeltSkipsBeforeReleaseAndCancelsWhenLeavingEarly() {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", "", "--ui-test-manual-opening"]

        // Use exposed felt away from the shuffle pile in both layouts.
        let layouts: [(UIDeviceOrientation, CGVector)] = [
            (.portrait, CGVector(dx: 0.16, dy: 0.23)),
            (.landscapeLeft, CGVector(dx: 0.24, dy: 0.86)),
        ]
        for (orientation, point) in layouts {
            XCUIDevice.shared.orientation = orientation
            app.launch()
            openFreshSoloGame(app)

            let skip = app.buttons["skip-opening"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            let table = element("table-surface", in: app)
            let felt = table.coordinate(withNormalizedOffset: point)
            let outside = table.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: point.dy))
            let seat = element("seat-score-\(Seat.north.id)", in: app)
            XCTAssertTrue(seat.exists)
            let seatCenter = seat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            felt.tap()
            XCTAssertTrue(skip.exists)
            felt.press(forDuration: 0.25)
            XCTAssertTrue(skip.exists)

            felt.press(forDuration: 0.15, thenDragTo: outside, withVelocity: .fast, thenHoldForDuration: 1)
            XCTAssertTrue(skip.exists, "Leaving the board early should cancel the hold.")
            felt.press(forDuration: 0.15, thenDragTo: seatCenter, withVelocity: .fast, thenHoldForDuration: 1)
            XCTAssertTrue(skip.exists, "Entering a seat early should cancel the hold.")

            seat.tap()
            let closeInspector = app.buttons["完成"]
            XCTAssertTrue(closeInspector.waitForExistence(timeout: 3))
            closeInspector.tap()
            XCTAssertTrue(closeInspector.waitForNonExistence(timeout: 3))

            felt.tap()
            felt.press(forDuration: 0.6, thenDragTo: outside, withVelocity: .fast, thenHoldForDuration: 0.2)
            XCTAssertTrue(skip.waitForNonExistence(timeout: 2))
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-"))
                .firstMatch.waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    func testTableBackSwipeStartsOnlyAtScreenEdge() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Content-area Back swipes require iOS 26.") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = try savedMatchArguments(match(seed: 29, after: 0))
        app.launch()
        let table = element("table-surface", in: app)
        let resume = app.buttons["practice-entry"]
        let back = app.buttons["BackButton"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        let inside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5))
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))

        func tryRulesContentSwipe() -> Bool {
            app.buttons["home-more"].tap()
            app.buttons["rules-entry"].tap()
            let lesson = app.staticTexts["rule-lesson-title"]
            XCTAssertTrue(lesson.waitForExistence(timeout: 5))
            inside.press(forDuration: 0.02, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            if resume.waitForExistence(timeout: 2) { return true }
            XCTAssertTrue(lesson.exists)
            back.tap()
            XCTAssertTrue(resume.waitForExistence(timeout: 5))
            return false
        }

        let rulesContentSwipePops = tryRulesContentSwipe()
        resume.tap()
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)

        inside.press(forDuration: 0.02, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(table.exists, "A swipe inside the table should keep the game open.")

        edge.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 5))

        XCTAssertEqual(tryRulesContentSwipe(), rulesContentSwipePops)
    }

    func testRotationDuringTheDealSettlesOnTheCurrentTable() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", ""]
        app.launch()
        openFreshSoloGame(app)
        let skip = app.buttons["skip-opening"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        let status = app.staticTexts["table-status"]
        let dealing = NSPredicate(format: "label == %@", "正在发牌")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: dealing, evaluatedWith: status)], timeout: 6), .completed)
        XCTAssertFalse(app.buttons["gold-rules"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(skip.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["gold-rules"].waitForExistence(timeout: 3))
        let board = element("table-surface", in: app)
        XCTAssertGreaterThan(board.frame.width, board.frame.height)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-"))
            .firstMatch.waitForExistence(timeout: 3))
        app.terminate()
    }

    func testSettledHistoryKeepsClaimedAndWinningDiscardsInOrder() throws {
        var game = try match(seed: 35, after: 41)
        while game.result == nil { try playFixtureMove(in: &game) }
        let table = game.table(for: .south)
        let timeline = try XCTUnwrap(table.discardTimeline)
        let claimed = try XCTUnwrap(timeline.first { discard in table.players.contains { player in
            player.melds.contains { $0.from == discard.seat && $0.tiles.contains(discard.tile) }
        } })
        let winning = try XCTUnwrap(game.result?.winningTile)
        XCTAssertEqual(claimed.id, timeline.first?.id)
        XCTAssertEqual(winning.id, timeline.last?.id)
        let app = try launchSavedMatch(game)
        app.buttons["view-scorecard"].tap()
        app.buttons["return-to-table"].tap()
        app.buttons["table-history"].tap()
        XCTAssertTrue(app.navigationBars["出牌与亮牌记录"].waitForExistence(timeout: 5))
        let history = app.scrollViews["table-history-scroll"]
        let first = element("history-discard-\(claimed.id)", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(history.frame.intersects(first.frame))
        XCTAssertTrue(first.label.contains("打出"))
        XCTAssertTrue(["吃", "碰", "杠"].contains { first.label.contains($0) })
        let last = visibleDiscard(winning.id, in: history)
        XCTAssertTrue(last.label.contains("打出"))
        XCTAssertTrue(last.label.contains("胡"))
    }

    func testOlderSaveDisplaysDiscardsMissingFromItsTimeline() throws {
        var game = try match(seed: 35, after: 41)
        while game.result == nil { try playFixtureMove(in: &game) }
        let data = try JSONEncoder().encode(game)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "discardTimeline")
        let saved = try JSONDecoder().decode(FuzhouMatch.self, from: JSONSerialization.data(withJSONObject: old))
        let app = try launchSavedMatch(saved)
        app.buttons["table-history"].tap()
        XCTAssertTrue(app.staticTexts["早前打出的牌（按座位）"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["按出牌顺序"].exists)
        XCTAssertFalse(app.staticTexts["本局还没有出牌"].exists)
        let winning = try XCTUnwrap(saved.result?.winningTile)
        let history = app.scrollViews["table-history-scroll"]
        let row = visibleDiscard(winning.id, in: history)
        XCTAssertTrue(row.label.contains("你胡"))
    }

    private func visibleDiscard(_ id: Tile.ID, in history: XCUIElement) -> XCUIElement {
        let row = history.descendants(matching: .any).matching(identifier: "history-discard-\(id)").firstMatch
        let viewport = history.frame
        for _ in 0..<12 {
            if row.exists, viewport.intersects(row.frame) { return row }
            history.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(row.exists && viewport.intersects(row.frame), "Discard \(id) should be visible in history")
        return row
    }

    func testLargeTextClaimShowsTheDiscardAndOpensTheChowChoice() throws {
        let game = try match(seed: 193, after: 1)
        let app = try launchSavedMatch(game, arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let discard = element("latest-discard", in: app)
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(discard.label.contains("六万"))
        let seat = element("seat-score-\(game.current.id)", in: app)
        XCTAssertTrue(seat.exists)
        XCTAssertTrue(seat.label.contains("手牌"))
        let chow = app.buttons["table-move-吃"]
        XCTAssertFalse(discard.frame.intersects(chow.frame))
        capture("largest-text-claim")
        chow.tap()
        XCTAssertTrue(app.buttons["confirm-meld"].waitForExistence(timeout: 5))
    }

    func testAuditRegressionLargeDrawKeepsItsInwardDiscardGesture() throws {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        let game = try match(seed: 10, after: 31)
        let table = game.table(for: .south)
        let tile = try XCTUnwrap(table.drawn)
        XCTAssertFalse(table.isGold(tile))
        XCTAssertTrue(table.moves.contains(.win))
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let app = try launchSavedMatch(game, arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
            let drawn = app.buttons["tile-\(tile.id)"]
            let ready = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: drawn)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
            XCTAssertGreaterThan(drawn.frame.midX, app.frame.midX)
            XCTAssertTrue(drawn.label.contains("刚摸到"))
            capture(orientation == .portrait ? "large-draw-portrait" : "large-draw-landscape")
            let start = drawn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -70, dy: -54)))
            XCTAssertTrue(drawn.waitForNonExistence(timeout: 3))
            app.terminate()
        }
    }

    func testAuditRegressionLargeTextOpponentWinKeepsRackAndShowsWideGroups() throws {
        XCUIDevice.shared.orientation = .portrait
        var game = try match(seed: 14, after: 29)
        while game.result == nil { try playFixtureMove(in: &game) }
        XCTAssertEqual(game.result?.winner, .west)
        let app = try launchSavedMatch(game, arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let reveal = app.scrollViews["winning-hand-scroll"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        let board = element("table-surface", in: app)
        XCTAssertGreaterThan(reveal.frame.width, board.frame.width * 0.85)
        XCTAssertGreaterThan(reveal.frame.height, 44)
        XCTAssertTrue(element("table-rack", in: app).exists)
        XCTAssertTrue(element("winning-hand-reveal", in: app).label.contains("自摸"))
        capture("large-text-opponent-win")
    }

    func testAuditRegressionOpponentTileCountAppearsAfterOpening() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", "", "--ui-test-manual-opening"]
        app.launch()
        openFreshSoloGame(app)

        let skip = app.buttons["skip-opening"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        let seat = element("seat-score-\(Seat.north.id)", in: app)
        let backs = element("concealed-rack-\(Seat.north.id)", in: app)
        let count = app.staticTexts["inspected-rack-count"]
        XCTAssertTrue(["正在洗牌", "正在摆牌", "正在发牌", "正在补花", "开金"].contains(backs.label), backs.label)
        seat.tap()
        let close = app.buttons["完成"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertFalse(count.exists)
        close.tap()
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(backs.label.hasPrefix("手牌 "))
        seat.tap()
        XCTAssertTrue(count.waitForExistence(timeout: 3))
    }

    func testWinRevealAndScorecardFollowTheSameHand() async throws {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        let cases: [(seed: UInt64, moves: Int, kind: WinKind?, winner: Seat?, label: String)] = [
            (35, 41, .discard, .south, "胡"),     // Player claims a discard after two melds.
            (14, 29, .selfDraw, .west, "自摸"),   // AI wins from its draw after two melds.
            (53518, 0, .robGold, .south, "抢金"),
            (0, 36, nil, nil, "流局"),
        ]

        for (index, fixture) in cases.enumerated() {
            let landscape = index == 1
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            let before = try match(seed: fixture.seed, after: fixture.moves)
            var completed = before
            while completed.result == nil { try playFixtureMove(in: &completed) }
            let result = try XCTUnwrap(completed.result)
            XCTAssertEqual(result.kind, fixture.kind)
            XCTAssertEqual(result.winner, fixture.winner)
            let app = try launchSavedMatch(before)
            XCTAssertFalse(app.buttons["skip-opening"].exists)
            let comparesNextHand = index == 0 || index == cases.count - 1
            let firstRackTile = element("table-rack", in: app).buttons.firstMatch
            let liveRackSlot = comparesNextHand ? try await settledRackSlot(firstRackTile) : nil
            let liveBoardTop = element("table-surface", in: app).frame.minY

            if before.result == nil, fixture.winner == .south {
                let board = element("table-surface", in: app)
                let actions = element("table-actions", in: app)
                XCTAssertTrue(actions.waitForExistence(timeout: 5))
                assertContains(board.frame, actions.frame)
                if fixture.kind == .discard {
                    XCTAssertTrue(element("latest-discard", in: app).exists)
                    XCTAssertFalse(actions.frame.intersects(element("latest-discard", in: app).frame))
                    capture("claim-actions")
                }
                let win = app.buttons["declare-win"]
                let pass = app.buttons["table-move-过"]
                XCTAssertGreaterThan(win.frame.width, pass.frame.width)
                XCTAssertGreaterThan(win.frame.height, pass.frame.height)
                win.tap()
            }

            let scorecard = app.buttons["view-scorecard"]
            XCTAssertTrue(scorecard.waitForExistence(timeout: 8))
            let board = element("table-surface", in: app)
            let settledFrame = board.frame
            let outcome = result.winner == nil ? "drawn-hand" : "winning-hand-reveal"
            capture("completed-\(index)")
            XCTAssertTrue(element(outcome, in: app).exists)
            XCTAssertTrue(element(outcome, in: app).label.contains(fixture.label))
            XCTAssertFalse(app.buttons["next-hand"].exists)
            let tableNext = app.buttons["table-next-hand"]
            XCTAssertTrue(tableNext.isHittable)
            XCTAssertTrue(element("table-score-delta", in: app).label.contains("\(result.delta(for: .south))"))
            if let winner = result.winner {
                let reveal = app.scrollViews["winning-hand-scroll"]
                XCTAssertTrue(reveal.exists)
                if winner == .south {
                    XCTAssertFalse(element("table-rack", in: app).exists)
                    if element("table-region", in: app).exists {
                        XCTAssertFalse(board.frame.intersects(reveal.frame))
                        assertContains(app.windows.firstMatch.frame, reveal.frame)
                    } else {
                        XCTAssertGreaterThan(reveal.frame.width, settledFrame.width * 0.85)
                        XCTAssertTrue(board.frame.contains(reveal.frame))
                    }
                    XCTAssertFalse(reveal.frame.intersects(scorecard.frame))
                } else if landscape {
                    XCTAssertTrue(element("table-rack", in: app).exists)
                    if element("table-region", in: app).exists {
                        // In split layouts the scorecard control also occupies the table pane.
                        assertContains(settledFrame, reveal.frame)
                        XCTAssertFalse(reveal.frame.intersects(scorecard.frame))
                        XCTAssertTrue(reveal.isHittable)
                    } else {
                        XCTAssertEqual(reveal.frame.minY, settledFrame.minY, accuracy: 2)
                        XCTAssertEqual(reveal.frame.maxY, settledFrame.maxY, accuracy: 2)
                    }
                    element("seat-score-\(winner.id)", in: app).tap()
                    let count = app.staticTexts["inspected-rack-count"]
                    XCTAssertTrue(count.waitForExistence(timeout: 5))
                    XCTAssertEqual(count.label, "手牌 \(result.winningHand.count) 张")
                    app.buttons["完成"].tap()
                    XCTAssertTrue(count.waitForNonExistence(timeout: 5))
                }
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "revealed-winning-tile").count, 1)
                XCTAssertTrue(element("winning-pair", in: app).exists)
                for meld in completed.table(for: .south).players[winner.id].melds {
                    XCTAssertTrue(element("revealed-meld-\(meld.id)", in: app).exists)
                }
            }

            if fixture.kind == .robGold {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(element(outcome, in: app).exists)
                XCTAssertTrue(scorecard.isHittable)
                XCUIDevice.shared.orientation = .portrait
            }

            scorecard.tap()
            let returnButton = app.buttons["return-to-table"]
            XCTAssertTrue(returnButton.waitForExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars["本局结算"].exists)
            XCTAssertTrue(returnButton.isHittable)
            if result.winner != nil {
                XCTAssertTrue(element("winning-pair", in: app).exists)
                XCTAssertTrue(element("score-total", in: app).label.contains("\(result.points)"))
                capture("grouped-scorecard-\(index)")
            }
            XCTAssertFalse(scorecard.isHittable)
            returnButton.tap()
            XCTAssertTrue(element(outcome, in: app).waitForExistence(timeout: 5))
            assertFrames([board.frame], match: [settledFrame])

            if let liveRackSlot {
                if index == 0 {
                    scorecard.tap()
                    app.buttons["next-hand"].tap()
                } else {
                    tableNext.tap()
                }
                let skip = app.buttons["skip-opening"]
                XCTAssertTrue(skip.waitForExistence(timeout: 5))
                XCTAssertFalse(returnButton.exists)
                skip.tap()
                XCTAssertTrue(skip.waitForNonExistence(timeout: 3))
                XCTAssertFalse(scorecard.exists)
                // The accessibility container can grow to include a draw or claim. Check the
                // top of the board and the first physical rack slot across the new deal.
                XCTAssertEqual(board.frame.minY, liveBoardTop, accuracy: 1)
                let nextRackSlot = try await settledRackSlot(firstRackTile)
                assertFrames([nextRackSlot], match: [liveRackSlot], labels: ["first rack tile"])
            }
            app.terminate()
        }
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func settledRackSlot(_ tile: XCUIElement) async throws -> CGRect {
        // The Duo can expose the incoming rack while navigation still changes the bottom inset.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        var previous = CGRect.null
        var unchangedSince = clock.now
        while clock.now < deadline {
            let frame = tile.exists ? tile.frame : .null
            if frame != previous {
                previous = frame
                unchangedSince = clock.now
            } else if !frame.isEmpty, unchangedSince.duration(to: clock.now) >= .milliseconds(650) {
                return frame
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("The first rack slot did not settle at a visible position. Last frame: \(previous)")
        return previous
    }

    private func openFreshSoloGame(_ app: XCUIApplication) {
        app.buttons["practice-entry"].tap()
        let start = app.buttons["start-solo-setup"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
    }

    private func assertHighlighted(_ ids: Set<Tile.ID>, in hand: [Tile], app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        for tile in hand {
            let highlighted = app.buttons["tile-\(tile.id)"].value as? String == "牌组候选"
            XCTAssertEqual(highlighted, ids.contains(tile.id), "Tile \(tile.id)", file: file, line: line)
        }
    }

    private func assertContains(_ outer: CGRect, _ inner: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        // Accessibility can round a shared parent/child edge to different fractions of a point.
        XCTAssertTrue(outer.insetBy(dx: -0.25, dy: -0.25).contains(inner),
                      "Expected \(outer) to contain \(inner)", file: file, line: line)
    }

    private func assertFrames(_ frames: [CGRect], match expected: [CGRect],
                              labels: [String] = ["board"],
                              file: StaticString = #filePath, line: UInt = #line) {
        for (label, (actual, original)) in zip(labels, zip(frames, expected)) {
            let difference = "\(label) moved from \(original) to \(actual)"
            XCTAssertEqual(actual.minX, original.minX, accuracy: 1, difference, file: file, line: line)
            XCTAssertEqual(actual.minY, original.minY, accuracy: 1, difference, file: file, line: line)
            XCTAssertEqual(actual.width, original.width, accuracy: 1, difference, file: file, line: line)
            XCTAssertEqual(actual.height, original.height, accuracy: 1, difference, file: file, line: line)
        }
    }

    private func capture(_ name: String, screenshot: XCUIScreenshot = XCUIScreen.main.screenshot()) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func savedMatchArguments(_ match: FuzhouMatch) throws -> [String] {
        let save = try JSONEncoder().encode(match).map { String(format: "%02x", $0) }.joined()
        // Foundation reads OpenStep data literals in the launch argument domain.
        return ["-play-access.archive.v1", "", "-solo-match.v2", "<\(save)>"]
    }

    private func launchSavedMatch(_ match: FuzhouMatch, arguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = try savedMatchArguments(match) + arguments
        app.launch()
        let practice = app.buttons["practice-entry"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        XCTAssertTrue(practice.label.contains("继续单机"))
        practice.tap()
        return app
    }

    private func olderSaveWithDecidedDiscard(houseRules: FuzhouHouseRules? = nil) throws -> FuzhouMatch {
        let match = try match(seed: 662, after: 24, houseRules: houseRules)
        XCTAssertTrue(match.legalMoves(for: .north).contains(.win))
        let data = try JSONEncoder().encode(match)
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Earlier versions saved the computer's Hu while still waiting for the player's Pung or Pass.
        saved["responses"] = [
            ["pending": ["_0": Seat.south.rawValue]],
            ["chose": ["_0": Seat.north.rawValue, "_1": ["win": [String: String]()]]],
        ]
        return try JSONDecoder().decode(FuzhouMatch.self, from: JSONSerialization.data(withJSONObject: saved))
    }

    private func match(seed: UInt64, after moves: Int, houseRules: FuzhouHouseRules? = nil) throws -> FuzhouMatch {
        var random = FixtureRandom(seed: seed)
        var match = FuzhouMatch(using: &random, ruleset: .pureSuit, houseRules: houseRules)
        for _ in 0..<moves { try playFixtureMove(in: &match) }
        return match
    }

    private func playFixtureMove(in match: inout FuzhouMatch) throws {
        let seat = try XCTUnwrap(Seat.allCases.first { !match.legalMoves(for: $0).isEmpty })
        let moves = match.legalMoves(for: seat)
        let meld = moves.first { if case .meld = $0 { true } else { false } }
        let move: Move = moves.contains(.win) ? .win : meld ?? (moves.contains(.pass) ? .pass : moves[0])
        XCTAssertTrue(match.apply(move, by: seat))
    }
}

private struct FixtureRandom: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var result = seed
        result = (result ^ (result >> 30)) &* 0xBF58476D1CE4E5B9
        result = (result ^ (result >> 27)) &* 0x94D049BB133111EB
        return result ^ (result >> 31)
    }
}
