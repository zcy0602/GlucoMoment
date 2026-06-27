//
//  Item.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
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
