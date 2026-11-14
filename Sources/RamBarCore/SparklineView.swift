import SwiftUI

public struct SparklineView: View {
    public let values: [Double]
    public var tint: Color = .primary

    public init(values: [Double], tint: Color = .primary) {
        self.values = values
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            if values.count >= 2 {
                let minVal = max(0, (values.min() ?? 0) - 0.05)
                let maxVal = min(1, max(minVal + 0.1, (values.max() ?? 1) + 0.05))
                let range = max(0.01, maxVal - minVal)

                let points: [CGPoint] = values.enumerated().map { index, value in
                    let x = width * CGFloat(index) / CGFloat(values.count - 1)
                    let normalized = (value - minVal) / range
                    let y = height * (1 - CGFloat(normalized))
                    return CGPoint(x: x, y: y)
                }

                ZStack {
                    Path { path in
                        guard let first = points.first, let last = points.last else { return }
                        path.move(to: CGPoint(x: first.x, y: height))
                        path.addLine(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: last.x, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.25), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        tint.opacity(0.75),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                }
            } else {
                Capsule()
                    .fill(tint.opacity(0.2))
                    .frame(height: 1.5)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}
