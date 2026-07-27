import SwiftUI

@main
struct LastLegApp: App {
    var body: some Scene {
        WindowGroup {
            BoardView()
                .preferredColorScheme(.dark)
        }
    }
}

enum Brand {
    static let walnut = Color(red: 0.10, green: 0.07, blue: 0.05)
    static let walnutCard = Color(red: 0.14, green: 0.10, blue: 0.07)
    static let brass = Color(red: 0.79, green: 0.66, blue: 0.42)
    static let cream = Color(red: 0.95, green: 0.92, blue: 0.86)
    static let dim = Color(red: 0.62, green: 0.56, blue: 0.48)
}
