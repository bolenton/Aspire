import SwiftUI
import UIKit
import StoryEngine

/// Giant synchronized text: highlights word-by-word as the narrator speaks,
/// and every word is tappable to hear it again — reading optional, encouraged.
struct NarrationTextView: View {
    @ObservedObject var narrator: Narrator
    let theme: Theme

    private struct Word: Identifiable {
        let id: Int
        let text: String
        let range: NSRange
    }

    private var words: [Word] {
        var result: [Word] = []
        var location = 0
        for (index, piece) in narrator.currentText.components(separatedBy: " ").enumerated() {
            let length = (piece as NSString).length
            result.append(Word(id: index, text: piece, range: NSRange(location: location, length: length)))
            location += length + 1
        }
        return result
    }

    private func isHighlighted(_ word: Word) -> Bool {
        guard let range = narrator.highlightRange else { return false }
        return NSIntersectionRange(range, word.range).length > 0
    }

    var body: some View {
        FlowLayout(spacing: theme.fontSize(7)) {
            ForEach(words) { word in
                Button {
                    narrator.speakWord(word.text)
                } label: {
                    Text(word.text)
                        .font(.system(size: theme.fontSize(26), weight: .semibold, design: .rounded))
                        .foregroundColor(isHighlighted(word) ? theme.background : theme.text)
                        .padding(.horizontal, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isHighlighted(word) ? theme.highlight : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.12), value: narrator.highlightRange)
    }
}

/// Minimal wrapping layout for the word buttons.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// App-wide two-finger hold: "freeze and explain". Attached to the window so
/// it works on every screen without stealing normal touches.
struct FreezeGestureView: UIViewRepresentable {
    let onBegan: () -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            guard context.coordinator.recognizer == nil, let window = view.window else { return }
            let recognizer = UILongPressGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handle(_:)))
            recognizer.numberOfTouchesRequired = 2
            recognizer.minimumPressDuration = 0.4
            recognizer.cancelsTouchesInView = false
            window.addGestureRecognizer(recognizer)
            context.coordinator.recognizer = recognizer
            context.coordinator.window = window
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer {
            coordinator.window?.removeGestureRecognizer(recognizer)
        }
    }

    final class Coordinator: NSObject {
        let onBegan: () -> Void
        let onEnded: () -> Void
        var recognizer: UILongPressGestureRecognizer?
        weak var window: UIWindow?

        init(onBegan: @escaping () -> Void, onEnded: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onEnded = onEnded
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onBegan()
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }
    }
}
