//
//  MainTabView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2024/06/08.
//

import SwiftUI

struct MainTabView: View {

    var body: some View {
        TabView {
            TalkNowView()
                .tabItem {
                    Label("Talk Now", systemImage: "mic.fill")
                }
        }
    }
}
