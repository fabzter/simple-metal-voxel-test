import Foundation

@MainActor
final class GameLoop: NSObject {
    typealias Step = (Float) -> Void

    private let step: Step
    private var lastTime = CFAbsoluteTimeGetCurrent()
    private var timer: Timer?

    init(step: @escaping Step) {
        self.step = step
    }

    func start() {
        stop()
        lastTime = CFAbsoluteTimeGetCurrent()

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let dt = Float(min(currentTime - lastTime, 0.05))
        lastTime = currentTime
        step(dt)
    }
}
