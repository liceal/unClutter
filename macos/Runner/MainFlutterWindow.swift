import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var previousFrontmostApp: NSRunningApplication?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Force native window to be fully transparent to prevent any pure black mask
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    flutterViewController.backgroundColor = NSColor.clear
    self.hasShadow = false
    self.isMovable = false

    // Remove macOS system-level window corner radius.
    // Flutter's borderRadius=0 only affects widget painting; the OS still clips
    // the window's contentView with its own rounded corners. Setting the layer's
    // cornerRadius to 0 on both the contentView and its hosting layer removes this.
    if let contentView = self.contentView {
      contentView.wantsLayer = true
      contentView.layer?.cornerRadius = 0
      contentView.layer?.masksToBounds = false
    }
    
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Re-apply after super.awakeFromNib() in case it resets layer properties.
    // Also zero out the window-level corner radius that macOS 11+ enforces.
    self.contentView?.layer?.cornerRadius = 0
    self.contentView?.layer?.masksToBounds = false

    // Register MethodChannel for scroll events
    let channel = FlutterMethodChannel(
      name: "app.pod/menu_bar_scroll",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "showInactive" {
        // Show window on screen without activating the app or stealing focus
        self.orderFront(nil)
        result(nil)
      } else if call.method == "focusWindow" {
        // Explicitly focus and activate the window/app
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        result(nil)
      } else if call.method == "savePreviousApp" {
        // Remember the currently frontmost app (excluding our own) before we steal focus
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
          self.previousFrontmostApp = frontmost
        }
        result(nil)
      } else if call.method == "restorePreviousApp" {
        // Restore focus to the previously saved app
        if let prev = self.previousFrontmostApp, !prev.isTerminated {
          prev.activate(options: [.activateIgnoringOtherApps])
        }
        self.previousFrontmostApp = nil
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Register MethodChannel for clipboard owner info (app icon and name)
    let clipboardOwnerChannel = FlutterMethodChannel(
      name: "app.pod/clipboard_owner",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    clipboardOwnerChannel.setMethodCallHandler { (call, result) in
      if call.method == "getClipboardOwner" {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
          result([String: Any]())
          return
        }
        
        let appName = frontmostApp.localizedName ?? "Unknown"
        var iconPath = ""
        
        if let icon = frontmostApp.icon {
          if let tiffData = icon.tiffRepresentation,
             let bitmapImage = NSBitmapImageRep(data: tiffData),
             let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            let tempDir = FileManager.default.temporaryDirectory
            let iconsDir = tempDir.appendingPathComponent("pod_icons")
            try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true, attributes: nil)
            let destURL = iconsDir.appendingPathComponent("\(appName).png")
            do {
              try pngData.write(to: destURL)
              iconPath = destURL.path
            } catch {
              // ignore
            }
          }
        }
        
        var response = [String: Any]()
        response["name"] = appName
        response["iconPath"] = iconPath
        result(response)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      self?.handleScrollEvent(event, channel: channel)
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      self?.handleScrollEvent(event, channel: channel)
      return event
    }
  }

  deinit {
    if let monitor = globalMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  private func isMouseInMenuBar() -> Bool {
    let mouseLoc = NSEvent.mouseLocation
    for screen in NSScreen.screens {
      let frame = screen.frame
      let visibleFrame = screen.visibleFrame
      if visibleFrame.maxY < frame.maxY {
        // Expand hit area slightly below the menu bar (e.g. 20px slop)
        // This prevents the scroll event from dropping if the user's mouse drifts slightly down during a swipe
        let extendedMaxY = visibleFrame.maxY - 20.0
        if mouseLoc.x >= frame.minX && mouseLoc.x <= frame.maxX &&
           mouseLoc.y >= extendedMaxY && mouseLoc.y <= frame.maxY {
          return true
        }
      }
    }
    return false
  }

  private func handleScrollEvent(_ event: NSEvent, channel: FlutterMethodChannel) {
    guard isMouseInMenuBar() else { return }

    let deltaY = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
    guard deltaY != 0 else { return }

    // Map Cocoa scroll direction to Dart scroll direction
    // By default, trackpad swipe down is a positive deltaY. We map this directly so swipe down = positive = expand.
    let dartDeltaY = deltaY
    channel.invokeMethod("onMenuBarScroll", arguments: dartDeltaY)
  }
}
