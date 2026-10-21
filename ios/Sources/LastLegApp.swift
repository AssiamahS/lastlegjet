import SwiftUI

@main
struct LastLegApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var mode = AppMode.shared
    @StateObject private var nav = AppNavigation()
    @StateObject private var session = SessionStore()
    @StateObject private var flights = FlightsStore()
    @StateObject private var bookings = BookingsStore()
    @StateObject private var trips = TripsStore()
    @StateObject private var ops = OperatorStore()

    init() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(Brand.ink)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = UIColor(Brand.ink)
        let serif = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline).withDesign(.serif)
        let titleFont = serif.map { UIFont(descriptor: $0, size: 18) } ?? UIFont.preferredFont(forTextStyle: .headline)
        navBar.titleTextAttributes = [.foregroundColor: UIColor(Brand.cream), .font: titleFont]
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
                .environmentObject(trips)
                .environmentObject(ops)
                .preferredColorScheme(.dark)
                .tint(Brand.gold)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushRegistrar.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.didRegister(tokenData: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushRegistrar.shared.didFail(error)
    }
}

struct RootView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode
    @AppStorage(RoleMode.demoOperatorKey) private var demoOperator = false

    private var showsOperator: Bool { session.user?.isOperator == true || demoOperator }

    var body: some View {
        TabView(selection: $nav.tab) {
            MapHomeView()
                .tabItem { Label("Home", systemImage: "map") }
                .tag(AppTab.home)
            SearchView()
                .tabItem { Label("Deals", systemImage: "tag") }
                .tag(AppTab.deals)
            BookingsView()
                .tabItem { Label("Trips", systemImage: "airplane") }
                .tag(AppTab.trips)
            if showsOperator {
                OperatorRootView()
                    .tabItem { Label("Operator", systemImage: "steeringwheel") }
                    .tag(AppTab.ops)
            }
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
        .task {
            await mode.refreshMeta()
            await session.restore()
        }
        .task(id: session.user?.id) {
            guard session.user != nil else { return }
            await PushRegistrar.shared.requestAndRegister()
        }
        .onChange(of: showsOperator) { _, visible in
            if !visible && nav.tab == .ops { nav.tab = .account }
        }
    }
}

enum AppTab: Hashable {
    case home
    case deals
    case trips
    case ops
    case account
}

enum RoleMode {
    /// Shows the Operator tab for non-operator accounts / sample mode (demo switch in Account).
    static let demoOperatorKey = "demoOperatorTab"
}

/// Shared navigation state so deep views (confirmation) can pop to root and switch tabs.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var bookingsPath = NavigationPath()
    @Published var operatorPath = NavigationPath()

    /// Pushes onto whichever stack is currently on screen.
    func push<V: Hashable>(_ value: V) {
        switch tab {
        case .home: homePath.append(value)
        case .deals: searchPath.append(value)
        case .trips: bookingsPath.append(value)
        case .ops: operatorPath.append(value)
        case .account: homePath.append(value)
        }
    }

    func resetToSearch() {
        homePath = NavigationPath()
        searchPath = NavigationPath()
        tab = .home
    }

    func showBookings() {
        homePath = NavigationPath()
        searchPath = NavigationPath()
        bookingsPath = NavigationPath()
        tab = .trips
    }

    /// Opens the live trip screen from anywhere.
    func showTrip(_ booking: Booking) {
        homePath = NavigationPath()
        searchPath = NavigationPath()
        bookingsPath = NavigationPath()
        bookingsPath.append(TrackRoute(booking: booking))
        tab = .trips
    }
}

enum Brand {
    // AmblrX design tokens: black/charcoal with a bronze gradient.
    static let ink = Color(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0A / 255.0)       // #0A0A0A
    static let inkCard = Color(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x16 / 255.0)   // #161616
    static let inkLine = Color(red: 0x2A / 255.0, green: 0x26 / 255.0, blue: 0x22 / 255.0)   // warm hairline
    static let bronzeLight = Color(red: 0xF6 / 255.0, green: 0xD5 / 255.0, blue: 0xA3 / 255.0) // #F6D5A3
    static let bronze = Color(red: 0xD7 / 255.0, green: 0xA6 / 255.0, blue: 0x74 / 255.0)      // #D7A674
    static let bronzeDeep = Color(red: 0xB0 / 255.0, green: 0x7F / 255.0, blue: 0x4C / 255.0)  // #B07F4C
    /// Accent used across the existing screens.
    static let gold = bronze
    static let cream = Color(red: 0xF5 / 255.0, green: 0xF0 / 255.0, blue: 0xE8 / 255.0)
    static let muted = Color(red: 0x9C / 255.0, green: 0x95 / 255.0, blue: 0x8C / 255.0)
    static let success = Color(red: 0x5B / 255.0, green: 0xB9 / 255.0, blue: 0x7E / 255.0)
    static let danger = Color(red: 0xD9 / 255.0, green: 0x5F / 255.0, blue: 0x55 / 255.0)

    static let bronzeGradient = LinearGradient(colors: [bronzeLight, bronze, bronzeDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)

    static let appName = "AmblrX"
    static let tagline = "Fly different."
}
