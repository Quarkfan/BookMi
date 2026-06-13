import SwiftUI
import CryptoKit

struct AIOCRSettingsView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var isEnabled = false
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var timeout = "60"
    @State private var maxTokens = "2000"
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var showAPIKey = false
    var body: some View {
        Form {
            Section {
                Toggle("启用 AI/OCR", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        appContainer.settings.isAICapabilityEnabled = newValue
                    }

                TextField("API Base URL", text: $baseURL)
                    .onChange(of: baseURL) { _, newValue in
                        appContainer.settings.aiBaseURL = newValue.nilIfEmpty
                    }

                HStack {
                    if showAPIKey {
                        TextField("API Key", text: $apiKey)
                    } else {
                        SecureField("API Key", text: $apiKey)
                    }
                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: apiKey) { _, newValue in
                    if newValue.isEmpty {
                        appContainer.keychain.deleteLLMAPIKey()
                    } else {
                        _ = appContainer.keychain.setLLMAPIKey(newValue)
                    }
                }

                TextField("Model Name", text: $modelName)
                    .onChange(of: modelName) { _, newValue in
                        appContainer.settings.aiModelName = newValue.nilIfEmpty
                    }
            }

            Section("高级设置") {
                TextField("超时（秒）", text: $timeout)
                    .keyboardType(.numberPad)
                    .onChange(of: timeout) { _, newValue in
                        if let v = Int(newValue) {
                            appContainer.settings.aiTimeout = v
                        }
                    }

                TextField("最大 Token", text: $maxTokens)
                    .keyboardType(.numberPad)
                    .onChange(of: maxTokens) { _, newValue in
                        if let v = Int(newValue) {
                            appContainer.settings.aiMaxTokens = v
                        }
                    }
            }

            Section("测试") {
                Button(isTesting ? "测试中..." : "测试连接") {
                    testConnection()
                }
                .disabled(isEnabled && baseURL.isEmpty)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("成功") ? .green : .red)
                }
            }

            Section("当前配置") {
                HStack {
                    Text("已启用")
                    Spacer()
                    Text(isEnabled ? "是" : "否")
                        .foregroundStyle(.secondary)
                }
                if !baseURL.isEmpty {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        Text(baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !modelName.isEmpty {
                    HStack {
                        Text("模型")
                        Spacer()
                        Text(modelName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("AI / OCR 设置")
        .task {
            await loadSettings()
        }
    }

    private func loadSettings() async {
        isEnabled = appContainer.settings.isAICapabilityEnabled
        baseURL = appContainer.settings.aiBaseURL ?? ""
        modelName = appContainer.settings.aiModelName ?? ""
        timeout = String(appContainer.settings.aiTimeout)
        maxTokens = String(appContainer.settings.aiMaxTokens)
        if let key = appContainer.keychain.getLLMAPIKey() {
            apiKey = key
        }
    }

    private func testConnection() {
        guard !baseURL.isEmpty else {
            testResult = "请先配置 API Base URL"
            return
        }
        guard !apiKey.isEmpty else {
            testResult = "请先配置 API Key"
            return
        }

        isTesting = true
        Task {
            do {
                let url = URL(string: "\(baseURL)/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                let body: [String: Any] = [
                    "model": modelName.isEmpty ? "qwen-turbo" : modelName,
                    "messages": [
                        ["role": "user", "content": "Say 'hello'"]
                    ],
                    "max_tokens": 10
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if httpResponse.statusCode == 200 {
                    await MainActor.run {
                        isTesting = false
                        testResult = "成功！API 连接正常"
                    }
                } else {
                    let body = String(data: data, encoding: .utf8) ?? "No body"
                    await MainActor.run {
                        isTesting = false
                        testResult = "失败 (HTTP \(httpResponse.statusCode)): \(body.prefix(100))"
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = "连接失败: \(error.localizedDescription)"
                }
            }
        }
    }

}
