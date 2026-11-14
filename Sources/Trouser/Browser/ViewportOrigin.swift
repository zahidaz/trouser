import QuartzCore

enum ViewportOrigin {
    static let scrolledLayerName = "frame scrolled contents"
    static let scrollContainerName = "scroll container"

    static func read(from root: CALayer) -> CGPoint? {
        var level = [root]
        while !level.isEmpty {
            if let scrolled = level.first(where: { $0.name == scrolledLayerName }) {
                return CGPoint(x: -scrolled.position.x, y: -scrolled.position.y)
            }
            level = level.flatMap { $0.sublayers ?? [] }
        }
        return nil
    }

    static func scrollPositions(in root: CALayer) -> [CGPoint] {
        var positions: [CGPoint] = []
        var level = [root]
        while !level.isEmpty {
            for layer in level {
                if layer.name == scrolledLayerName {
                    positions.append(CGPoint(x: -layer.position.x, y: -layer.position.y))
                } else if layer.name == scrollContainerName {
                    positions.append(layer.bounds.origin)
                }
            }
            level = level.flatMap { $0.sublayers ?? [] }
        }
        return positions
    }
}
