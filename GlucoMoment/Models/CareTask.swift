//
//  CareTask.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

struct CareTask: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    var isDone: Bool
}
