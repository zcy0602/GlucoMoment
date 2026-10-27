# LiDAR 两段式识别接口

iOS App 在有 LiDAR 的设备上使用两段式识别：

1. `POST /v1/food/detect`：定位图片中的食物和容器（名称、边界框、叠放关系、密度区间）。
2. App 在本地完成分割、高度图积分和密度换算，得到每种食物的实测体积与克重区间。
3. `POST /v1/food/estimate`：上传实测数据，由模型给出最终克重、营养与建议。

两个接口与 `/v1/food/analyze` 位于同一路径前缀下。例如 App 中配置的地址为 `https://example.com/api/v1/food/analyze` 时，App 会请求 `https://example.com/api/v1/food/detect`。若配置的地址不以 `/v1/food/analyze` 结尾，则使用根路径 `/v1/food/detect`。

通用约定与现有接口一致：

- 请求为 `multipart/form-data`，图片字段名为 `image`（JPEG，≤ 8MB，已转正、无位置元数据）。
- 请求头：`X-Request-Id`（同一请求重试时不变）、`X-Install-Id`。
- 错误响应：非 2xx 状态码 + `{"message": "面向用户的中文提示", "requestId": "..."}`。App 会对 408、429、5xx 自动重试。
- 不得在日志中记录图片、用户描述或实测数据。

---

## 1. `POST /v1/food/detect`

### 表单字段

| 字段 | 说明 |
| --- | --- |
| `image` | 最佳俯视帧 JPEG |
| `requestId` | 与 `X-Request-Id` 相同 |
| `schemaVersion` | 固定为 `2` |
| `locale` | `zh-CN` |
| `mealPeriod` | 餐次（早餐 / 午餐 / 晚餐 / 加餐），可能为空 |
| `userFoodContext` | 用户补充描述，≤ 500 字，可能为空；只能作为事实背景 |

### 提示词

服务端应使用与 App 直连模式相同的提示词（`QwenFoodAnalysisService.detectionSystemPrompt`，版本 `food-detect-v1`），要求模型只返回 JSON。

### 响应

```json
{
  "provider": "qwen",
  "model": "qwen3.7-plus",
  "promptVersion": "food-detect-v1",
  "mealName": "红烧肉盖饭",
  "containers": [
    { "index": 0, "type": "shallowBowl", "box": [120, 180, 880, 820] }
  ],
  "items": [
    {
      "index": 0,
      "name": "米饭",
      "category": "staple",
      "box": [180, 240, 820, 760],
      "containerIndex": 0,
      "layeredOnIndex": null,
      "layerThicknessCmMin": 0,
      "layerThicknessCmMax": 0,
      "densityMin": 0.75,
      "densityMax": 0.9,
      "confidence": 0.9
    },
    {
      "index": 1,
      "name": "红烧肉",
      "category": "meat",
      "box": [380, 380, 640, 620],
      "containerIndex": 0,
      "layeredOnIndex": 0,
      "layerThicknessCmMin": 1,
      "layerThicknessCmMax": 2,
      "densityMin": 0.75,
      "densityMax": 1.0,
      "confidence": 0.85
    }
  ],
  "uncertainties": ["酱汁覆盖部分米饭，下层米饭份量为估计值"]
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `box` | `[x1, y1, x2, y2]` | 0～1000 的整数，相对图片宽高归一化，左上角为原点 |
| `containers[].type` | 字符串 | `flatPlate` / `shallowBowl` / `deepBowl` / `cup` / `noContainer`；未知值按 `flatPlate` 处理 |
| `items[].category` | 字符串 | `staple` / `vegetable` / `meat` / `seafood` / `egg` / `soy` / `soup` / `beverage` / `fruit` / `snack` / `mixed` / `other`；未知值按 `other` 处理 |
| `items[].containerIndex` | 整数或 `null` | 指向 `containers[].index` |
| `items[].layeredOnIndex` | 整数或 `null` | 本食物铺在哪个食物之上，指向 `items[].index` |
| `layerThicknessCm*` | 数字 | 上层食物自身厚度（厘米），无叠放时为 0 |
| `density*` | 数字 | 盛装状态下的表观密度（g/ml），可选 |
| `containers`、`uncertainties` | 数组 | 可选 |

App 端校验规则（服务端可以做同样的校验，也可以直接透传）：

- 宽或高小于 10（即 1%）的框、名称为空的食物会被丢弃；去除后至少保留 1 个、最多 20 个食物，否则视为无效响应。
- 指向不存在容器或食物的引用会被置空；互相叠放时只保留一个方向。
- 有叠放但未给出层厚时，默认 0.5～2.0 cm。

---

## 2. `POST /v1/food/estimate`

### 表单字段

在检测接口字段的基础上增加：

| 字段 | 说明 |
| --- | --- |
| `measurements` | 实测报告 JSON 字符串，结构见下文 |

`measurements` 示例：

```json
{
  "mealName": "红烧肉盖饭",
  "items": [
    {
      "itemIndex": 0,
      "name": "米饭",
      "category": "staple",
      "containerType": "shallowBowl",
      "layeredOnIndex": null,
      "layeredOnName": null,
      "volumeMl": 205.3,
      "volumeMinMl": 176.1,
      "volumeMaxMl": 238.4,
      "footprintAreaCm2": 118.2,
      "meanHeightCm": 1.7,
      "coverage": 0.93,
      "densityGPerMl": 0.83,
      "densitySource": "localTable",
      "measuredGrams": 169.4,
      "measuredGramsMin": 132.1,
      "measuredGramsMax": 214.6,
      "notes": ["部分被其他食物遮挡，被遮挡部分为估计值"]
    }
  ]
}
```

- `densitySource`：`localTable`（App 内置密度表）/ `model`（检测阶段模型给出）/ `categoryDefault`（类别默认值）。
- `notes`：App 生成的中文测量提示，可直接放入提示词。
- 用户在 App 中修正分割、容器类型或层厚后，上传的是修正后的结果。

### 提示词

服务端应使用 `QwenFoodAnalysisService.measuredSystemPrompt`（版本 `food-measured-v1`），并把实测报告放在 `<lidar_measurements>` 标签中，声明其只能作为事实参考。核心要求：

- 重量以 `measuredGramsMin`～`measuredGramsMax` 为主要依据，只有图片明显显示测量有误时才调整，并在该食物的 `uncertainties` 中说明。
- `items` 与实测数据一一对应，`itemIndex` 必须相同，不得新增或遗漏。

### 响应

与 `/v1/food/analyze` 的响应结构相同，每个 `items[]` 额外包含 `itemIndex`：

```json
{
  "provider": "qwen",
  "model": "qwen3.7-plus",
  "promptVersion": "food-measured-v1",
  "mealName": "红烧肉盖饭",
  "overallConfidence": 0.82,
  "glucoseImpact": "较高",
  "score": 62,
  "items": [
    {
      "itemIndex": 0,
      "name": "米饭",
      "portionDescription": "约 170g（LiDAR 实测）",
      "estimatedGramsMin": 150,
      "estimatedGramsMax": 190,
      "caloriesMin": 175,
      "caloriesMax": 220,
      "carbsMin": 39,
      "carbsMax": 49,
      "proteinMin": 4,
      "proteinMax": 5,
      "fatMin": 0,
      "fatMax": 1,
      "fiberMin": 0,
      "fiberMax": 1,
      "confidence": 0.85,
      "evidence": "LiDAR 实测体积与米饭密度",
      "uncertainties": []
    }
  ],
  "followUpQuestions": ["红烧肉的酱汁是否偏甜？"],
  "suggestions": ["可以先吃肉和蔬菜，再吃米饭。"],
  "uncertainties": []
}
```

App 按 `itemIndex` 把实测数据挂到对应条目上；缺少 `itemIndex` 时按顺序匹配。若模型给出的重量超出实测区间的 0.8～1.2 倍，App 会在该条目的不确定性中提示用户检查。

---

## 兼容性

- 未实现这两个接口的旧服务器会返回 404，App 会显示错误。届时用户可以在扫描界面切换到「普通拍照」，继续使用 `/v1/food/analyze`。
- `GET /health` 无需修改；建议在响应中增加 `"measurementPromptVersions": ["food-detect-v1", "food-measured-v1"]`，方便排查。
