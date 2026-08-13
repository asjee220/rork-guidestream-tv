//  FocusedSearchField.swift
//  GuideStreamTV
//
//  UIKit-backed search field that reliably summons the keyboard when presented
//  inside a .fullScreenCover. SwiftUI @FocusState frequently fails to bring up
//  the keyboard in that presentation context, so we drive the underlying
//  UITextField directly with becomeFirstResponder().
//

import SwiftUI
import UIKit

struct FocusedSearchField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.text = text
        field.placeholder = placeholder
        field.textColor = .white
        field.tintColor = UIColor(Color.orange)
        field.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.returnKeyType = .search
        field.enablesReturnKeyAutomatically = false
        field.delegate = context.coordinator

        // Placeholder styling to match the SwiftUI tertiary prompt color.
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.35),
                .font: UIFont.systemFont(ofSize: 15, weight: .regular)
            ]
        )

        // Become first responder after the full-screen cover transition finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            field.becomeFirstResponder()
        }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: FocusedSearchField

        init(_ parent: FocusedSearchField) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let stringRange = Range(range, in: current) else { return true }
            let updated = current.replacingCharacters(in: stringRange, with: string)
            parent.text = updated
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onEditingChanged(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEditingChanged(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
