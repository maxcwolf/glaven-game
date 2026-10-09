import XCTest
import SpriteKit
@testable import GlavenGameLib

/// The board camera frames the whole board in the part of the view the HUD leaves clear, never
/// pans the board out of sight, zooms where the fingers are, and follows the figure acting.
@MainActor
final class BoardCameraTests: XCTestCase {

    /// iPad Pro 13" landscape: the HUD and turn rail along the top, the party and the monsters
    /// down the sides, the turn's card and buttons along the bottom.
    private let iPadPro = BoardViewport(size: CGSize(width: 1376, height: 1032), obstacles: [
        CGRect(x: 0, y: 0, width: 1376, height: 215), CGRect(x: 0, y: 215, width: 350, height: 817),
        CGRect(x: 1020, y: 215, width: 356, height: 817), CGRect(x: 350, y: 752, width: 670, height: 280),
    ])
    /// iPad mini landscape, same panels.
    private let iPadMini = BoardViewport(size: CGSize(width: 1133, height: 744), obstacles: [
        CGRect(x: 0, y: 0, width: 1133, height: 200), CGRect(x: 0, y: 200, width: 330, height: 544),
        CGRect(x: 803, y: 200, width: 330, height: 544), CGRect(x: 330, y: 514, width: 473, height: 230),
    ])

    // MARK: - Geometry

    func testFittingPutsTheWholeBoardInTheClearArea() {
        let board = CGRect(x: -300, y: -200, width: 900, height: 700)
        for viewport in [iPadPro, iPadMini] {
            let camera = BoardCamera.fitting(board, in: viewport)
            for corner in corners(of: board) {
                XCTAssertTrue(viewport.clearRect.contains(camera.viewPoint(of: corner, in: viewport)),
                              "\(corner) is in the clear area of \(viewport.size)")
            }
        }
    }

    func testASmallBoardIsntBlownUp() {
        let camera = BoardCamera.fitting(CGRect(x: 0, y: 0, width: 200, height: 200), in: iPadPro)
        XCTAssertEqual(camera.scale, 1, "1:1 at most")
    }

    func testAHugeBoardStopsAtTheZoomLimit() {
        let camera = BoardCamera.fitting(CGRect(x: 0, y: 0, width: 50_000, height: 50_000), in: iPadPro)
        XCTAssertEqual(camera.scale, BoardCamera.scaleRange.upperBound)
    }

    func testPanelsThatLeaveNoRoomFallBackToTheWholeView() {
        let cramped = BoardViewport(size: CGSize(width: 600, height: 400),
                                    obstacles: [CGRect(x: 0, y: 0, width: 600, height: 300)])
        XCTAssertEqual(cramped.clearRect, CGRect(x: 0, y: 0, width: 600, height: 400))
    }

    /// However far the player drags, some of the board stays in the clear area.
    func testPanningNeverLosesTheBoard() {
        let board = CGRect(x: 0, y: 0, width: 900, height: 700)
        let fitted = BoardCamera.fitting(board, in: iPadPro)
        XCTAssertEqual(fitted.clamped(to: board, in: iPadPro), fitted, "a fitted camera is left alone")
        for direction in [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1),
                          CGPoint(x: 1, y: 1), CGPoint(x: -1, y: -1)] {
            for scale in [BoardCamera.scaleRange.lowerBound, 1, BoardCamera.scaleRange.upperBound] {
                var camera = BoardCamera(position: CGPoint(x: direction.x * 100_000, y: direction.y * 100_000), scale: scale)
                camera = camera.clamped(to: board, in: iPadPro)
                let seen = CGRect(origin: camera.viewPoint(of: CGPoint(x: board.minX, y: board.maxY), in: iPadPro),
                                  size: CGSize(width: board.width / scale, height: board.height / scale))
                let overlap = seen.intersection(iPadPro.clearRect)
                XCTAssertGreaterThanOrEqual(overlap.width, min(BoardCamera.keepVisible, seen.width) - 0.5,
                                            "\(direction) at \(scale)")
                XCTAssertGreaterThanOrEqual(overlap.height, min(BoardCamera.keepVisible, seen.height) - 0.5,
                                            "\(direction) at \(scale)")
            }
        }
    }

    /// A pinch zooms where the fingers are: the point under them doesn't move.
    func testZoomKeepsThePointUnderTheFingers() {
        let camera = BoardCamera(position: CGPoint(x: 120, y: -40), scale: 1)
        let fingers = CGPoint(x: 900, y: 300)
        let under = camera.scenePoint(at: fingers, in: iPadPro)
        for factor: CGFloat in [0.5, 2] {
            let zoomed = camera.zoomed(to: camera.scale / factor, around: fingers, in: iPadPro)
            let after = zoomed.viewPoint(of: under, in: iPadPro)
            XCTAssertEqual(after.x, fingers.x, accuracy: 0.001)
            XCTAssertEqual(after.y, fingers.y, accuracy: 0.001)
        }
        let tooFar = camera.zoomed(to: 0.001, around: fingers, in: iPadPro)
        XCTAssertEqual(tooFar.scale, BoardCamera.scaleRange.lowerBound)
    }

    func testShowingAPointPansOnlyWhenItIsOutOfView() {
        let camera = BoardCamera(position: .zero, scale: 1)
        let center = camera.scenePoint(at: CGPoint(x: iPadPro.clearRect.midX, y: iPadPro.clearRect.midY), in: iPadPro)
        XCTAssertEqual(camera.showing(center, in: iPadPro), camera)

        let offscreen = CGPoint(x: 2_000, y: -1_500)
        let moved = camera.showing(offscreen, in: iPadPro)
        XCTAssertTrue(iPadPro.clearRect.insetBy(dx: 89, dy: 89).contains(moved.viewPoint(of: offscreen, in: iPadPro)))
        XCTAssertEqual(moved.scale, camera.scale, "following pans, it doesn't zoom")
    }

    func testTheClearAreaIsTheLargestGapBetweenPanels() {
        XCTAssertEqual(iPadPro.clearRect, CGRect(x: 350, y: 215, width: 670, height: 537))
        // The turn's card at the bottom left and the monster cards at the bottom right leave the
        // board free between them, down to the bottom edge.
        let split = BoardViewport(size: CGSize(width: 1376, height: 1032), obstacles: [
            CGRect(x: 0, y: 0, width: 1376, height: 200), CGRect(x: 0, y: 200, width: 350, height: 400),
            CGRect(x: 1020, y: 200, width: 356, height: 500), CGRect(x: 0, y: 640, width: 560, height: 392),
            CGRect(x: 1180, y: 820, width: 196, height: 212),
        ])
        XCTAssertEqual(split.clearRect, CGRect(x: 560, y: 200, width: 460, height: 832))
    }

    /// Between a tall gap and a wide one, the board goes where it shows largest.
    func testTheBoardGoesInTheGapThatShowsItLargest() {
        // The turn's card covers the bottom of the middle column's left part: a tall gap on the
        // right, a wide one above.
        var viewport = BoardViewport(size: CGSize(width: 1376, height: 1032), obstacles: [
            CGRect(x: 0, y: 0, width: 1376, height: 215), CGRect(x: 0, y: 215, width: 350, height: 817),
            CGRect(x: 1020, y: 215, width: 356, height: 817), CGRect(x: 0, y: 630, width: 620, height: 402),
        ])
        let tall = CGRect(x: 620, y: 215, width: 400, height: 817)
        let wide = CGRect(x: 350, y: 215, width: 670, height: 415)
        viewport.contentSize = CGSize(width: 900, height: 500)
        XCTAssertEqual(viewport.clearRect, wide)
        viewport.contentSize = CGSize(width: 400, height: 1000)
        XCTAssertEqual(viewport.clearRect, tall)
    }

    func testPanelFramesAreMadeRelativeToTheBoard() {
        let board = CGRect(x: 0, y: -20, width: 1376, height: 1052)
        let obstacles = BoardViewport.obstacles([CGRect(x: 0, y: 0, width: 1376, height: 200), .zero,
                                                 CGRect(x: 1300, y: 1000, width: 200, height: 200)], over: board)
        XCTAssertEqual(obstacles, [CGRect(x: 0, y: 20, width: 1376, height: 200),
                                   CGRect(x: 1300, y: 1020, width: 76, height: 32)],
                       "moved into the board's space, clipped to it, empty frames dropped")
    }

    /// A short party panel still keeps the whole left column: the board doesn't slide under it
    /// during card selection only to be covered when the turn's tray appears.
    func testSidePanelsKeepTheirWholeColumn() {
        var frames = BoardView.HUDFrames()
        frames.board = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        frames.hud = CGRect(x: 0, y: 0, width: 1376, height: 160)
        frames.left = CGRect(x: 0, y: 160, width: 350, height: 190)
        frames.right = CGRect(x: 1020, y: 160, width: 356, height: 600)
        let obstacles = frames.obstacles(showingSidePanels: true)
        XCTAssertTrue(obstacles.contains(CGRect(x: 0, y: 160, width: 350, height: 872)))
        XCTAssertTrue(obstacles.contains(CGRect(x: 1020, y: 160, width: 356, height: 872)))
        let viewport = BoardViewport(size: frames.board.size, obstacles: obstacles, contentSize: CGSize(width: 900, height: 600))
        XCTAssertEqual(viewport.clearRect, CGRect(x: 350, y: 160, width: 670, height: 872))

        XCTAssertEqual(frames.obstacles(showingSidePanels: false), [frames.hud], "hidden panels cover nothing")
    }

    // MARK: - The scene

    /// Every revealed hex of real scenario maps lands in the clear area once the board is shown.
    func testRealBoardsAreFramedInTheClearArea() throws {
        for index in ["1", "11", "32", "52", "72"] {
            for viewport in [iPadPro, iPadMini] {
                let (coord, view) = try presentedBoard(index, allRooms: true, viewport: viewport)
                let scene = try XCTUnwrap(coord.boardScene)
                assertBoardFramed(scene, coord: coord, view: view, in: viewport, "scenario \(index) at \(viewport.size)")
            }
        }
    }

    /// Dragging or zooming as far as the player likes leaves part of the board in the clear area.
    func testTheBoardCantBeDraggedAway() throws {
        let (coord, view) = try presentedBoard("32", allRooms: true, viewport: iPadPro)
        let scene = try XCTUnwrap(coord.boardScene)
        for drag in [CGVector(dx: 100_000, dy: 0), CGVector(dx: -100_000, dy: 0),
                     CGVector(dx: 0, dy: 100_000), CGVector(dx: 0, dy: -100_000)] {
            scene.zoom(by: 4, around: CGPoint(x: 1300, y: 1000))
            scene.pan(by: drag)
            let inView = coord.boardState.cells.keys.filter {
                iPadPro.clearRect.contains(viewPoint(of: scene.sceneCenter(of: $0), scene: scene, view: view))
            }
            XCTAssertFalse(inView.isEmpty, "after dragging \(drag) some of the board is still in view")
        }
    }

    /// The camera follows the figure whose turn it is when it's off screen.
    func testTheCameraFollowsTheActingFigure() throws {
        let (coord, view) = try presentedBoard("32", allRooms: true, viewport: iPadMini)
        let scene = try XCTUnwrap(coord.boardScene)
        let piece = try XCTUnwrap(coord.boardState.piecePositions.keys.sorted().first)
        let hex = try XCTUnwrap(coord.boardState.piecePositions[piece])
        // Look far away from it, zoomed in.
        scene.zoom(by: 3, around: CGPoint(x: 500, y: 400))
        scene.pan(by: CGVector(dx: 5_000, dy: 5_000))
        XCTAssertFalse(scene.viewport.clearRect.contains(viewPoint(of: scene.sceneCenter(of: hex), scene: scene, view: view)))

        scene.setActingPiece(piece)
        let seen = viewPoint(of: scene.sceneCenter(of: hex), scene: scene, view: view)
        XCTAssertTrue(scene.viewport.clearRect.contains(seen), "\(piece) is brought into view: \(seen)")
    }

    /// Opening a door frames the board again so the new room is seen.
    func testARevealedRoomIsFramed() throws {
        let (coord, view) = try presentedBoard("1", allRooms: false, viewport: iPadPro)
        let scene = try XCTUnwrap(coord.boardScene)
        scene.pan(by: CGVector(dx: 400, dy: -300))
        XCTAssertTrue(scene.userMovedCamera)
        let cellsBefore = coord.boardState.cells.count
        let door = try XCTUnwrap(coord.boardState.doors.sorted { $0.coord < $1.coord }.first { !$0.isOpen })
        coord.openDoor(at: door.coord)
        XCTAssertGreaterThan(coord.boardState.cells.count, cellsBefore, "a room opened")
        assertBoardFramed(scene, coord: coord, view: view, in: iPadPro, "after the reveal")
    }

    /// Undo rebuilds the board without moving the camera.
    func testRebuildingKeepsThePlayersView() throws {
        let (coord, _) = try presentedBoard("1", allRooms: false, viewport: iPadPro)
        let scene = try XCTUnwrap(coord.boardScene)
        scene.zoom(by: 1.5, around: CGPoint(x: 700, y: 500))
        let before = scene.cameraState
        coord.restore(from: coord.snapshot())
        XCTAssertEqual(scene.cameraState, before)
    }

    /// A panel that grows over the board reframes it — the execution bar appearing after card
    /// selection must not hide the bottom of the board.
    func testAPanelGrowingOverTheBoardReframesIt() throws {
        let withoutBar = BoardViewport(size: iPadPro.size, obstacles: Array(iPadPro.obstacles.dropLast()))
        let (coord, view) = try presentedBoard("1", allRooms: true, viewport: withoutBar)
        let scene = try XCTUnwrap(coord.boardScene)
        scene.setHUDObstacles(iPadPro.obstacles)
        assertBoardFramed(scene, coord: coord, view: view, in: iPadPro, "after the execution bar appears")

        // It shrinking again doesn't zoom back in: the board doesn't pump every round.
        let framed = scene.cameraState
        scene.setHUDObstacles(withoutBar.obstacles)
        XCTAssertEqual(scene.cameraState, framed)
    }

    /// Once the player has set their own view, panels coming and going leave it alone — unless
    /// they asked for a reframe by showing or hiding the side panels.
    func testPanelChangesLeaveThePlayersView() throws {
        let (coord, _) = try presentedBoard("1", allRooms: true, viewport: iPadPro)
        let scene = try XCTUnwrap(coord.boardScene)
        scene.pan(by: CGVector(dx: 60, dy: 0))
        let moved = scene.cameraState
        scene.setHUDObstacles(iPadPro.obstacles + [CGRect(x: 350, y: 500, width: 670, height: 300)])
        XCTAssertEqual(scene.cameraState, moved, "a growing panel leaves the player's view alone")

        scene.refitWhenHUDChanges()
        scene.setHUDObstacles([iPadPro.obstacles[0]])
        let fitted = BoardCamera.fitting(scene.boardContentRect, in: scene.viewport)
        XCTAssertEqual(scene.cameraState.position.x, fitted.position.x, accuracy: 0.01, "reframed")
        XCTAssertEqual(scene.cameraState.position.y, fitted.position.y, accuracy: 0.01)
        XCTAssertEqual(scene.cameraState.scale, fitted.scale, accuracy: 0.0001)
    }

    // MARK: - Helpers

    /// The games under test (the coordinator holds its manager weakly).
    private var managers: [GameManager] = []

    private func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    /// Start scenario `index` with its characters placed, show it in a view of the viewport's
    /// size, and report the viewport's HUD insets as the board view would.
    private func presentedBoard(_ index: String, allRooms: Bool,
                                viewport: BoardViewport) throws -> (BoardCoordinator, SKView) {
        let gm = try SaveAndContinueTestsSupport.manager()
        managers.append(gm)
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        for character in gm.game.characters {
            let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
            coord.placeCharacter(characterID: character.id, at: free)
        }
        coord.finishSetup()
        if allRooms { coord.openScenarioRooms((scenario.rooms ?? []).compactMap(\.roomNumber)) }
        let scene = try XCTUnwrap(coord.boardScene)
        scene.reduceMotion = true
        let view = SKView(frame: CGRect(origin: .zero, size: viewport.size))
        view.presentScene(scene)
        XCTAssertEqual(scene.size, viewport.size, "the scene fills the view")
        scene.setHUDObstacles(viewport.obstacles)
        return (coord, view)
    }

    /// A scene point in view points, y down, through SpriteKit's own conversion — not the
    /// camera maths under test.
    private func viewPoint(of point: CGPoint, scene: BoardScene, view: SKView) -> CGPoint {
        let converted = scene.convertPoint(toView: point)
        return view.isFlipped ? converted : CGPoint(x: converted.x, y: view.bounds.height - converted.y)
    }

    /// Every revealed hex is in the viewport's clear area — the one the test set up, not the
    /// scene's own idea of it.
    private func assertBoardFramed(_ scene: BoardScene, coord: BoardCoordinator, view: SKView,
                                   in viewport: BoardViewport, _ label: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let clear = viewport.clearRect
        if scene.cameraState.scale >= BoardCamera.scaleRange.upperBound - 0.0001 {
            // Too big to fit even zoomed all the way out: at least centred on the clear area.
            let mid = viewPoint(of: CGPoint(x: scene.boardContentRect.midX, y: scene.boardContentRect.midY),
                                scene: scene, view: view)
            XCTAssertEqual(mid.x, clear.midX, accuracy: 1, label, file: file, line: line)
            XCTAssertEqual(mid.y, clear.midY, accuracy: 1, label, file: file, line: line)
            return
        }
        for hex in coord.boardState.cells.keys.sorted() {
            let seen = viewPoint(of: scene.sceneCenter(of: hex), scene: scene, view: view)
            XCTAssertTrue(clear.contains(seen), "\(label): \(hex) at \(seen) is outside \(clear)", file: file, line: line)
        }
    }
}
