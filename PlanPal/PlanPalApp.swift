// Project: PlanPal
// EID: mc77599
// Course: CS 329E

import SwiftUI
import FirebaseCore

@main
struct PlanPalApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
