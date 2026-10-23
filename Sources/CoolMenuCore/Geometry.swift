import CoreGraphics
import Foundation

/// A snap area expressed as fractions of a screen's visible frame, origin at the top-left.
public struct Zone: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(id: UUID = UUID(), name: String, x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Frame in AppKit coordinates (bottom-left origin) inside `visible`.
    public func frame(in visible: CGRect) -> CGRect {
        CGRect(
            x: (visible.minX + x * visible.width).rounded(),
            y: (visible.maxY - (y + height) * visible.height).rounded(),
            width: (width * visible.width).rounded(),
            height: (height * visible.height).rounded()
        )
    }
}

public enum Orientation: String, Codable, CaseIterable, Hashable {
    case landscape
    case portrait

    public static func of(_ size: CGSize) -> Orientation {
        size.height > size.width ? .portrait : .landscape
    }
}

/// A set of zones that applies to screens of a given orientation and minimum width (points).
public struct ZoneLayout: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var orientation: Orientation
    public var minWidth: Double
    public var zones: [Zone]

    public init(id: UUID = UUID(), name: String, orientation: Orientation, minWidth: Double = 0, zones: [Zone]) {
        self.id = id
        self.name = name
        self.orientation = orientation
        self.minWidth = minWidth
        self.zones = zones
    }

    public func zone(named name: String) -> Zone? {
        zones.first { $0.name == name }
    }
}

public enum LayoutPicker {
    /// The most specific layout for a screen: matching orientation, largest `minWidth` that still fits.
    public static func pick(_ layouts: [ZoneLayout], for screenSize: CGSize) -> ZoneLayout? {
        let orientation = Orientation.of(screenSize)
        return layouts
            .filter { $0.orientation == orientation && $0.minWidth <= screenSize.width }
            .max { $0.minWidth < $1.minWidth }
    }
}

public enum ZoneCycler {
    /// Index of the zone to apply next when a binding with several zones is pressed.
    /// Advances when the window still sits where the previous press put it (apps with size
    /// increments never land exactly on the zone), or when it already matches a candidate.
    public static func nextIndex(
        current: CGRect,
        candidates: [CGRect],
        lastIndex: Int?,
        lastResult: CGRect?,
        tolerance: CGFloat = 8
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        if let lastIndex, let lastResult, approximatelyEqual(current, lastResult, tolerance: tolerance) {
            return (lastIndex + 1) % candidates.count
        }
        if let i = candidates.firstIndex(where: { approximatelyEqual($0, current, tolerance: tolerance) }) {
            return (i + 1) % candidates.count
        }
        return 0
    }

    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

public enum GridLayout {
    /// Tiles `count` windows into a near-square grid, filling rows top to bottom (AppKit coordinates).
    /// The last row stretches its windows when it is not full.
    public static func frames(count: Int, in rect: CGRect, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let cols = Int(ceil(Double(count).squareRoot()))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let height = (rect.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        return (0..<count).map { i in
            let row = i / cols
            let col = i % cols
            let colsInRow = row == rows - 1 ? count - cols * (rows - 1) : cols
            let width = (rect.width - gap * CGFloat(colsInRow + 1)) / CGFloat(colsInRow)
            return CGRect(
                x: (rect.minX + gap + CGFloat(col) * (width + gap)).rounded(),
                y: (rect.maxY - CGFloat(row + 1) * (height + gap)).rounded(),
                width: width.rounded(),
                height: height.rounded()
            )
        }
    }
}

public enum ScreenCoordinates {
    /// Converts between AppKit (bottom-left origin) and Accessibility/CoreGraphics (top-left origin)
    /// global coordinates. The transform is its own inverse.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Maps `rect` from one visible frame to another, keeping its relative position and size.
    public static func remap(_ rect: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let sx = target.width / source.width
        let sy = target.height / source.height
        let width = min(rect.width * sx, target.width)
        let height = min(rect.height * sy, target.height)
        let x = target.minX + (rect.minX - source.minX) * sx
        let y = target.minY + (rect.minY - source.minY) * sy
        return CGRect(
            x: min(max(x, target.minX), target.maxX - width).rounded(),
            y: min(max(y, target.minY), target.maxY - height).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }
}
