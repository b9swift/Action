/*
 B9Action.swift

 Copyright © 2021 BB9z.
 https://github.com/b9swift/Action

 The MIT License
 https://opensource.org/licenses/MIT
 */

import Foundation

/**
 A simple base component whose main purpose is to provide a unified interface for target/selector patterns and block calls.
 */
public final class Action {
    /// The object that receives the selector message when the action is triggered.
    public weak var target: AnyObject?

    /// The message sent to the target when the action is triggered.
    public var selector: Selector?

    /// The closure executed when the action is triggered.
    public var block: (() -> Void)?

    /// The reference object set when the action is initialized. When this object is released, the action will become invalid and no operation can be executed.
    private(set) weak var reference: AnyObject?
    private let hasReferenceSet: Bool

    /// Create an Action object with target/selector patterns
    ///
    /// - Parameters:
    ///   - target: The `target` property.
    ///   - selector: The `selector` property.
    ///   - reference: The `reference` property.
    public init(target: AnyObject?, selector: Selector, reference: AnyObject? = nil) {
        self.target = target
        self.selector = selector
        hasReferenceSet = reference != nil
        self.reference = reference
    }

    /// Create an action object with closure call
    ///
    /// - Parameters:
    ///   - action: The `block` property.
    ///   - reference: The `reference` property.
    public init(_ action: @escaping () -> Void, reference: AnyObject? = nil) {
        block = action
        hasReferenceSet = reference != nil
        self.reference = reference
    }

    /// Perform this action
    ///
    /// If target, selector and block are not nil, the selector will be sent to the target first, and then the block will be called.
    ///
    /// - Parameter obj: An object sent with the selector message to the target, ignored when the closure is called.
    public func perform(with obj: Any?) {
        guard isVaild else { return }
        if let selector = selector {
            _ = target?.perform(selector, with: obj)
        }
        if let action = block {
            action()
        }
    }

    /// Whether this action is still or not. Execute the perform method with no action if the action is invalid.
    ///
    /// If a reference object is set during initialization, it is valid only when the reference is not released.
    public var isVaild: Bool {
        if hasReferenceSet, reference == nil { return false }
        return true
    }
}

#if os(iOS)
import UIKit

extension Action {
    /// Perform action through responder chain.
    ///
    /// Must be called on the main queue
    ///
    /// - Parameter sender: An object sent with the selector message to the target, ignored when the closure is called.
    public func perform(sender: Any?) {
        if #available(iOS 10.0, *) {
            dispatchPrecondition(condition: .onQueue(.main))
        }
        guard isVaild else { return }
        if let selector = selector {
            UIApplication.shared.sendAction(selector, to: target, from: sender, for: nil)
        }
        if let action = block {
            action()
        }
    }
}

#elseif os(macOS)
import AppKit

extension Action {
    /// Perform action through responder chain.
    ///
    /// Must be called on the main queue
    ///
    /// - Parameter sender: An object sent with the selector message to the target, ignored when the closure is called.
    public func perform(sender: Any?) {
        if #available(macOS 10.12, *) {
            dispatchPrecondition(condition: .onQueue(.main))
        }
        guard isVaild else { return }
        if let selector = selector {
            NSApp.sendAction(selector, to: target, from: sender)
        }
        if let action = block {
            action()
        }
    }
}

#endif

extension Action: CustomDebugStringConvertible {
    public var debugDescription: String {
        let properties: [(String, Any?)] = [("target", target), ("selector", selector), ("block", block), ("reference", reference), ("isVaild", isVaild)]
        let propertyDiscription = properties.compactMap { key, value in
            if let value = value {
                return "\(key) = \(value)"
            }
            return nil
        }.joined(separator: ", ")
        return "<Action \(Unmanaged.passUnretained(self).toOpaque()): \(propertyDiscription)>"
    }
}

/**
 Perform an action object after delay. Typical scenarios: setNeedsDoSomething pattern.

 eg.
 ```
 // Create delay controller
 lazy var needsSave = DelayAction(delay: 0.3, action: Action(target: self, selector: #selector(save)))

 // Called when saving is required
 needsSave.set()
 ```
 */
public final class DelayAction {
    /// An action object.
    public let action: Action

    /// The queue which the action is performed on.
    public let queue: DispatchQueue

    /// The length of time that the action needs to be delayed.
    public let delay: TimeInterval

    /// Create a DelayAction object
    ///
    /// - Parameters:
    ///   - action: An action object
    ///   - delay: The duration of the action is delayed. Must not be negative.
    ///   - queue: Action will be performed on this queue. If not specified, the main queue will be use.
    public init(_ action: Action, delay: TimeInterval = 0, queue: DispatchQueue = .main) {
        precondition(delay >= 0)
        self.action = action
        self.delay = delay
        self.queue = queue
    }

    deinit {
        work?.cancel()
    }

    /// Mark the action needs to be performed. The actual operation will be triggered on the specified queue after a certain delay.
    ///
    /// - Parameter reschedule: Reschedule the delay time for true
    public func set(reschedule: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        if needs {
            if !reschedule { return }
        }
        needs = true
        let newItem = DispatchWorkItem { self.fired() }
        queue.asyncAfter(deadline: .now() + delay, execute: newItem)
        work?.cancel()
        work = newItem
    }

    /// Reset the marks and cancel any scheduled.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        needs = false
        work?.cancel()
        work = nil
    }

    private let lock = NSLock()
    private var needs: Bool = false
    private var work: DispatchWorkItem?

    private func fired() {
        lock.lock()
        guard needs else {
            lock.unlock()
            return
        }
        needs = false
        work = nil
        lock.unlock()
        action.perform(with: nil)
    }
}
