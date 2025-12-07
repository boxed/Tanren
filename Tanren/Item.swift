//
//  Item.swift
//  Tanren
//
//  Created by Anders Hovmöller on 2025-12-07.
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
