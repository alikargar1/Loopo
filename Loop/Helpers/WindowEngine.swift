//
//  WindowEngine.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-16.
//

import SwiftUI
import Defaults

struct WindowEngine {

    private let kAXFullscreenAttribute = "AXFullScreen"

    func resizeFrontmostWindow(direction: WindowDirection) {
        guard let frontmostWindow = self.getFrontmostWindow(),
              let screenWithMouse = NSScreen.screenWithMouse else { return }
        resize(window: frontmostWindow, direction: direction, screen: screenWithMouse)
    }

    func getFrontmostWindow() -> AXUIElement? {

        #if DEBUG
        print("--------------------------------")
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.isActive }) else { return nil }
        print("Frontmost app: \(app)")
        guard let window = self.getFocusedWindow(pid: app.processIdentifier) else { return nil }
        print("AXUIElement: \(window)")
        print("Is kAXWindowRole: \(self.getRole(element: window) == kAXWindowRole)")
        print("Is kAXStandardWindowSubrole: \(self.getSubRole(element: window) == kAXStandardWindowSubrole)")
        #endif

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.isActive }),
                let window = self.getFocusedWindow(pid: app.processIdentifier),
                self.getRole(element: window) == kAXWindowRole,
                self.getSubRole(element: window) == kAXStandardWindowSubrole
        else { return nil }

        return window
    }

    func resize(window: AXUIElement, direction: WindowDirection, screen: NSScreen) {
        self.setFullscreen(element: window, state: false)

        let windowFrame = getRect(element: window)
        guard let screenFrame = getScreenFrame(screen: screen),
              let windowFrame = generateWindowFrame(windowFrame, screenFrame, direction) else { return }

        let windowFrameWithPadding = applyPadding(windowFrame, direction)

        self.setPosition(element: window, position: windowFrameWithPadding.origin)
        self.setSize(element: window, size: windowFrameWithPadding.size)

        if self.getRect(element: window) != windowFrameWithPadding {
            self.handleSizeConstrainedWindow(
                element: window,
                windowFrame: self.getRect(element: window),
                screenFrame: screenFrame,
                direction: direction
            )
        }

        KeybindMonitor.shared.resetPressedKeys()
    }

    private func getFocusedWindow(pid: pid_t) -> AXUIElement? {
        let element = AXUIElementCreateApplication(pid)
        guard let window = element.copyAttributeValue(attribute: kAXFocusedWindowAttribute) else { return nil }
        // swiftlint:disable force_cast
        return (window as! AXUIElement)
        // swiftlint:enable force_cast
    }
    private func getRole(element: AXUIElement) -> String? {
        return element.copyAttributeValue(attribute: kAXRoleAttribute) as? String
    }
    private func getSubRole(element: AXUIElement) -> String? {
        return element.copyAttributeValue(attribute: kAXSubroleAttribute) as? String
    }

    @discardableResult
    private func setFullscreen(element: AXUIElement, state: Bool) -> Bool {
        return element.setAttributeValue(attribute: kAXFullscreenAttribute, value: state ? kCFBooleanTrue : kCFBooleanFalse)
    }
    private func getFullscreen(element: AXUIElement) -> Bool {
        let result = element.copyAttributeValue(attribute: kAXFullscreenAttribute) as? NSNumber
        return result?.boolValue ?? false
    }

    @discardableResult
    private func setPosition(element: AXUIElement, position: CGPoint) -> Bool {
        var position = position
        if let value = AXValueCreate(AXValueType.cgPoint, &position) {
            return element.setAttributeValue(attribute: kAXPositionAttribute, value: value)
        }
        return false
    }
    private func getPosition(element: AXUIElement) -> CGPoint {
        var point: CGPoint = .zero
        guard let value = element.copyAttributeValue(attribute: kAXPositionAttribute) else { return point }
        // swiftlint:disable force_cast
        AXValueGetValue(value as! AXValue, .cgPoint, &point)    // Convert to CGPoint
        // swiftlint:enable force_cast
        return point
    }

    @discardableResult
    private func setSize(element: AXUIElement, size: CGSize) -> Bool {
        var size = size
        if let value = AXValueCreate(AXValueType.cgSize, &size) {
            return element.setAttributeValue(attribute: kAXSizeAttribute, value: value)
        }
        return false
    }
    private func getSize(element: AXUIElement) -> CGSize {
        var size: CGSize = .zero
        guard let value = element.copyAttributeValue(attribute: kAXSizeAttribute) else { return size }
        // swiftlint:disable force_cast
        AXValueGetValue(value as! AXValue, .cgSize, &size)      // Convert to CGSize
        // swiftlint:enable force_cast
        return size
    }

    private func getRect(element: AXUIElement) -> CGRect {
        return CGRect(origin: getPosition(element: element), size: getSize(element: element))
    }

    private func getScreenFrame(screen: NSScreen) -> CGRect? {
        guard let displayID = screen.displayID else { return nil }
        let screenFrameOrigin = CGDisplayBounds(displayID).origin
        var screenFrame: CGRect = screen.visibleFrame

        // Set position of the screenFrame (useful for multiple displays)
        screenFrame.origin = screenFrameOrigin

        // Move screenFrame's y origin to compensate for menubar & dock, if it's on the bottom
        screenFrame.origin.y += (screen.frame.size.height - screen.visibleFrame.size.height)

        // Move screenFrame's x origin when dock is shown on left/right
        screenFrame.origin.x += (screen.frame.size.width - screen.visibleFrame.size.width)

        return screenFrame
    }

    private func generateWindowFrame(_ windowFrame: CGRect, _ screenFrame: CGRect, _ direction: WindowDirection) -> CGRect? {
        let screenWidth = screenFrame.size.width
        let screenHeight = screenFrame.size.height
        let screenX = screenFrame.origin.x
        let screenY = screenFrame.origin.y

        switch direction {
        case .maximize:
            return CGRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight)
        case .center:
            return CGRect(x: screenFrame.midX - windowFrame.width/2,
                          y: screenFrame.midY - windowFrame.height/2,
                          width: windowFrame.width,
                          height: windowFrame.height)
        case .topHalf:
            return CGRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight/2)
        case .rightHalf:
            return CGRect(x: screenX+screenWidth/2, y: screenY, width: screenWidth/2, height: screenHeight)
        case .bottomHalf:
            return CGRect(x: screenX, y: screenY+screenHeight/2, width: screenWidth, height: screenHeight/2)
        case .leftHalf:
            return CGRect(x: screenX, y: screenY, width: screenWidth/2, height: screenHeight)
        case .topRightQuarter:
            return CGRect(x: screenX+screenWidth/2, y: screenY, width: screenWidth/2, height: screenHeight/2)
        case .topLeftQuarter:
            return CGRect(x: screenX, y: screenY, width: screenWidth/2, height: screenHeight/2)
        case .bottomRightQuarter:
            return CGRect(x: screenX+screenWidth/2, y: screenY+screenHeight/2, width: screenWidth/2, height: screenHeight/2)
        case .bottomLeftQuarter:
            return CGRect(x: screenX, y: screenY+screenHeight/2, width: screenWidth/2, height: screenHeight/2)
        case .rightThird:
            return CGRect(x: screenX+2*screenWidth/3, y: screenY, width: screenWidth/3, height: screenHeight)
        case .rightTwoThirds:
            return CGRect(x: screenX+screenWidth/3, y: screenY, width: 2*screenWidth/3, height: screenHeight)
        case .horizontalCenterThird:
            return CGRect(x: screenX+screenWidth/3, y: screenY, width: screenWidth/3, height: screenHeight)
        case .leftThird:
            return CGRect(x: screenX, y: screenY, width: screenWidth/3, height: screenHeight)
        case .leftTwoThirds:
            return CGRect(x: screenX, y: screenY, width: 2*screenWidth/3, height: screenHeight)
        case .topThird:
            return CGRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight/3)
        case .topTwoThirds:
            return CGRect(x: screenX, y: screenY, width: screenWidth, height: 2*screenHeight/3)
        case .verticalCenterThird:
            return CGRect(x: screenX, y: screenY+screenHeight/3, width: screenWidth, height: screenHeight/3)
        case .bottomThird:
            return CGRect(x: screenX, y: screenY+2*screenHeight/3, width: screenWidth, height: screenHeight/3)
        case .bottomTwoThirds:
            return CGRect(x: screenX, y: screenY+screenHeight/3, width: screenWidth, height: 2*screenHeight/3)
        default:
            return nil
        }
    }

    private func applyPadding(_ windowFrame: CGRect, _ direction: WindowDirection) -> CGRect {
        var paddingAppliedRect = windowFrame
        for side in [Edge.top, Edge.bottom, Edge.leading, Edge.trailing] {
            if direction.sidesThatTouchScreen.contains(side) {
                paddingAppliedRect.inset(side, amount: Defaults[.windowPadding])
            } else {
                paddingAppliedRect.inset(side, amount: Defaults[.windowPadding] / 2)
            }
        }
        return paddingAppliedRect
    }

    private func handleSizeConstrainedWindow(element: AXUIElement, windowFrame: CGRect, screenFrame: CGRect, direction: WindowDirection) {

        // If the window is fully shown on the screen
        if (windowFrame.maxX <= screenFrame.maxX) && (windowFrame.maxY <= screenFrame.maxY) {
            return
        }

        // If not, then Loop will auto re-adjust the window size to be fully shown on the screen
        var fixedWindowFrame = windowFrame

        if fixedWindowFrame.maxX > screenFrame.maxX {
            fixedWindowFrame.origin.x = screenFrame.maxX - fixedWindowFrame.width - Defaults[.windowPadding]
        }

        if fixedWindowFrame.maxY > screenFrame.maxY {
            fixedWindowFrame.origin.y = screenFrame.maxY - fixedWindowFrame.height - Defaults[.windowPadding]
        }

//        fixedWindowFrame = applyPadding(fixedWindowFrame, direction)
        setPosition(element: element, position: fixedWindowFrame.origin)
    }
}

extension CGRect {
    mutating func inset(_ side: Edge, amount: CGFloat) {
        switch side {
        case .top:
            self.origin.y += amount
            self.size.height -= amount
        case .leading:
            self.origin.x += amount
            self.size.width -= amount
        case .bottom:
            self.size.height -= amount
        case .trailing:
            self.size.width -= amount
        }
    }
}
