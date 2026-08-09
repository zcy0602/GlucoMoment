//
//  FoodAnalysisSettingsView.swift
//  GlucoMoment
//

import SwiftUI

struct FoodAnalysisSettingsView: View {
    @Bindable var settings: FoodAnalysisSettings
    let credentialStore: any FoodAnalysisCredentialStoring

    @State private var apiKeyInput = ""
    @State private var hasStoredAPIKey = false
    @State private var operationState: OperationState = .idle
    @State private var confirmsKeyDeletion = false
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section {
                Picker("识别方式", selection: $settings.mode) {
                    ForEach(FoodAnalysisConnectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(settings.mode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("食物识别")
            }

            switch settings.mode {
            case .demo:
                demoSection
            case .directQwen:
                directQwenSection
            case .proxy:
                proxySection
            }

            if case .idle = operationState {
                EmptyView()
            } else {
                statusSection
            }

            Section("隐私与费用") {
                Label("识别照片和补充描述会发送到当前选择的服务。", systemImage: "photo.badge.arrow.down")
                Label("App 内直连的调用费用由所填写 Key 对应的阿里云账户承担。", systemImage: "creditcard")
                Label("营养结果是模型估算，不代替医疗或用药建议。", systemImage: "cross.case")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("AI 食物识别")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { await refreshCredentialStatus() }
        .onDisappear { apiKeyInput = "" }
        .alert("删除 API Key？", isPresented: $confirmsKeyDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteAPIKey() }
            }
        } message: {
            Text("将从本机钥匙串删除，之后使用 App 内直连需要重新填写。")
        }
    }

    private var demoSection: some View {
        Section("演示模式") {
            Label("使用本地固定结果，不上传照片。", systemImage: "iphone")
                .foregroundStyle(.secondary)
        }
    }

    private var directQwenSection: some View {
        Section {
            LabeledContent("模型", value: FoodAnalysisSettings.qwenModel)
            LabeledContent("API 地址", value: "阿里云中国大陆")

            HStack {
                Label(
                    hasStoredAPIKey ? "已保存到钥匙串" : "尚未保存 API Key",
                    systemImage: hasStoredAPIKey ? "key.fill" : "key"
                )
                .foregroundStyle(hasStoredAPIKey ? Color.brandLeaf : .secondary)
                Spacer()
            }

            SecureField("输入新的 API Key", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .focused($focusedField, equals: .apiKey)
                .accessibilityIdentifier("qwen-api-key-field")

            Button {
                Task { await saveAndTestAPIKey() }
            } label: {
                Label("保存并测试连接", systemImage: "checkmark.shield")
            }
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || operationState.isWorking)
            .accessibilityIdentifier("save-test-qwen-key")

            if hasStoredAPIKey {
                Button("测试已保存的 Key") {
                    Task { await testStoredAPIKey() }
                }
                .disabled(operationState.isWorking)

                Button("删除已保存的 Key", role: .destructive) {
                    confirmsKeyDeletion = true
                }
            }
        } header: {
            Text("阿里云百炼直连")
        } footer: {
            Text("Key 使用系统 Keychain 的仅本机、解锁时可访问级别保存，不写入 SwiftData、UserDefaults 或项目文件。")
        }
    }

    private var proxySection: some View {
        Section {
            TextField("http(s)://服务器:端口", text: $settings.proxyEndpointString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .proxyEndpoint)
                .accessibilityIdentifier("food-proxy-endpoint-field")

            if !settings.proxyEndpointString.isEmpty && settings.validatedProxyEndpoint == nil {
                Label("请输入有效的 HTTP 或 HTTPS 地址。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Button {
                Task { await testProxy() }
            } label: {
                Label("测试代理连接", systemImage: "network")
            }
            .disabled(settings.validatedProxyEndpoint == nil || operationState.isWorking)
        } header: {
            Text("自建代理")
        } footer: {
            Text("可以填写服务器根地址或完整的 /v1/food/analyze 地址；根地址会自动补全接口路径。App 不会把本机保存的阿里云 Key 发送给代理。")
        }
    }

    private var statusSection: some View {
        Section("连接状态") {
            switch operationState {
            case .idle:
                EmptyView()
            case .working(let message):
                HStack(spacing: 12) {
                    ProgressView()
                    Text(message)
                }
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandLeaf)
            case .failure(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func refreshCredentialStatus() async {
        do {
            hasStoredAPIKey = try await credentialStore.apiKey() != nil
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }

    private func saveAndTestAPIKey() async {
        focusedField = nil
        operationState = .working("正在保存并验证…")
        do {
            try await credentialStore.save(apiKey: apiKeyInput)
            apiKeyInput = ""
            hasStoredAPIKey = true
            settings.mode = .directQwen
            try await performQwenConnectionTest()
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }

    private func testStoredAPIKey() async {
        focusedField = nil
        operationState = .working("正在验证阿里云连接…")
        do {
            try await performQwenConnectionTest()
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }

    private func performQwenConnectionTest() async throws {
        guard let key = try await credentialStore.apiKey() else {
            throw FoodAnalysisError.missingCredential
        }
        let message = try await QwenFoodAnalysisService(apiKey: key).testConnection()
        operationState = .success(message)
    }

    private func deleteAPIKey() async {
        operationState = .working("正在删除…")
        do {
            try await credentialStore.deleteAPIKey()
            apiKeyInput = ""
            hasStoredAPIKey = false
            operationState = .success("已从本机钥匙串删除 API Key")
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }

    private func testProxy() async {
        focusedField = nil
        guard let endpoint = settings.validatedProxyEndpoint else {
            operationState = .failure("代理地址无效。")
            return
        }

        operationState = .working("正在检查代理健康状态…")
        do {
            guard let healthURL = FoodAnalysisProxyEndpoint.healthURL(from: endpoint) else {
                throw FoodAnalysisError.invalidEndpoint
            }
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 15
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw FoodAnalysisError.invalidResponse
            }
            operationState = .success("代理连接成功")
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }
}

private extension FoodAnalysisSettingsView {
    enum Field: Hashable {
        case apiKey
        case proxyEndpoint
    }

    enum OperationState: Equatable {
        case idle
        case working(String)
        case success(String)
        case failure(String)

        var isWorking: Bool {
            if case .working = self { true } else { false }
        }
    }
}

#Preview {
    NavigationStack {
        FoodAnalysisSettingsView(
            settings: FoodAnalysisSettings(mode: .directQwen),
            credentialStore: InMemoryFoodAnalysisCredentialStore()
        )
    }
}
