# 稳糖食刻 GlucoMoment

> 看懂每一餐，从容每一刻。

稳糖食刻是一款面向糖尿病患者的 iOS 饮食与血糖管理 App。拍下一餐，App 识别食物和份量，用公式算出「稳糖分」，再结合 Apple 健康里的血糖数据，帮你看懂这一餐对血糖的影响。

本项目是 2026 中国高校计算机大赛—移动应用创新赛的参赛作品（上海应用技术大学）。

> [!IMPORTANT]
> 稳糖食刻不是医疗器械，不提供诊断或治疗建议。识别结果和稳糖分都是估算值，调整饮食、用药前请咨询医生。

## 功能

- **拍照识餐**：同一餐最多 6 张照片一起识别，可以先补充一句文字说明（比如「米饭只吃了半碗」）。包装食品会优先读取营养成分表。
- **复核与一句话修正**：识别结果可以逐项手动修改，也可以直接说哪里不对，由模型给出改动，App 合并后重新计算。
- **稳糖分**：由大模型识别食物、份量和类别，分数本身不由模型给出，而是按整餐血糖负荷（GL）计算，再根据蔬菜、蛋白质、全谷物和添加糖加减分。血糖影响按 WS/T 652 的 GL 分级标注，App 内有「评分依据」页说明计算过程。
- **稳糖建议**：按固定规则根据稳糖分的构成生成，每条建议都对应《成人糖尿病食养指南（2023 年版）》的具体条目。
- **血糖记录与 Apple 健康同步**：本地记录血糖，并与 Apple 健康双向同步最近 30 天的血糖，以及热量、碳水、蛋白质、脂肪、膳食纤维五项营养。CGM 写入健康的数据可以直接用。
- **AI 近期复盘（可选）**：默认关闭。开启后，App 在本地算好每餐的餐后指标和对比，交给模型写成复盘；模型写的数字会在本地校验后再填入，校验不通过时改用本地模板。

## 识别方式

在「设置 → AI 食物识别」中选择：

| 方式 | 说明 |
|---|---|
| 演示 | 离线运行，返回内置示例结果，适合体验和开发 |
| 自定义 API | 自备 API Key，直连 OpenAI 兼容接口。预设了百炼、OpenAI、Gemini、智谱、火山方舟、Kimi、DeepSeek，也可以自定义地址和模型 |
| 自建代理 | 调用 [`Backend/FoodAnalysisProxy`](Backend/FoodAnalysisProxy) 部署的服务，Key 只保存在服务器上 |

## 隐私

- 血糖、餐食和照片都保存在本机（SwiftData + Application Support），没有账号，也没有云端数据库。
- 自备的 API Key 只存在系统钥匙串里。
- 照片上传前会压缩并移除 EXIF 等元数据。
- 代理是无状态的，不保存图片、文字说明或餐食记录，也不在日志里记录请求内容。
- Apple 健康的数据不会发给识别服务。只有你在说明页同意并开启「AI 复盘」后，才会发送最近 14 天的餐后血糖摘要（不含照片）。

## 构建与运行

环境要求：Xcode 26.5 及以上，iOS 26.5 及以上。iOS 端没有第三方依赖。

```bash
git clone https://github.com/zcy0602/GlucoMoment.git
cd GlucoMoment
open GlucoMoment.xcodeproj
```

在 Xcode 中把 Signing 的 Team 改成你自己的开发者账号（必要时同时修改 Bundle Identifier），然后运行即可。Apple 健康同步需要真机。首次运行建议在设置里选「演示」模式，不需要任何 Key。

运行单元测试（Swift Testing）：

```bash
xcodebuild -project GlucoMoment.xcodeproj -scheme GlucoMoment -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:GlucoMomentTests
```

### 识别代理

代理基于 Node.js + Express，负责保管模型 Key、限流、维护提示词并校验模型输出。

```bash
cd Backend/FoodAnalysisProxy
npm install
cp .env.example .env   # 填入你自己的模型地址和 Key
npm run dev:server
```

接口说明和 Windows Server 部署步骤见 [代理 README](Backend/FoodAnalysisProxy/README.md)。

## 项目结构

```text
GlucoMoment/
├── App/            # 入口、依赖装配、标签页、识别设置
├── Domain/         # 业务模型、仓库协议、稳糖分与建议规则、识别服务、HealthKit 同步
├── Data/           # SwiftData 实体、版本化 Schema 与迁移、照片存储
├── Models/         # 展示模型与结构化识别结果
├── ViewModels/
├── Views/
└── DesignSystem/   # 品牌色、日期格式
GlucoMomentTests/   # 单元测试（Swift Testing）
GlucoMomentUITests/
Backend/FoodAnalysisProxy/   # 识别代理（TypeScript）
```

App 采用 MVVM + SwiftUI，ViewModel 使用 `@Observable`，数据通过 Repository 读写 SwiftData。

## 参考资料

- 《成人糖尿病食养指南（2023 年版）》，国家卫生健康委员会
- WS/T 652-2019《食物血糖生成指数测定方法》
- WS/T 429—2013《成人糖尿病患者膳食指导》

## 许可协议

源代码以 [MIT 协议](LICENSE) 开源。

以下内容不在 MIT 授权范围内：

- 「稳糖食刻」「GlucoMoment」名称、logo 与 App 图标；
- Apple 健康图标，其权利归 Apple Inc. 所有；
- 上述参考资料的原文，其版权归原作者或发布机构所有。
