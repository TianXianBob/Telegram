import Foundation
import UIKit

private final class DisplayLinkTarget: NSObject {
    private let f: () -> Void
    
    init(_ f: @escaping () -> Void) {
        self.f = f
    }
    
    @objc func event() {
        self.f()
    }
}

public final class DisplayLinkAnimator {
    private var displayLink: CADisplayLink!
    private let duration: Double
    private let fromValue: CGFloat
    private let toValue: CGFloat
    private let startTime: Double
    private let update: (CGFloat) -> Void
    private let completion: () -> Void
    private var completed = false
    
    public init(duration: Double, from fromValue: CGFloat, to toValue: CGFloat, update: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        self.duration = duration
        self.fromValue = fromValue
        self.toValue = toValue
        self.update = update
        self.completion = completion
        
        self.startTime = CACurrentMediaTime()
        
        self.displayLink = CADisplayLink(target: DisplayLinkTarget({ [weak self] in
            self?.tick()
        }), selector: #selector(DisplayLinkTarget.event))
        self.displayLink.isPaused = false
        self.displayLink.add(to: RunLoop.main, forMode: .common)
    }
    
    deinit {
        self.displayLink.isPaused = true
        self.displayLink.invalidate()
    }
    
    public func invalidate() {
        self.displayLink.isPaused = true
        self.displayLink.invalidate()
    }
    
    @objc private func tick() {
        if self.completed {
            return
        }
        let timestamp = CACurrentMediaTime()
        var t = (timestamp - self.startTime) / self.duration
        t = max(0.0, t)
        t = min(1.0, t)
        self.update(self.fromValue * CGFloat(1 - t) + self.toValue * CGFloat(t))
        if abs(t - 1.0) < Double.ulpOfOne {
            self.completed = true
            self.displayLink.isPaused = true
            self.completion()
        }
    }
}

public final class ConstantDisplayLinkAnimator {
    private var displayLink: CADisplayLink!
    private let update: () -> Void
    private var completed = false
    
    public var isPaused: Bool = true {
        didSet {
            if self.isPaused != oldValue {
                self.displayLink.isPaused = self.isPaused
            }
        }
    }
    
    public init(update: @escaping () -> Void) {
        self.update = update
        
        self.displayLink = CADisplayLink(target: DisplayLinkTarget({ [weak self] in
            self?.tick()
        }), selector: #selector(DisplayLinkTarget.event))
        self.displayLink.isPaused = true
        self.displayLink.add(to: RunLoop.main, forMode: .common)
    }
    
    deinit {
        self.displayLink.isPaused = true
        self.displayLink.invalidate()
    }
    
    public func invalidate() {
        self.displayLink.isPaused = true
        self.displayLink.invalidate()
    }
    
    @objc private func tick() {
        if self.completed {
            return
        }
        self.update()
    }
}

