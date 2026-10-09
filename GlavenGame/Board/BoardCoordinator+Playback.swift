import Foundation

/// Pause and fast-forward for the turns that play themselves (monsters, summons, escorts).
/// Every pause those turns take goes through `beat`, which is where both take hold: a paused
/// game stops at its next step, and fast-forward shortens the pauses and quickens the board.
extension BoardCoordinator {

    /// How much faster fast-forward plays.
    static let fastForwardFactor = 4.0

    /// Whether the figure acting now plays itself, so the pace controls apply.
    var isAutomatedTurn: Bool {
        if case .watchingMonsterTurn = interactionMode { return true }
        return false
    }

    /// One step's pause in an automated turn, `factor` times the usual length: held while paused,
    /// shortened by fast-forward.
    @MainActor func beat(_ factor: Double = 1) async {
        await waitWhilePaused()
        let pause = Self.beatNanoseconds(base: turnDelayNanoseconds, factor: factor, fastForward: isFastForward)
        if pause > 0 { try? await Task.sleep(nanoseconds: pause) }
        await waitWhilePaused()
    }

    static func beatNanoseconds(base: UInt64, factor: Double, fastForward: Bool) -> UInt64 {
        UInt64(Double(base) * factor / (fastForward ? fastForwardFactor : 1))
    }

    /// The board's animation speed for the Animation Speed setting (0.5 fast … 2 slow).
    static func sceneSpeed(animationSpeed: Double, fastForward: Bool) -> Double {
        (1 / animationSpeed) * (fastForward ? fastForwardFactor : 1)
    }

    /// Wait here while the game is paused (and the board is still this one).
    @MainActor func waitWhilePaused() async {
        let generation = boardGeneration
        while isPaused && isCurrentBoard(generation) {
            await withCheckedContinuation { pauseWaiters.append($0) }
        }
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if !paused { releasePauseWaiters() }
    }

    func setFastForward(_ on: Bool) {
        isFastForward = on
        boardScene?.speed = CGFloat(Self.sceneSpeed(animationSpeed: animationSpeed, fastForward: on))
    }

    /// Back to the normal pace, unpaused: when a character's turn or a new round comes, or the
    /// board is left.
    func endPlaybackControls() {
        isPaused = false
        releasePauseWaiters()
        if isFastForward { setFastForward(false) }
    }

    private func releasePauseWaiters() {
        let waiters = pauseWaiters
        pauseWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}
