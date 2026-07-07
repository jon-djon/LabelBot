//
//  IconChoiceButton.swift
//  LabelBot
//

import SwiftUI

/// A single selectable icon swatch with a caption, used in the icon grids.
struct IconChoiceButton: View {
    let image: NSImage?
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .interpolation(.high)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "nosign")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40, height: 40)
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: Design.swatchCornerRadius)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Design.swatchCornerRadius)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                }

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
