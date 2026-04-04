//
//  AppDelegate.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/5/25.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Add "Load Splat…" to the File menu (Cmd+O)
        if let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu {
            let item = NSMenuItem(title: "Load Splat…",
                                  action: #selector(GameViewController.loadSplatFile(_:)),
                                  keyEquivalent: "o")
            item.target = nil  // nil = route through responder chain
            fileMenu.insertItem(item, at: 1)
            fileMenu.insertItem(.separator(), at: 2)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
}
