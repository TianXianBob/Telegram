import UIKit

public struct KeyShortcut: Hashable {
    let title: String
    let input: String
    let modifiers: UIKeyModifierFlags
    let action: () -> Void
    
    public init(title: String = "", input: String = "", modifiers: UIKeyModifierFlags = [], action: @escaping () -> Void = {}) {
        self.title = title
        self.input = input
        self.modifiers = modifiers
        self.action = action
    }
    
    public var hashValue: Int {
        return input.hashValue ^ modifiers.hashValue
    }
    
    public static func ==(lhs: KeyShortcut, rhs: KeyShortcut) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}

extension UIKeyModifierFlags: Hashable {
    public var hashValue: Int {
        return self.rawValue
    }
}

extension KeyShortcut {
    var uiKeyCommand: UIKeyCommand {
        if #available(iOSApplicationExtension 9.0, iOS 9.0, *), !self.title.isEmpty {
            return UIKeyCommand(input: self.input, modifierFlags: self.modifiers, action: #selector(KeyShortcutsController.handleKeyCommand(_:)), discoverabilityTitle: self.title)
        } else {
            return UIKeyCommand(input: self.input, modifierFlags: self.modifiers, action: #selector(KeyShortcutsController.handleKeyCommand(_:)))
        }
    }
    
    func isEqual(to command: UIKeyCommand) -> Bool {
        return self.input == command.input && self.modifiers == command.modifierFlags
    }
}
