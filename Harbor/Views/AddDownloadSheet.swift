import AppKit
import SwiftUI

struct AddDownloadSheet: View {
    private enum Field: Hashable {
        case sourceURL
        case filename
    }

    private enum EntryMode: String, CaseIterable, Identifiable {
        case linkOrMagnet
        case torrentFile

        var id: String { rawValue }

        var title: String {
            switch self {
            case .linkOrMagnet:
                "Link or Magnet"
            case .torrentFile:
                "Torrent File"
            }
        }
    }

    let settings: AppSettingsStore
    let onSubmit: @MainActor (AddDownloadRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var entryMode: EntryMode = .linkOrMagnet
    @State private var sourceURLText = ""
    @State private var customFilename = ""
    @State private var torrentFileURL: URL?
    @State private var destinationPath: String
    @State private var shouldStartImmediately: Bool
    @State private var validationMessage: String?

    init(
        settings: AppSettingsStore,
        onSubmit: @escaping @MainActor (AddDownloadRequest) -> Void
    ) {
        self.settings = settings
        self.onSubmit = onSubmit
        _destinationPath = State(initialValue: settings.defaultDestinationPath)
        _shouldStartImmediately = State(initialValue: settings.startDownloadsAutomatically)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add Download")
                    .font(.title2.weight(.semibold))
                Text("Paste a direct URL, add a magnet link, or choose a `.torrent` file. Torrent transfers use a dedicated backend while direct links stay on the native `URLSession` path.")
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("Source", selection: $entryMode) {
                    ForEach(EntryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if entryMode == .linkOrMagnet {
                    TextField("https://example.com/file.zip or magnet:?xt=...", text: $sourceURLText)
                        .focused($focusedField, equals: Field.sourceURL)

                    TextField("Optional file name override", text: $customFilename)
                        .focused($focusedField, equals: Field.filename)
                } else {
                    LabeledContent("Torrent File") {
                        HStack(spacing: 8) {
                            Text(torrentFileURL?.path ?? "No file selected")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)

                            Button("Choose…") {
                                torrentFileURL = TorrentFileSelectionService.chooseTorrentFile(
                                    startingAt: URL(fileURLWithPath: destinationPath, isDirectory: true)
                                )
                            }
                        }
                    }
                }

                destinationPicker

                Toggle("Start immediately", isOn: $shouldStartImmediately)
            }
            .formStyle(.grouped)

            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                if entryMode == .linkOrMagnet {
                    Button("Paste Link") {
                        sourceURLText = NSPasteboard.general.string(forType: .string) ?? sourceURLText
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Download") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            focusedField = .sourceURL
        }
        .onChange(of: entryMode) { _, newMode in
            validationMessage = nil
            if newMode == .linkOrMagnet {
                focusedField = .sourceURL
            }
        }
    }

    private var destinationPicker: some View {
        LabeledContent("Destination") {
            HStack(spacing: 8) {
                Text(destinationPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Button("Choose…") {
                    guard let folder = FolderSelectionService.chooseFolder(
                        startingAt: URL(fileURLWithPath: destinationPath, isDirectory: true)
                    ) else {
                        return
                    }

                    destinationPath = folder.path
                }

                Button("Use Default") {
                    destinationPath = settings.defaultDestinationPath
                }
            }
        }
    }

    private func submit() {
        validationMessage = nil

        let sourceURL: URL
        let sourceKind: DownloadSourceKind

        switch entryMode {
        case .linkOrMagnet:
            let trimmedURL = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsedURL = URL(string: trimmedURL),
                  let detectedKind = DownloadSourceKind.detect(from: parsedURL),
                  detectedKind == .directURL || detectedKind == .magnetLink else {
                validationMessage = "Enter a valid HTTP/HTTPS URL or magnet link."
                focusedField = .sourceURL
                return
            }

            sourceURL = parsedURL
            sourceKind = detectedKind

        case .torrentFile:
            guard let torrentFileURL,
                  DownloadSourceKind.detect(from: torrentFileURL) == .torrentFile else {
                validationMessage = "Choose a valid `.torrent` file."
                return
            }

            sourceURL = torrentFileURL
            sourceKind = .torrentFile
        }

        let folderURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let trimmedFilename = customFilename.trimmingCharacters(in: .whitespacesAndNewlines)

        onSubmit(
            AddDownloadRequest(
                sourceKind: sourceKind,
                sourceURL: sourceURL,
                customFilename: sourceKind.supportsCustomFilename && trimmedFilename.isEmpty == false ? trimmedFilename : nil,
                destinationFolder: folderURL,
                shouldStartImmediately: shouldStartImmediately
            )
        )
        dismiss()
    }
}
