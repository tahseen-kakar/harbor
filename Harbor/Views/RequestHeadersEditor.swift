import AppKit
import SwiftUI

struct RequestHeadersEditor: View {
    private static let placeholder = """
    User-Agent: Mozilla/5.0
    Referer: https://example.com/
    """

    let onSave: ([RequestHeader]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var requestHeadersText: String
    @State private var isRequestHeadersEditorFocused = false
    @State private var validationMessage: String?

    init(
        requestHeaders: [RequestHeader],
        onSave: @escaping ([RequestHeader]) -> Void
    ) {
        self.onSave = onSave
        _requestHeadersText = State(
            initialValue: requestHeaders
                .map { "\($0.name): \($0.value)" }
                .joined(separator: "\n")
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Request Headers")
                    .font(.title2.weight(.semibold))

                Text("Enter one header per line using Name: value format.")
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                PaddedTextEditor(
                    text: $requestHeadersText,
                    isFocused: $isRequestHeadersEditorFocused
                )

                if requestHeadersText.isEmpty {
                    Text(Self.placeholder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 140, idealHeight: 170)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.secondary.opacity(0.25), lineWidth: 1)
            }

            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 560, minHeight: 260, idealHeight: 300)
        .onAppear {
            isRequestHeadersEditorFocused = true
        }
        .onChange(of: isRequestHeadersEditorFocused) { oldValue, newValue in
            if oldValue, newValue == false {
                _ = parseRequestHeaders()
            }
        }
        .onChange(of: requestHeadersText) {
            validationMessage = nil
        }
    }

    private func save() {
        guard let requestHeaders = parseRequestHeaders() else {
            isRequestHeadersEditorFocused = true
            return
        }

        onSave(requestHeaders)
        dismiss()
    }

    private func parseRequestHeaders() -> [RequestHeader]? {
        var requestHeaders: [RequestHeader] = []
        validationMessage = nil

        for (index, line) in requestHeadersText.components(separatedBy: "\n").enumerated() {
            guard line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                continue
            }

            let lineNumber = index + 1
            guard let separator = line.firstIndex(of: ":") else {
                validationMessage = String(
                    format: String(
                        localized: "add.validation.headerFormat",
                        defaultValue: "Header line %d must use Name: value format.",
                        comment: "Validation message shown when a request header line has no colon separator. Parameter is the one-based line number."
                    ),
                    lineNumber
                )
                return nil
            }

            let valueStart = line.index(after: separator)
            let header = RequestHeader(
                name: line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines),
                value: line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            )

            guard let issue = header.validationIssue else {
                requestHeaders.append(header)
                continue
            }

            switch issue {
            case .missingName:
                validationMessage = String(
                    format: String(
                        localized: "add.validation.headerNameRequired",
                        defaultValue: "Header line %d is missing a name.",
                        comment: "Validation message shown when a request header line has no name before its colon. Parameter is the one-based line number."
                    ),
                    lineNumber
                )
            case .invalidName:
                validationMessage = String(
                    format: String(
                        localized: "add.validation.headerNameInvalid",
                        defaultValue: "Header line %d has an invalid name.",
                        comment: "Validation message shown when a request header name contains unsupported characters. Parameter is the one-based line number."
                    ),
                    lineNumber
                )
            case .invalidValue:
                validationMessage = String(
                    format: String(
                        localized: "add.validation.headerValueInvalid",
                        defaultValue: "Header line %d contains an invalid control character.",
                        comment: "Validation message shown when a request header value contains an invalid HTTP control character. Parameter is the one-based line number."
                    ),
                    lineNumber
                )
            }

            return nil
        }

        return requestHeaders
    }
}

private struct PaddedTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.lineFragmentPadding = 5
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.setAccessibilityLabel("Request Headers")

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }

        guard isFocused,
              textView.window?.firstResponder !== textView else {
            return
        }

        DispatchQueue.main.async {
            guard isFocused else {
                return
            }

            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PaddedTextEditor

        init(_ parent: PaddedTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            if parent.isFocused == false {
                parent.isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  parent.text != textView.string else {
                return
            }

            parent.text = textView.string
        }
    }
}
