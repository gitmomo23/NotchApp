import Foundation

/// Callbacks installed by the panel controller after the SwiftUI tree exists.
final class PanelActions {
    var openPinned: () -> Void = {}
    var togglePin: () -> Void = {}
    var collapse: () -> Void = {}
    var showSettings: () -> Void = {}
    var share: ([URL]) -> Void = { _ in }
    var airDrop: ([URL]) -> Void = { _ in }
}
