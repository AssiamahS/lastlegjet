import SwiftUI

@main
struct LastLegApp: App {
    @StateObject private var mode = AppMode.shared
    @StateObject private var nav = AppNavigation()
    @StateObject private var session = SessionStore()
    @StateObject private var flights = FlightsStore()
    @StateObject private var bookings = BookingsStore()

    init() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(Brand.ink)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = UIColor(Brand.ink)
        navBar.titleTextAttributes = [.foregroundColor: UIColor(Brand.cream)]
        navBar.largeTitleTextAttributes = [.foregroundColor: UIColor(Brand.cream)]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(mode)
                .environmentObject(nav)
                .environmentObject(session)
                .environmentObject(flights)
                .environmentObject(bookings)
                .preferredColorScheme(.dark)
                .tint(Brand.gold)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode

    var body: some View {
        TabView(selection: $nav.tab) {
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            BookingsView()
                .tabItem { Label("Bookings", systemImage: "ticket") }
                .tag(AppTab.bookings)
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
        .task {
            await mode.refreshMeta()
            await session.restore()
        }
    }
}

enum AppTab: Hashable {
    case search
    case bookings
    case account
}

/// Shared navigation state so deep views (confirmation) can pop to root and switch tabs.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var tab: AppTab = .search
    @Published var searchPath = NavigationPath()
    @Published var bookingsPath = NavigationPath()

    /// Pushes onto whichever stack is currently on screen.
    func push<V: Hashable>(_ value: V) {
        if tab == .bookings {
            bookingsPath.append(value)
        } else {
            searchPath.append(value)
        }
    }

    func resetToSearch() {
        searchPath = NavigationPath()
        tab = .search
    }

    func showBookings() {
        searchPath = NavigationPath()
        bookingsPath = NavigationPath()
        tab = .bookings
    }
}

enum Brand {
    // Last Leg Jet design tokens
    static let ink = Color(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0B / 255.0)       // #0B0B0B
    static let inkCard = Color(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x16 / 255.0)   // raised surface
    static let inkLine = Color(red: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x2A / 255.0)   // hairlines
    static let gold = Color(red: 0xC9 / 255.0, green: 0xA2 / 255.0, blue: 0x4A / 255.0)      // #C9A24A
    static let cream = Color(red: 0xF5 / 255.0, green: 0xF4 / 255.0, blue: 0xF0 / 255.0)     // #F5F4F0
    static let muted = Color(red: 0x9A / 255.0, green: 0x97 / 255.0, blue: 0x8F / 255.0)     // secondary text
    static let success = Color(red: 0x3F / 255.0, green: 0xB2 / 255.0, blue: 0x6B / 255.0)
    static let danger = Color(red: 0xD9 / 255.0, green: 0x4F / 255.0, blue: 0x4F / 255.0)

    static let appName = "Last Leg Jet"
}
