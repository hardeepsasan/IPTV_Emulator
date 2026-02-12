import SwiftUI
import UIKit

struct SearchFieldView: UIViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onUpdate: (String) -> Void
    var onEditingBegan: (() -> Void)?
    var onExit: (() -> Void)? // Callback for Menu/Escape key
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> NativeSearchField {
        let textField = NativeSearchField()
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        // REMOVED: primaryActionTriggered target to allow native keyboard to open
        return textField
    }

    func updateUIView(_ uiView: NativeSearchField, context: Context) {
        if uiView.text != text {
            DispatchQueue.main.async {
                uiView.text = text
            }
        }
        
        // Pass the exit handler to the native view
        uiView.onMenuPress = onExit
        
        // Handle Programmatic Focus (if needed)
        // ...
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchFieldView

        init(parent: SearchFieldView) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            let newText = textField.text ?? ""
            if parent.text != newText {
                parent.text = newText
                parent.onUpdate(newText)
            }
        }
        
        // No longer triggered by primaryActionTriggered, only by Keyboard "Return"
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onCommit()
            return true
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
            parent.onEditingBegan?() // Notify parent to clear results
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            // parent.isFocused = false
        }
    }
}

// Custom UITextField Subclass for Precise tvOS Styling
class NativeSearchField: UITextField {
    
    private let iconView = UIImageView()
    var onMenuPress: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu {
                onMenuPress?() // Trigger side-effect (Scroll Reset)
            }
        }
        super.pressesBegan(presses, with: event) // Allow system handling (Resign Focus)
    }
    
    private func setupView() {
        // Base Styling
        self.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        self.layer.cornerRadius = 25 // Half of height 50
        self.layer.masksToBounds = true
        
        // Text Styling
        self.textColor = .white
        self.tintColor = .black // Cursor color
        self.font = UIFont.preferredFont(forTextStyle: .headline)
        self.textAlignment = .center
        
        // Placeholder
        self.attributedPlaceholder = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: UIColor.lightGray]
        )
        
        // Default Icon Styling
        iconView.image = UIImage(systemName: "magnifyingglass")
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .lightGray
        
        // Icon Layout (Left View)
        let iconContainer = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 50))
        iconView.frame = CGRect(x: 20, y: 12.5, width: 25, height: 25)
        iconContainer.addSubview(iconView)
        
        self.leftView = iconContainer
        self.leftViewMode = .always
        self.returnKeyType = .search
    }
    
    // Handle Focus Appearance
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        
        let isFocusedNow = (context.nextFocusedView == self)
        
        // Update Placeholder Contrast
        let placeholderColor: UIColor = isFocusedNow ? .black : .lightGray
        self.attributedPlaceholder = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: placeholderColor]
        )
        
        // Simple property updates - avoid complex coordinate animations that trigger ReplicantView
        UIView.animate(withDuration: 0.2) {
            if isFocusedNow {
                self.backgroundColor = .white
                self.textColor = .black
                self.iconView.tintColor = .black
            } else {
                self.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
                self.textColor = .white
                self.iconView.tintColor = .lightGray
            }
        }
    }
}
