import Observation
import SwiftUI

/// Where the panel's map is magnified and moved to, and whether it's
/// selected. The panel's gestures move it, and so do the app's scroll wheel
/// and keys, which find the map by `frame`. Snapshots and widgets have none:
/// they draw the framing itself.
@MainActor
@Observable
public final class MapViewport {
    public private(set) var transform = MapTransform.identity
    /// Selected, ↑ and ↓ zoom the map.
    public var isSelected = false
    /// Where the map shows in its window, from the top left.
    public var frame: CGRect = .zero
    /// The map's size, as last laid out, in its own units.
    public var size: CGSize = .zero
    /// Points to one of the map's units: 1 where the map is drawn in
    /// points, a dot's breadth where it is drawn in a terminal's dots.
    public var unit = CGSize(width: 1, height: 1)
    /// How far the map may be magnified.
    public var maxZoom = 8.0

    public init() {}

    public var zoom: Double { transform.zoom }
    public var isZoomed: Bool { transform.zoom > 1.001 }

    /// Magnifies the map by `factor` about `anchor`, in points from the
    /// map's top left, or about its middle. A step of the keyboard's eases
    /// there; a scroll or a pinch follows at once.
    public func zoom(by factor: Double, at anchor: CGPoint? = nil, easing: Animation? = nil) {
        guard size.width > 0, factor.isFinite, factor > 0 else { return }
        let a = anchor.map { CGPoint(x: $0.x / unit.width, y: $0.y / unit.height) } ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let t = transform.zoomed(by: factor, about: a).clamped(to: size, maxZoom: maxZoom)
        withAnimation(easing) { transform = t }
    }

    /// Moves the magnified map by `d` points, as the pointer drags it.
    public func pan(by d: CGSize) {
        guard size.width > 0 else { return }
        var t = transform
        t.offset.x += d.width / unit.width
        t.offset.y += d.height / unit.height
        transform = t.clamped(to: size, maxZoom: maxZoom)
    }

    /// Back to the framing.
    public func reset(easing: Animation? = nil) {
        withAnimation(easing) { transform = .identity }
    }

    /// How a keyboard step or a way back eases, or nil under Reduce Motion.
    public static func easing(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeInOut(duration: 0.28) }

    /// One step of the keyboard's zoom: ↑ in, ↓ out.
    public static let step = 1.5

    /// A step of the keyboard's zoom, in when `zoomIn`, else out; a step
    /// out that would leave the map barely magnified goes back to its
    /// framing.
    public func step(in zoomIn: Bool, easing: Animation? = nil) {
        var f = zoomIn ? Self.step : 1 / Self.step
        if !zoomIn, transform.zoom * f < 1.25 { f = 1 / transform.zoom }
        zoom(by: f, easing: easing)
    }

    /// Lays the map out at `size`, in units of `unit` points; a new size
    /// keeps the magnification, held inside the map.
    func layout(_ size: CGSize, unit: CGSize = CGSize(width: 1, height: 1)) {
        guard size != self.size || unit != self.unit else { return }
        self.size = size
        self.unit = unit
        transform = transform.clamped(to: size, maxZoom: maxZoom)
    }
}

extension EnvironmentValues {
    /// The panel's map viewport; none where the map is drawn still.
    @Entry public var mapViewport: MapViewport?
}
