import SwiftUI

/// Outline icons drawn from Tabler Icons' 24×24 path data (stroke 2, round caps and joins).
enum TablerIcon {
    case plus, minus, x, trash, chevronUp, chevronDown, check, circleCheck, alertCircle, infoCircle, movie

    fileprivate func path() -> Path {
        var p = Path()
        func line(_ points: (CGFloat, CGFloat)...) {
            p.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for point in points.dropFirst() {
                p.addLine(to: CGPoint(x: point.0, y: point.1))
            }
        }
        func circle() {
            p.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
        }

        switch self {
        case .plus:
            line((12, 5), (12, 19))
            line((5, 12), (19, 12))
        case .minus:
            line((5, 12), (19, 12))
        case .x:
            line((18, 6), (6, 18))
            line((6, 6), (18, 18))
        case .trash:
            line((4, 7), (20, 7))
            line((10, 11), (10, 17))
            line((14, 11), (14, 17))
            p.move(to: CGPoint(x: 5, y: 7))
            p.addLine(to: CGPoint(x: 6, y: 19))
            p.addQuadCurve(to: CGPoint(x: 8, y: 21), control: CGPoint(x: 6, y: 21))
            p.addLine(to: CGPoint(x: 16, y: 21))
            p.addQuadCurve(to: CGPoint(x: 18, y: 19), control: CGPoint(x: 18, y: 21))
            p.addLine(to: CGPoint(x: 19, y: 7))
            p.move(to: CGPoint(x: 9, y: 7))
            p.addLine(to: CGPoint(x: 9, y: 4))
            p.addQuadCurve(to: CGPoint(x: 10, y: 3), control: CGPoint(x: 9, y: 3))
            p.addLine(to: CGPoint(x: 14, y: 3))
            p.addQuadCurve(to: CGPoint(x: 15, y: 4), control: CGPoint(x: 15, y: 3))
            p.addLine(to: CGPoint(x: 15, y: 7))
        case .chevronUp:
            line((6, 15), (12, 9), (18, 15))
        case .chevronDown:
            line((6, 9), (12, 15), (18, 9))
        case .check:
            line((5, 12), (10, 17), (20, 7))
        case .circleCheck:
            circle()
            line((9, 12), (11, 14), (15, 10))
        case .alertCircle:
            circle()
            line((12, 8), (12, 12))
            line((12, 16), (12.01, 16))
        case .infoCircle:
            circle()
            line((12, 9), (12.01, 9))
            line((11, 12), (12, 12), (12, 16), (13, 16))
        case .movie:
            p.addRoundedRect(in: CGRect(x: 4, y: 4, width: 16, height: 16), cornerSize: CGSize(width: 2, height: 2))
            line((8, 4), (8, 20))
            line((16, 4), (16, 20))
            line((4, 8), (8, 8))
            line((4, 16), (8, 16))
            line((4, 12), (20, 12))
            line((16, 8), (20, 8))
            line((16, 16), (20, 16))
        }
        return p
    }
}

private struct TablerShape: Shape {
    let icon: TablerIcon

    func path(in rect: CGRect) -> Path {
        icon.path().applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

struct Icon: View {
    let icon: TablerIcon
    var size: CGFloat = 20

    init(_ icon: TablerIcon, size: CGFloat = 20) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        TablerShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: max(1.5, 2 * size / 24), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
