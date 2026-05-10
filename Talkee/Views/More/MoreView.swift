//
//  MoreView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftUI

struct MoreView: View {

    var body: some View {
        NavigationStack {
            List {
                aboutSection
            }
            .navigationTitle("Tab.More")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            Link(destination: URL(string: "https://github.com/katagaki/Talkee")!) {
                HStack {
                    Text("More.SourceCode")
                    Spacer()
                    Text("katagaki/Talkee")
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
            NavigationLink {
                MoreAttributionsView()
            } label: {
                Text("More.Attributions")
            }
        }
    }
}
