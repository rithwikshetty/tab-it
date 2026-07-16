import SwiftUI
import SwiftData

@main
struct TabApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate
    @State private var auth: AuthService
    @State private var sync: SyncService
    @State private var realtime: RealtimeService
    @State private var push = PushService.shared
    @State private var invites = InviteLinkService()
    let container: ModelContainer

    init() {
        let container = TabModelContainer.make()
        #if DEBUG
        if ProcessInfo.processInfo.environment["TAB_RESET_LOCAL_STORE"] == "1" {
            try? LocalStore.wipe(container.mainContext)
        }
        #endif
        let auth = AuthService()
        let sync = SyncService(container: container, auth: auth)
        let realtime = RealtimeService(sync: sync)
        // On sign-out, clear all locally-cached data so the next account on this
        // device never sees the previous user's trips or pending writes.
        auth.onSignedOut = { [container] in
            try? LocalStore.wipe(container.mainContext)
            // The badge belongs to the account that just left; don't let it
            // linger for the next sign-in.
            await PushService.shared.setBadgeCount(0)
        }
        // Before the session dies, drop this device's push registration so the
        // signed-out account's notifications stop arriving on this device.
        auth.onWillSignOut = { [sync] in
            await sync.unregisterPushDevice(token: PushService.shared.deviceToken)
        }
        self.container = container
        _auth = State(initialValue: auth)
        _sync = State(initialValue: sync)
        _realtime = State(initialValue: realtime)
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(auth)
                .environment(sync)
                .environment(realtime)
                .environment(push)
                .environment(invites)
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}

private struct AppShell: View {
    @Environment(AuthService.self) private var auth
    @Environment(InviteLinkService.self) private var invites
    @State private var splashAnimationDone = false

    private var isLoading: Bool {
        if case .loading = auth.phase { return true }
        return false
    }

    private var showSplash: Bool {
        !splashAnimationDone || isLoading
    }

    var body: some View {
        ZStack {
            Group {
                switch auth.phase {
                case .loading:
                    Sage.bg.ignoresSafeArea()
                case .signedOut:
                    AuthView()
                case .signedIn:
                    RootView()
                }
            }

            if showSplash {
                SplashView(onAnimationComplete: { splashAnimationDone = true })
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onOpenURL { url in
            handle(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                handle(url)
            }
        }
        .animation(.easeOut(duration: 0.35), value: splashAnimationDone)
        .animation(.easeOut(duration: 0.35), value: isLoading)
    }

    private func handle(_ url: URL) {
        if !invites.capture(url: url) {
            auth.handleAuthCallback(url)
        }
    }
}
