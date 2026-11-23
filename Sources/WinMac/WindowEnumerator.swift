import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct WindowCandidate: Identifiable {
    let key: WindowKey
    let appName: String
    let title: String
    let appIcon: NSImage
    let frame: CGRect
    var thumbnail: NSImage?

    var id: WindowKey { key }
}

@MainActor
final class WindowEnumerator {
    private static let excludedBundleIDs: Set<String> = [
        "com.winmac.windowmanager",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.apple.wallpaper.agent",
        "com.apple.loginwindow"
    ]

    /// Lists visible standard windows in front-to-back order, excluding `excludingKey` and system chrome.
    func visibleCandidates(excluding excludingKey: WindowKey, limit: Int = 9) -> [WindowCandidate] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [WindowCandidate] = []
        var seenKeys = Set<WindowKey>()

        for entry in rawList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pidNum = entry[kCGWindowOwnerPID as String] as? Int32,
                  pidNum != myPID,
                  let winIDNum = entry[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else {
                continue
            }

            // Skip tiny utility/status windows
            guard bounds.width >= 180, bounds.height >= 140 else { continue }

            let key = WindowKey(pid: pidNum, windowID: winIDNum)
            if key == excludingKey || seenKeys.contains(key) { continue }

            guard let app = NSRunningApplication(processIdentifier: pidNum),
                  app.activationPolicy == .regular
            else {
                continue
            }

            if let bundleID = app.bundleIdentifier, Self.excludedBundleIDs.contains(bundleID) {
                continue
            }

            let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? app.localizedName ?? "App"
            let rawTitle = (entry[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = rawTitle.isEmpty ? ownerName : rawTitle
            let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")

            seenKeys.insert(key)
            results.append(WindowCandidate(
                key: key,
                appName: ownerName,
                title: title,
                appIcon: icon,
                frame: bounds,
                thumbnail: nil
            ))

            if results.count >= limit {
                break
            }
        }

        return results
    }

    /// Asynchronously captures live window thumbnails using ScreenCaptureKit ONLY when
    /// Screen Recording permission is already granted (never triggers a permission prompt).
    func captureThumbnailsIfPermitted(for candidates: [WindowCandidate]) async -> [WindowKey: NSImage] {
        guard CGPreflightScreenCaptureAccess() else { return [:] }
        guard !candidates.isEmpty else { return [:] }

        let targetIDs = Set(candidates.map(\.key.windowID))
        var images: [WindowKey: NSImage] = [:]

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let scByID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })

            for candidate in candidates {
                guard let scWindow = scByID[candidate.key.windowID],
                      targetIDs.contains(scWindow.windowID)
                else { continue }

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                let aspect = max(0.3, min(3.0, candidate.frame.width / max(1, candidate.frame.height)))
                config.width = 480
                config.height = max(160, Int((480.0 / aspect).rounded()))
                config.showsCursor = false

                if let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    images[candidate.key] = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                }
            }
        } catch {
            // Silently fall back to icon+title cards
        }

        return images
    }
}
