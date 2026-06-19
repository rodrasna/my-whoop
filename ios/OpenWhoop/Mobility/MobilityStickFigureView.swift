import SwiftUI

// MARK: - MobilityStickFigureView
// Monigote simple con Canvas según postura del ejercicio.

struct MobilityStickFigureView: View {
    let pose: MobilityPose

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous)
                .fill(WH.Color.surface2)
            Canvas { context, size in
                drawStickFigure(in: &context, size: size, pose: pose)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityHidden(true)
    }

    private func drawStickFigure(
        in context: inout GraphicsContext,
        size: CGSize,
        pose: MobilityPose
    ) {
        let stroke = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        let color = WH.Color.strainBlue

        let cx = size.width / 2
        let headY = size.height * 0.18
        let neckY = size.height * 0.28
        let hipY = size.height * 0.55
        let footY = size.height * 0.88

        var path = Path()
        path.addEllipse(in: CGRect(x: cx - 7, y: headY - 7, width: 14, height: 14))
        path.move(to: CGPoint(x: cx, y: neckY))
        path.addLine(to: CGPoint(x: cx, y: hipY))

        switch pose {
        case .squat:
            path.move(to: CGPoint(x: cx - 18, y: hipY - 4))
            path.addLine(to: CGPoint(x: cx - 14, y: footY))
            path.move(to: CGPoint(x: cx + 18, y: hipY - 4))
            path.addLine(to: CGPoint(x: cx + 14, y: footY))
            path.move(to: CGPoint(x: cx - 14, y: neckY + 8))
            path.addLine(to: CGPoint(x: cx - 22, y: hipY))
            path.move(to: CGPoint(x: cx + 14, y: neckY + 8))
            path.addLine(to: CGPoint(x: cx + 22, y: hipY))
        case .lunge:
            path.move(to: CGPoint(x: cx - 6, y: hipY))
            path.addLine(to: CGPoint(x: cx - 20, y: footY))
            path.move(to: CGPoint(x: cx + 6, y: hipY))
            path.addLine(to: CGPoint(x: cx + 24, y: hipY + 18))
            path.addLine(to: CGPoint(x: cx + 28, y: footY))
            path.move(to: CGPoint(x: cx - 12, y: neckY + 4))
            path.addLine(to: CGPoint(x: cx - 20, y: hipY - 6))
            path.move(to: CGPoint(x: cx + 12, y: neckY + 4))
            path.addLine(to: CGPoint(x: cx + 18, y: neckY + 16))
        case .shoulderCircle:
            path.move(to: CGPoint(x: cx - 10, y: neckY + 6))
            path.addQuadCurve(to: CGPoint(x: cx + 10, y: neckY + 6),
                              control: CGPoint(x: cx, y: neckY - 14))
            path.move(to: CGPoint(x: cx - 10, y: neckY + 6))
            path.addLine(to: CGPoint(x: cx - 22, y: hipY - 8))
            path.move(to: CGPoint(x: cx + 10, y: neckY + 6))
            path.addLine(to: CGPoint(x: cx + 22, y: hipY - 8))
            path.move(to: CGPoint(x: cx - 8, y: hipY))
            path.addLine(to: CGPoint(x: cx - 10, y: footY))
            path.move(to: CGPoint(x: cx + 8, y: hipY))
            path.addLine(to: CGPoint(x: cx + 10, y: footY))
        case .catCow:
            path.move(to: CGPoint(x: cx - 16, y: hipY))
            path.addLine(to: CGPoint(x: cx - 22, y: footY))
            path.move(to: CGPoint(x: cx + 16, y: hipY))
            path.addLine(to: CGPoint(x: cx + 22, y: footY))
            path.move(to: CGPoint(x: cx - 12, y: neckY + 2))
            path.addLine(to: CGPoint(x: cx - 28, y: neckY + 14))
            path.move(to: CGPoint(x: cx + 12, y: neckY + 2))
            path.addLine(to: CGPoint(x: cx + 28, y: neckY + 14))
            path.move(to: CGPoint(x: cx, y: neckY))
            path.addQuadCurve(to: CGPoint(x: cx + 14, y: neckY + 10),
                              control: CGPoint(x: cx + 8, y: neckY - 6))
        case .childPose:
            path.move(to: CGPoint(x: cx, y: neckY))
            path.addLine(to: CGPoint(x: cx + 8, y: hipY + 10))
            path.move(to: CGPoint(x: cx - 10, y: neckY + 8))
            path.addLine(to: CGPoint(x: cx - 30, y: hipY + 4))
            path.move(to: CGPoint(x: cx + 10, y: neckY + 8))
            path.addLine(to: CGPoint(x: cx + 30, y: hipY + 4))
            path.move(to: CGPoint(x: cx - 6, y: hipY + 10))
            path.addLine(to: CGPoint(x: cx - 18, y: footY - 4))
            path.move(to: CGPoint(x: cx + 6, y: hipY + 10))
            path.addLine(to: CGPoint(x: cx + 18, y: footY - 4))
        case .wristCircle:
            path.move(to: CGPoint(x: cx - 12, y: neckY + 6))
            path.addEllipse(in: CGRect(x: cx - 28, y: neckY + 2, width: 12, height: 12))
            path.move(to: CGPoint(x: cx + 12, y: neckY + 6))
            path.addEllipse(in: CGRect(x: cx + 16, y: neckY + 2, width: 12, height: 12))
            path.move(to: CGPoint(x: cx - 8, y: hipY))
            path.addLine(to: CGPoint(x: cx - 10, y: footY))
            path.move(to: CGPoint(x: cx + 8, y: hipY))
            path.addLine(to: CGPoint(x: cx + 10, y: footY))
        case .hipRotation:
            path.move(to: CGPoint(x: cx - 20, y: hipY + 6))
            path.addLine(to: CGPoint(x: cx - 8, y: footY))
            path.move(to: CGPoint(x: cx + 14, y: hipY + 2))
            path.addLine(to: CGPoint(x: cx + 26, y: hipY + 18))
            path.addLine(to: CGPoint(x: cx + 20, y: footY))
            path.move(to: CGPoint(x: cx - 10, y: neckY + 6))
            path.addLine(to: CGPoint(x: cx - 18, y: hipY))
            path.move(to: CGPoint(x: cx + 10, y: neckY + 6))
            path.addLine(to: CGPoint(x: cx + 16, y: hipY - 4))
        case .thoracicRotation:
            path.move(to: CGPoint(x: cx - 14, y: hipY))
            path.addLine(to: CGPoint(x: cx - 18, y: footY))
            path.move(to: CGPoint(x: cx + 14, y: hipY))
            path.addLine(to: CGPoint(x: cx + 18, y: footY))
            path.move(to: CGPoint(x: cx - 10, y: neckY + 4))
            path.addLine(to: CGPoint(x: cx - 24, y: neckY + 18))
            path.move(to: CGPoint(x: cx + 10, y: neckY + 4))
            path.addLine(to: CGPoint(x: cx + 8, y: neckY - 8))
            path.addLine(to: CGPoint(x: cx + 22, y: neckY + 2))
        case .ankleRock:
            path.move(to: CGPoint(x: cx - 10, y: hipY))
            path.addLine(to: CGPoint(x: cx - 18, y: footY - 8))
            path.move(to: CGPoint(x: cx + 10, y: hipY))
            path.addLine(to: CGPoint(x: cx + 22, y: footY))
            path.move(to: CGPoint(x: cx - 8, y: neckY + 6))
            path.addLine(to: CGPoint(x: cx - 14, y: hipY - 4))
            path.move(to: CGPoint(x: cx + 8, y: neckY + 6))
            path.addLine(to: CGPoint(x: cx + 14, y: hipY - 4))
        case .hamstringStretch, .standingFold:
            path.move(to: CGPoint(x: cx, y: neckY))
            path.addLine(to: CGPoint(x: cx + 4, y: hipY - 4))
            path.move(to: CGPoint(x: cx - 8, y: hipY))
            path.addLine(to: CGPoint(x: cx - 10, y: footY))
            path.move(to: CGPoint(x: cx + 8, y: hipY))
            path.addLine(to: CGPoint(x: cx + 10, y: footY))
            path.move(to: CGPoint(x: cx - 10, y: neckY + 8))
            path.addLine(to: CGPoint(x: cx - 6, y: hipY + 8))
            path.move(to: CGPoint(x: cx + 10, y: neckY + 8))
            path.addLine(to: CGPoint(x: cx + 6, y: hipY + 8))
            path.move(to: CGPoint(x: cx, y: neckY + 4))
            path.addQuadCurve(to: CGPoint(x: cx + 2, y: hipY - 2),
                              control: CGPoint(x: cx + 16, y: neckY + 20))
        }

        context.stroke(path, with: .color(color), style: stroke)
    }
}
