//
//  Fast_IRLApp.swift
//  Fast IRL
//
//  Created by Emir Beytekin on 21.08.2025.
//

import SwiftUI
import UIKit

@main
struct Fast_IRLApp: App {
    @UIApplicationDelegateAdaptor(OrientationAppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
