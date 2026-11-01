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
    @State private var availableModels: [String] = []
    @State private var showsModelPicker = false
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section {
                Picker("识别方式", selection: $settings.mode) {
                    ForEach(FoodAnalysisConnectionMode.selectableCases) { mode in
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
            case .directAPI:
                apiEndpointSection
                apiKeySection
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
                Label("自定义 API 的调用费用由所填写 Key 对应的服务商账户承担。", systemImage: "creditcard")
                Label("营养结果是模型估算，不代替医疗或用药建议。", systemImage: "cross.case")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("AI 食物识别")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        // 切换服务商时重新读取该服务商的 Key 状态，并清空上一家的输入与结果
        .task(id: settings.apiProvider) {
            apiKeyInput = ""
            availableModels = []
            operationState = .idle
            await refreshCredentialStatus()
        }
        .onDisappear { apiKeyInput = "" }
        .sheet(isPresented: $showsModelPicker) {
            ModelPickerSheet(models: availableModels, selection: $settings.apiModel)
        }
        .alert("删除 API Key？", isPresented: $confirmsKeyDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteAPIKey() }
            }
        } message: {
            Text("将从本机钥匙串删除 \(settings.apiProvider.title) 的 Key，之后使用需要重新填写。")
        }
    }

    private var demoSection: some View {
        Section("演示模式") {
            Label("使用本地固定结果，不上传照片。", systemImage: "iphone")
                .foregroundStyle(.secondary)
        }
    }

    private var apiEndpointSection: some View {
        Section {
            Picker("服务商", selection: $settings.apiProvider) {
                ForEach(FoodAnalysisAPIProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API 地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/v1", text: $settings.apiBaseURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .baseURL)
                    .accessibilityIdentifier("api-base-url-field")
                if !settings.apiBaseURL.isEmpty && !settings.isAPIBaseURLValid {
                    Text("地址需以 https:// 开头")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("模型名称", text: $settings.apiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .model)
                        .accessibilityIdentifier("api-model-field")

                    Button("选择模型", systemImage: "list.bullet") {
                        Task { await loadModels() }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!hasStoredAPIKey || !settings.isAPIBaseURLValid || operationState.isWorking)
                    .accessibilityHint("从服务商获取可用模型列表")
                }
            }

            if settings.apiProvider != .custom && !settings.isUsingProviderDefaults {
                Button("恢复预设地址和模型") {
                    settings.restoreProviderDefaults()
                }
            }
        } header: {
            Text("服务商与模型")
        } footer: {
            Text("支持 OpenAI Chat Completions 兼容接口，地址填写到 /v1 一级即可。请选择支持图片输入的视觉模型；保存 Key 后可点列表按钮从服务商获取模型。")
        }
    }

    private var apiKeySection: some View {
        Section {
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
                .accessibilityIdentifier("api-key-field")

            Button {
                Task { await saveAndTestAPIKey() }
            } label: {
                Label("保存并测试连接", systemImage: "checkmark.shield")
            }
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || operationState.isWorking)
            .accessibilityIdentifier("save-test-api-key")

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
            Text("\(settings.apiProvider.title) API Key")
        } footer: {
            Text("每个服务商的 Key 分别使用系统 Keychain 的仅本机、解锁时可访问级别保存，不写入 SwiftData、UserDefaults 或项目文件。连接测试会发送一张纯色小图，确认模型能识别图片。")
        }
    }

    private var proxySection: some View {
        Section {
            LabeledContent("代理服务器", value: FoodAnalysisSettings.proxyServerAddress)

            Button {
                Task { await testProxy() }
            } label: {
                Label("测试代理连接", systemImage: "network")
            }
            .disabled(operationState.isWorking)
        } header: {
            Text("自建代理")
        } footer: {
            Text("代理地址已由 App 预置。App 不会把本机保存的任何 API Key 发送给代理。")
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
            hasStoredAPIKey = try await credentialStore.apiKey(for: settings.apiProvider) != nil
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }

    private func saveAndTestAPIKey() async {
        focusedField = nil
        operationState = .working("正在保存并验证…")
        do {
            try await credentialStore.save(apiKey: apiKeyInput, for: settings.apiProvider)
            apiKeyInput = ""
            hasStoredAPIKey = true
            settings.mode = .directAPI
            try await performConnectionTest()
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }

    private func testStoredAPIKey() async {
        focusedField = nil
        operationState = .working("正在验证 \(settings.apiProvider.title) 连接…")
        do {
            try await performConnectionTest()
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }

    private func performConnectionTest() async throws {
        guard let configuration = settings.directAPIConfiguration else {
            throw FoodAnalysisError.incompleteConfiguration
        }
        guard let key = try await credentialStore.apiKey(for: configuration.provider) else {
            throw FoodAnalysisError.missingCredential
        }
        let message = try await OpenAICompatibleFoodAnalysisService(
            apiKey: key,
            configuration: configuration
        ).testConnection()
        operationState = .success(message)
    }

    private func loadModels() async {
        focusedField = nil
        operationState = .working("正在获取模型列表…")
        do {
            guard let baseURL = OpenAICompatibleConfiguration.normalizedBaseURL(
                from: settings.apiBaseURL
            ) else {
                throw FoodAnalysisError.incompleteConfiguration
            }
            guard let key = try await credentialStore.apiKey(for: settings.apiProvider) else {
                throw FoodAnalysisError.missingCredential
            }
            let models = try await OpenAICompatibleFoodAnalysisService.availableModels(
                apiKey: key,
                baseURL: baseURL
            )
            guard !models.isEmpty else {
                operationState = .failure("服务商没有返回可用模型，请手动填写模型名称。")
                return
            }
            availableModels = models
            operationState = .idle
            showsModelPicker = true
        } catch {
            operationState = .failure("无法获取模型列表：\(error.localizedDescription) 可以手动填写模型名称。")
        }
    }

    private func deleteAPIKey() async {
        operationState = .working("正在删除…")
        do {
            try await credentialStore.deleteAPIKey(for: settings.apiProvider)
            apiKeyInput = ""
            hasStoredAPIKey = false
            operationState = .success("已从本机钥匙串删除 API Key")
        } catch {
            operationState = .failure(error.localizedDescription)
        }
    }

    private func testProxy() async {
        focusedField = nil
        let endpoint = FoodAnalysisSettings.proxyEndpoint

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
        case baseURL
        case model
        case apiKey
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

/// 从服务商返回的模型列表中选择；列表可能很长，提供搜索
private struct ModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let models: [String]
    @Binding var selection: String
    @State private var searchText = ""

    private var filteredModels: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filteredModels, id: \.self) { model in
                Button {
                    selection = model
                    dismiss()
                } label: {
                    HStack {
                        Text(model)
                            .foregroundStyle(.primary)
                        Spacer()
                        if model == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索模型")
            .overlay {
                if filteredModels.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FoodAnalysisSettingsView(
            settings: FoodAnalysisSettings(mode: .directAPI),
            credentialStore: InMemoryFoodAnalysisCredentialStore()
        )
    }
}
