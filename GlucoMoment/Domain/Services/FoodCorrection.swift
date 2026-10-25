//
//  FoodCorrection.swift
//  GlucoMoment
//
//  一句话修正：用户说明哪里不对，模型只返回改动的条目，App 合并到当前记录。
//  服务端不保存会话，每次请求都带上当前记录（含用户手动修改）和之前的修正。
//

import Foundation

/// 一轮修正：用户的说明和模型的回复
nonisolated struct FoodCorrectionTurn: Hashable, Sendable {
    var instruction: String
    var reply: String
}

nonisolated struct FoodCorrectionRequest: Sendable {
    var current: FoodRecognitionResult
    var instruction: String
    var history: [FoodCorrectionTurn]
    var userFoodContext: String?
    var mealPeriod: MealPeriod?
    /// 可选；为空时只按文字修正
    var images: [Data] = []
}

nonisolated struct FoodCorrectionOutcome: Sendable {
    var result: FoodRecognitionResult
    var reply: String
    /// 本次修改或新增的条目，界面据此高亮
    var changedItemIDs: Set<UUID>
}

nonisolated enum FoodCorrectionLimit {
    /// 须与代理 `core.ts` 的 `MAX_CORRECTION_LENGTH` 保持一致
    static let maxInstructionLength = 200
    static let maxHistoryCount = 10
}

/// 模型给出的改动。ref 从 1 开始，对应当前记录中的第几条；没有提到的条目原样保留
nonisolated struct FoodCorrectionPatch: Sendable {
    var reply: String
    var mealName: String?
    var updatedItems: [Int: FoodRecognitionItem] = [:]
    var addedItems: [FoodRecognitionItem] = []
    var removedRefs: Set<Int> = []
    /// 为 nil 时保留原来的追问
    var followUpQuestions: [String]?

    /// 同一条既修改又删除时以删除为准；超出范围的 ref 忽略
    func apply(to current: FoodRecognitionResult) throws -> FoodCorrectionOutcome {
        var items: [FoodRecognitionItem] = []
        var changedItemIDs: Set<UUID> = []

        for (index, item) in current.items.enumerated() {
            let ref = index + 1
            if removedRefs.contains(ref) {
                continue
            }
            if var updated = updatedItems[ref] {
                updated.id = item.id
                updated.foodCategory = updated.foodCategory ?? item.foodCategory
                items.append(updated)
                changedItemIDs.insert(item.id)
            } else {
                items.append(item)
            }
        }

        for item in addedItems {
            items.append(item)
            changedItemIDs.insert(item.id)
        }

        guard !items.isEmpty else {
            throw FoodAnalysisError.correctionRemovedAllItems
        }

        var result = current
        result.items = items
        if let mealName = mealName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mealName.isEmpty {
            result.name = mealName
        }
        if let followUpQuestions {
            result.followUpQuestions = Array(followUpQuestions.prefix(3))
        }

        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackReply = changedItemIDs.isEmpty && items.count == current.items.count
            ? "没有找到需要修改的内容，可以换个说法再试一次。"
            : "已按你的说明修改。"
        return FoodCorrectionOutcome(
            result: result,
            reply: trimmedReply.isEmpty ? fallbackReply : trimmedReply,
            changedItemIDs: changedItemIDs
        )
    }
}

/// 发给模型的当前记录与修正记录；代理会按同样的结构重新校验
nonisolated enum FoodCorrectionRecord {
    static func recordJSON(for result: FoodRecognitionResult) -> String {
        let record = RecordDTO(
            mealName: result.name,
            items: result.items.enumerated().map { index, item in
                RecordItemDTO(
                    ref: index + 1,
                    name: item.name,
                    portionDescription: item.portionDescription,
                    foodCategory: item.foodCategory?.rawValue ?? "未选择",
                    estimatedGrams: rounded(item.estimatedGrams),
                    calories: rounded(item.caloriesKcal),
                    carbs: rounded(item.carbohydratesGrams),
                    protein: rounded(item.proteinGrams),
                    fat: rounded(item.fatGrams),
                    fiber: rounded(item.fiberGrams)
                )
            }
        )
        return encode(record) ?? "{}"
    }

    static func historyJSON(_ history: [FoodCorrectionTurn]) -> String {
        let turns = history.suffix(FoodCorrectionLimit.maxHistoryCount).map {
            TurnDTO(instruction: $0.instruction, reply: $0.reply)
        }
        return encode(turns) ?? "[]"
    }

    private static func rounded(_ value: Double) -> Double {
        (max(0, value) * 10).rounded() / 10
    }

    private static func encode(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated struct RecordDTO: Encodable {
        let mealName: String
        let items: [RecordItemDTO]
    }

    private nonisolated struct RecordItemDTO: Encodable {
        let ref: Int
        let name: String
        let portionDescription: String
        let foodCategory: String
        let estimatedGrams: Double
        let calories: Double
        let carbs: Double
        let protein: Double
        let fat: Double
        let fiber: Double
    }

    private nonisolated struct TurnDTO: Encodable {
        let instruction: String
        let reply: String
    }
}

/// 代理和直连模型返回的修正结果结构相同；代理额外带 provider 等字段，解码时忽略
nonisolated struct FoodCorrectionPayloadDTO: Decodable, Sendable {
    let reply: String?
    let mealName: String?
    let updatedItems: [FoodCorrectionUpdatedItemDTO]?
    let addedItems: [FoodAnalysisItemDTO]?
    let removedRefs: [FoodCorrectionRefDTO]?
    let followUpQuestions: [String]?

    func makePatch() throws -> FoodCorrectionPatch {
        var updated: [Int: FoodRecognitionItem] = [:]
        for entry in updatedItems ?? [] {
            guard let ref = entry.ref.value, updated[ref] == nil else { continue }
            updated[ref] = try entry.item.result
        }

        return FoodCorrectionPatch(
            reply: reply ?? "",
            mealName: mealName,
            updatedItems: updated,
            addedItems: try (addedItems ?? []).prefix(10).map { try $0.result },
            removedRefs: Set((removedRefs ?? []).compactMap(\.value)),
            followUpQuestions: followUpQuestions
        )
    }
}

nonisolated struct FoodCorrectionUpdatedItemDTO: Decodable, Sendable {
    let ref: FoodCorrectionRefDTO
    let item: FoodAnalysisItemDTO

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ref = try container.decode(FoodCorrectionRefDTO.self, forKey: .ref)
        item = try FoodAnalysisItemDTO(from: decoder)
    }

    private enum CodingKeys: String, CodingKey {
        case ref
    }
}

/// 模型偶尔把编号写成字符串，两种都接受；无法识别时为 nil
nonisolated struct FoodCorrectionRefDTO: Decodable, Sendable {
    let value: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Int(text.trimmingCharacters(in: .whitespaces))
        } else {
            value = nil
        }
    }
}
