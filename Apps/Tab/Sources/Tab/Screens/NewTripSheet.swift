import SwiftUI
import SwiftData

struct NewTripSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @State private var name: String = ""
    @State private var isSaving = false
    @State private var showingImport = false
    @FocusState private var nameFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && auth.currentUser != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    sectionLabel("Trip name")

                    TextField("Lisbon weekend", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .accessibilityIdentifier("newTrip.nameField")
                        .onSubmit { save() }
                        .font(.formRow)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Sage.rowDivider).frame(height: 1)
                        }

                    Text("Trips are private to people you add by email.")
                        .font(.system(size: 13))
                        .foregroundStyle(Sage.textSecondary)
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        showingImport = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Import from Splitwise")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Sage.textSecondary)
                        }
                        .foregroundStyle(Sage.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Sage.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .accessibilityIdentifier("newTrip.importButton")

                    Spacer(minLength: 32)
                }
            }
            .background(Sage.bg.ignoresSafeArea())
            .sheet(isPresented: $showingImport) {
                ImportFromSplitwiseSheet(onComplete: { dismiss() })
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.navLink)
                        .foregroundStyle(Sage.text)
                }
                ToolbarItem(placement: .principal) {
                    Text("New trip")
                        .font(.navTitle)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { save() }
                        .font(.navLinkBold)
                        .foregroundStyle(canCreate ? Sage.accent : Sage.accent.opacity(0.4))
                        .disabled(!canCreate)
                        .accessibilityIdentifier("newTrip.createButton")
                }
            }
            .toolbarBackground(Sage.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { nameFocused = true }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard canCreate, let user = auth.currentUser else { return }
        isSaving = true   // block a double tap during the dismiss transition
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        let trip = TripEntity(name: trimmed, createdByID: user.id)
        context.insert(trip)
        let person = TripPersonEntity(
            id: creatorPersonID(for: user.id),
            userID: user.id,
            email: user.email.map(Self.normalizedEmail) ?? "\(user.id.uuidString.lowercased())@users.tab",
            displayName: user.displayName,
            invitedByID: user.id,
            trip: trip,
            joinedAt: .now
        )
        context.insert(person)

        #if DEBUG
        insertDebugPeopleIfRequested(into: trip, invitedByID: user.id)
        #endif

        try? context.save()

        Haptics.success()
        dismiss()

        Task { await sync.pushPending() }
    }

    private func creatorPersonID(for userID: UUID) -> UUID {
        #if DEBUG
        if shouldSeedDebugPeople {
            return userID
        }
        #endif
        return UUID()
    }

    #if DEBUG
    /// Fixture people are local-only and can never sync (the server forbids
    /// direct trip_people inserts), so they're restricted to mock auth where
    /// no real session exists. Under real auth they'd strand every expense
    /// that includes them in a permanent push failure.
    private var shouldSeedDebugPeople: Bool {
        auth.isUsingMockAuth && ProcessInfo.processInfo.environment["TAB_DISABLE_DEBUG_PEOPLE"] != "1"
    }

    private func insertDebugPeopleIfRequested(into trip: TripEntity, invitedByID: UUID) {
        guard shouldSeedDebugPeople else { return }

        let fixtures: [(id: UUID, email: String, displayName: String)] = [
            (UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, "alex@test.tab", "Alex"),
            (UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, "sam@test.tab", "Sam"),
        ]

        let existingIDs = Set(trip.people.map(\.id))
        for fixture in fixtures where !existingIDs.contains(fixture.id) {
            context.insert(TripPersonEntity(
                id: fixture.id,
                email: fixture.email,
                displayName: fixture.displayName,
                invitedByID: invitedByID,
                trip: trip,
                joinedAt: nil
            ))
        }
    }
    #endif

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
