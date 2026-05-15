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
                    Label("Tab.TalkNow", systemImage: "mic.fill")
                }
            TranscriptionsListView()
                .tabItem {
                    Label("Tab.Transcriptions", systemImage: "list.bullet.rectangle")
                }
            MoreView()
                .tabItem {
                    Label("Tab.Settings", systemImage: "gear")
                }
        }
    }
}
