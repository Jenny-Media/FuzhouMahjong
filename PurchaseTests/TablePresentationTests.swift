import FuzhouCore
import SwiftUI
import XCTest
@testable import FuzhouMahjong

@MainActor
final class TablePresentationTests: XCTestCase {
    func testGuestSeatInspectorDismissesWhenHostDealsAgain() async throws {
        var game = FuzhouMatch()
        while game.result == nil, let (seat, move) = game.nextComputerMove(excluding: []) {
            XCTAssertTrue(game.apply(move, by: seat))
        }
        XCTAssertNotNil(game.result)
        let model = InspectorFixture(table: game.table(for: .south))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: InspectorBoard(model: model))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        model.selection = .east
        try await waitFor { controller.presentedViewController != nil }
        game.nextRound()
        model.table = game.table(for: .south)
        try await waitFor { model.selection == nil && controller.presentedViewController == nil }
    }

    private func waitFor(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

@MainActor @Observable
private final class InspectorFixture {
    var table: TableState
    var selection: Seat?
    init(table: TableState) { self.table = table }
}

private struct InspectorBoard: View {
    @Bindable var model: InspectorFixture

    var body: some View {
        GeometryReader { geometry in
            LiveTable(table: model.table, names: [:], latest: nil, opening: nil, drawingFromReserve: nil,
                      paused: false, size: geometry.size, showsDrawDock: false, flyingDiscard: nil, flyingClaim: nil,
                      inspectedSeat: $model.selection, onOfferedTileFrame: { _, _ in }) {
                EmptyView()
            } drawDock: { EmptyView() }
        }
    }
}
