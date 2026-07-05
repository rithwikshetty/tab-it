import ContactsUI
import SwiftUI
import SwiftData

struct TripPeopleSheet: View {
    let tripID: UUID
    let tripName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]

    @State private var emailText = ""
    @State private var suggestions: [TripPersonSuggestionDTO] = []
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var showContactPicker = false
    @State private var selectedPerson: TripPersonEntity?

    @FocusState private var emailFocused: Bool

    init(tripID: UUID, tripName: String) {
        self.tripID = tripID
        self.tripName = tripName
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var normalizedEmail: String {
        emailText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canAdd: Bool {
        EmailValidator.isValid(normalizedEmail) && !existingEmails.contains(normalizedEmail) && !isAdding
    }

    /// Active members only: adding an email that belongs to a removed person
    /// must stay possible — the server restores them.
    private var existingEmails: Set<String> {
        Set((trip?.activePeople ?? []).map(\.email))
    }

    private var displayPeople: [TripPersonEntity] {
        trip?.activePeople.sortedForDisplay(currentPersonID: currentPersonID) ?? []
    }

    private var filteredSuggestions: [TripPersonSuggestionDTO] {
        suggestions.filter { !existingEmails.contains($0.email) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("People")
                    peopleList

                    sectionLabel("Add by email")
                    addCard

                    if !filteredSuggestions.isEmpty {
                        sectionLabel("Suggestions")
                        suggestionList
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Sage.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.navLink)
                        .foregroundStyle(Sage.text)
                }
                ToolbarItem(placement: .principal) {
                    Text("People")
                        .font(.navTitle)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                }
            }
            .toolbarBackground(Sage.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Keyed on the query so SwiftUI cancels the in-flight fetch when the
            // text changes — a slow earlier response can't overwrite a newer one.
            .task(id: normalizedEmail) { await refreshSuggestions() }
            .sheet(isPresented: $showContactPicker) {
                ContactEmailPicker { name, email in
                    emailText = email
                    addEmail(displayName: name)
                }
                .ignoresSafeArea()
            }
            .sheet(item: $selectedPerson) { person in
                PersonDetailSheet(person: person, tripID: tripID)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var peopleList: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayPeople.enumerated()), id: \.element.id) { index, person in
                personRow(person)
                if index < displayPeople.count - 1 { RowDivider() }
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Sage.accent)
                TextField("name@example.com", text: $emailText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
                    .font(.formRow)
                    .foregroundStyle(Sage.text)
                    .submitLabel(.done)
                    .onSubmit { addEmail() }
            }

            Button {
                emailFocused = false
                showContactPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 14, weight: .medium))
                    Text("Choose from contacts")
                        .font(.system(size: 13.5, weight: .medium))
                }
                .foregroundStyle(Sage.accent)
            }
            .buttonStyle(.plain)
            .disabled(isAdding)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Sage.warning)
            }

            Button {
                addEmail()
            } label: {
                HStack(spacing: 8) {
                    if isAdding {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("Add person")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(canAdd ? Sage.accent : Sage.accent.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
        .padding(14)
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredSuggestions.enumerated()), id: \.element.email) { index, suggestion in
                Button {
                    emailText = suggestion.email
                    addEmail()
                } label: {
                    HStack(spacing: 12) {
                        Avatar(initial: AvatarInitial.from(suggestion.displayName), tone: AvatarTone.deterministic(for: suggestion.userID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!), size: 30, borderWidth: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.displayName)
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(Sage.text)
                            Text(suggestion.email)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Sage.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Sage.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)

                if index < filteredSuggestions.count - 1 { RowDivider() }
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var currentPersonID: UUID? {
        guard let userID = auth.currentUser?.id else { return nil }
        return trip?.people.first(where: { $0.userID == userID })?.id
    }

    @ViewBuilder
    private func personRow(_ person: TripPersonEntity) -> some View {
        let isYou = person.id == currentPersonID
        let content = HStack(spacing: 12) {
            Avatar(initial: AvatarInitial.from(isYou ? (auth.currentUser?.displayName ?? person.displayName) : person.displayName), tone: AvatarTone.deterministic(for: person.id), size: 30, borderWidth: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "You" : person.displayName)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                Text(emailText(for: person, isYou: isYou))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            statusBadge(for: person)
            if !isYou {
                Chevron(size: 9)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)

        if isYou {
            content
        } else {
            Button {
                selectedPerson = person
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("people.personRow.\(person.id.uuidString)")
        }
    }

    private func statusBadge(for person: TripPersonEntity) -> some View {
        let (label, isWarning): (String, Bool) = person.joinedAt != nil
            ? ("Joined", false)
            : (person.hasPlaceholderEmail ? "No email" : "Pending", true)
        return Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isWarning ? Sage.warning : Sage.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Sage.surface2, in: Capsule())
            .fixedSize()
    }

    private func emailText(for person: TripPersonEntity, isYou: Bool) -> String {
        if isYou, let email = auth.currentUser?.presentableEmail {
            return email
        }
        return person.hasPlaceholderEmail ? "No email yet" : person.email
    }

    private func addEmail(displayName: String? = nil) {
        guard canAdd else { return }
        let email = normalizedEmail
        isAdding = true
        errorMessage = nil

        Task {
            do {
                try await sync.addTripPerson(tripID: tripID, email: email, displayName: displayName)
                await sync.pullAll()
                await MainActor.run {
                    emailText = ""
                    isAdding = false
                    emailFocused = false
                    Haptics.success()
                }
                await refreshSuggestions()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAdding = false
                    Haptics.error()
                }
            }
        }
    }

    private func refreshSuggestions() async {
        do {
            let rows = try await sync.suggestTripPeople(query: normalizedEmail.isEmpty ? nil : normalizedEmail)
            await MainActor.run {
                suggestions = rows
            }
        } catch { }
    }

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
}

/// Detail sheet for one trip member: repoint a pending person's email (the
/// path that makes Splitwise-imported people claimable) or remove them from
/// the trip. Removal is soft — their expenses and balances stay.
private struct PersonDetailSheet: View {
    let person: TripPersonEntity
    let tripID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var sync

    @State private var emailText: String
    @State private var isSaving = false
    @State private var isRemoving = false
    @State private var errorMessage: String?
    @State private var showRemoveConfirmation = false

    @FocusState private var emailFocused: Bool

    init(person: TripPersonEntity, tripID: UUID) {
        self.person = person
        self.tripID = tripID
        _emailText = State(initialValue: person.hasPlaceholderEmail ? "" : person.email)
    }

    private var isPending: Bool { person.joinedAt == nil }
    private var isBusy: Bool { isSaving || isRemoving }

    private var normalizedEmail: String {
        emailText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSaveEmail: Bool {
        EmailValidator.isValid(normalizedEmail) && normalizedEmail != person.email && !isBusy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isPending {
                    emailCard
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Sage.warning)
                        .padding(.horizontal, 4)
                }

                removeButton

                Spacer(minLength: 16)
            }
            .padding(18)
        }
        .background(Sage.bg.ignoresSafeArea())
        .confirmationDialog(
            "Remove \(person.displayName)?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their expenses and balances stay in the trip. You can add them back later with the same email.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(initial: AvatarInitial.from(person.displayName), tone: AvatarTone.deterministic(for: person.id), size: 44, borderWidth: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private var statusText: String {
        if !isPending {
            return person.email
        }
        if person.hasPlaceholderEmail {
            return "No email yet"
        }
        return "Pending — joins when they sign in with this email"
    }

    private var emailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(person.hasPlaceholderEmail ? "ADD THEIR EMAIL" : "EMAIL")
                .font(.sectionLabel)
                .tracking(1.32)
                .foregroundStyle(Sage.textSecondary)

            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Sage.accent)
                TextField("name@example.com", text: $emailText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
                    .font(.formRow)
                    .foregroundStyle(Sage.text)
                    .submitLabel(.done)
                    .onSubmit { saveEmail() }
                    .accessibilityIdentifier("personDetail.emailField")
            }

            Text("They can claim this spot by signing in with this email.")
                .font(.system(size: 12.5))
                .foregroundStyle(Sage.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                saveEmail()
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("Save email")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(canSaveEmail ? Sage.accent : Sage.accent.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSaveEmail)
            .accessibilityIdentifier("personDetail.saveEmailButton")
        }
        .padding(14)
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
    }

    private var removeButton: some View {
        Button {
            emailFocused = false
            showRemoveConfirmation = true
        } label: {
            HStack(spacing: 8) {
                if isRemoving {
                    ProgressView().tint(Sage.warning)
                } else {
                    Image(systemName: "person.badge.minus")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text("Remove from trip")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Sage.warning)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Sage.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Sage.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("personDetail.removeButton")
    }

    private func saveEmail() {
        guard canSaveEmail else { return }
        let personID = person.id
        let email = normalizedEmail
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await sync.updateTripPersonEmail(personID: personID, email: email)
                await sync.pullAll()
                await MainActor.run {
                    isSaving = false
                    Haptics.success()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                    Haptics.error()
                }
            }
        }
    }

    private func remove() {
        let personID = person.id
        isRemoving = true
        errorMessage = nil

        Task {
            do {
                try await sync.removeTripPerson(personID: personID)
                await sync.pullAll()
                await MainActor.run {
                    isRemoving = false
                    Haptics.success()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRemoving = false
                    Haptics.error()
                }
            }
        }
    }
}

/// System contact picker scoped to email selection. Runs out-of-process, so it
/// needs no Contacts permission and the app only ever receives the one email
/// property the user taps (plus the contact's name when available).
private struct ContactEmailPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPick: (_ displayName: String?, _ email: String) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "emailAddresses.@count > 0")
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (String?, String) -> Void
        private let dismiss: () -> Void

        init(onPick: @escaping (String?, String) -> Void, dismiss: @escaping () -> Void) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            defer { dismiss() }
            guard let email = (contactProperty.value as? NSString).map(String.init) else { return }
            onPick(Self.name(of: contactProperty.contact), email.lowercased())
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            dismiss()
        }

        /// The picker is only guaranteed to fetch the displayed property keys.
        private static func name(of contact: CNContact) -> String? {
            var parts: [String] = []
            if contact.isKeyAvailable(CNContactGivenNameKey) {
                parts.append(contact.givenName)
            }
            if contact.isKeyAvailable(CNContactFamilyNameKey) {
                parts.append(contact.familyName)
            }
            let name = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
    }
}
