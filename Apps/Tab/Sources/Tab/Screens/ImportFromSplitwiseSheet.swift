import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TabCore

/// Imports a Splitwise group CSV export into a new trip. Pick a file, review the
/// detected people and counts (and confirm which column is you), then import.
struct ImportFromSplitwiseSheet: View {
    /// Called after a successful import so the presenter can dismiss the whole
    /// new-trip flow.
    var onComplete: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @State private var isImporting = false
    @State private var parsed: SplitwiseImport.Result?
    @State private var tripName = ""
    @State private var selfPerson: String?
    @State private var showingPicker = false
    @State private var fileError: String?
    @State private var importError: String?

    private var canImport: Bool {
        parsed != nil && !tripName.trimmingCharacters(in: .whitespaces).isEmpty && !isImporting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Sage.bg.ignoresSafeArea()
                ScrollView {
                    if let parsed {
                        reviewBody(parsed)
                    } else {
                        chooseBody
                    }
                }
                if isImporting { importingOverlay }
            }
            .interactiveDismissDisabled(isImporting)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.navLink)
                        .foregroundStyle(Sage.text)
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .principal) {
                    Text("Import from Splitwise")
                        .font(.navTitle)
                        .foregroundStyle(Sage.text)
                }
            }
            .toolbarBackground(Sage.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handlePicked(result)
        }
    }

    // MARK: - Choose

    private var chooseBody: some View {
        VStack(spacing: 0) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Sage.accent)
                .padding(.top, 48)
                .padding(.bottom, 18)

            Text("Bring a Splitwise group into tab")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
                .multilineTextAlignment(.center)

            Text("In Splitwise, open a group, choose Export as spreadsheet, and save the CSV. Then pick it here.")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            if let fileError {
                calloutBox(text: fileError, tone: Sage.warning)
                    .padding(.top, 20)
            }

            accentButton(title: "Choose CSV file", isEnabled: true) {
                fileError = nil
                showingPicker = true
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)

            Text("Importing needs an internet connection.")
                .font(.system(size: 12))
                .foregroundStyle(Sage.textSecondary)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Review

    @ViewBuilder
    private func reviewBody(_ parsed: SplitwiseImport.Result) -> some View {
        VStack(spacing: 0) {
            sectionLabel("Trip name")
            Card {
                TextField("Trip name", text: $tripName)
                    .font(.formRow)
                    .foregroundStyle(Sage.text)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .accessibilityIdentifier("import.tripNameField")
            }

            sectionLabel("Which one is you?")
            Card {
                Menu {
                    Picker("You", selection: $selfPerson) {
                        ForEach(parsed.people, id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                        Text("I'm not in this group").tag(Optional<String>.none)
                    }
                } label: {
                    HStack {
                        Text(selfPerson ?? "I'm not in this group")
                            .font(.formRow)
                            .foregroundStyle(Sage.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Sage.textSecondary)
                    }
                    .padding(14)
                }
            }

            sectionLabel("People (\(parsed.people.count))")
            Card {
                ForEach(Array(parsed.people.enumerated()), id: \.element) { index, name in
                    HStack {
                        Text(name)
                            .font(.formRow)
                            .foregroundStyle(Sage.text)
                        if name == selfPerson {
                            Text("You")
                                .font(.chip)
                                .foregroundStyle(Sage.accentStrong)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Sage.accentTint, in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    if index < parsed.people.count - 1 { RowDivider() }
                }
            }

            summaryRow(parsed)

            if !parsed.warnings.isEmpty {
                sectionLabel("Notes (\(parsed.warnings.count))")
                Card {
                    ForEach(Array(parsed.warnings.enumerated()), id: \.offset) { index, warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 12))
                                .foregroundStyle(Sage.warning)
                            Text("Line \(warning.line): \(warning.message)")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Sage.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if index < parsed.warnings.count - 1 { RowDivider() }
                    }
                }
            }

            Text("Everyone except you is added by name. Add their email later so they can claim their spot. Balances will match Splitwise exactly.")
                .font(.system(size: 12.5))
                .foregroundStyle(Sage.textSecondary)
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let importError {
                calloutBox(text: importError, tone: Sage.warning)
                    .padding(.top, 16)
            }

            accentButton(title: "Import \(tripName.trimmingCharacters(in: .whitespaces).isEmpty ? "trip" : tripName)", isEnabled: canImport) {
                runImport(parsed)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .accessibilityIdentifier("import.confirmButton")
        }
    }

    private func summaryRow(_ parsed: SplitwiseImport.Result) -> some View {
        HStack(spacing: 22) {
            summaryStat(value: parsed.expenses.count, label: "Expenses")
            summaryStat(value: parsed.settlements.count, label: "Settlements")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private func summaryStat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Sage.text)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Sage.textSecondary)
        }
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.08).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Importing…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Sage.text)
            }
            .padding(24)
            .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Actions

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            fileError = error.localizedDescription
        case let .success(urls):
            guard let url = urls.first else { return }
            do {
                let text = try readCSV(at: url)
                let parsedResult = try SplitwiseImport.parse(text)
                parsed = parsedResult
                tripName = defaultTripName(from: url)
                // Leave as "not in this group" when nothing matches rather than
                // guessing the first column (which silently misattributes balances).
                selfPerson = Self.bestSelfMatch(people: parsedResult.people, displayName: auth.currentUser?.displayName ?? "")
                fileError = nil
            } catch let error as SplitwiseImport.ParseError {
                fileError = message(for: error)
            } catch {
                fileError = "Couldn't read that file. \(error.localizedDescription)"
            }
        }
    }

    private func runImport(_ parsed: SplitwiseImport.Result) {
        importError = nil
        isImporting = true
        Task {
            do {
                let importer = SplitwiseImporter(context: context, sync: sync, auth: auth)
                try await importer.run(parsed, tripName: tripName.trimmingCharacters(in: .whitespaces), selfPerson: selfPerson)
                Haptics.success()
                onComplete()
                dismiss()
            } catch {
                importError = error.localizedDescription
                isImporting = false
            }
        }
    }

    private func readCSV(at url: URL) throws -> String {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        // A leading UTF-8 BOM is handled by the parser.
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    private func defaultTripName(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Imported trip" : trimmed
    }

    private func message(for error: SplitwiseImport.ParseError) -> String {
        switch error {
        case .empty:
            return "That file is empty."
        case .missingHeader, .unexpectedHeader:
            return "That doesn't look like a Splitwise export. Use the spreadsheet (CSV) export from a group."
        case .noPeople:
            return "No people were found in that export."
        }
    }

    /// Best guess for which Splitwise column is the current user, by name overlap.
    static func bestSelfMatch(people: [String], displayName: String) -> String? {
        let target = displayName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        if let exact = people.first(where: { $0.lowercased() == target }) { return exact }
        let targetTokens = Set(target.split(separator: " "))
        guard !targetTokens.isEmpty else { return nil }
        let scored = people
            .map { ($0, targetTokens.intersection(Set($0.lowercased().split(separator: " "))).count) }
            .filter { $0.1 > 0 }
        return scored.max { $0.1 < $1.1 }?.0
    }

    // MARK: - Styling helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calloutBox(text: String, tone: Color) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(tone)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    private func accentButton(title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    isEnabled ? Sage.accent : Sage.surface2,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
