//
//  Item.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2024/06/08.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
