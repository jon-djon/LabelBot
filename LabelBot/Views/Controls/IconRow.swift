//
//  IconRow.swift
//  LabelBot
//

import SwiftUI

/// A horizontally-scrolling row of selectable icon buttons.
struct IconRow<Option: Identifiable & Hashable>: View {
    let options: [Option]
    let image: (Option) -> NSImage?
    let title: (Option) -> String
    let selected: (Option) -> Bool
    let select: (Option) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(options) { option in
                    IconChoiceButton(image: image(option), title: title(option), selected: selected(option)) {
                        select(option)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
