import SwiftUI
import LocalAuthentication
import CryptoKit

struct PasscodeView: View {
    let onAuthenticated: () -> Void
    @EnvironmentObject var appContainer: AppContainer

    @State private var passcode = ""
    @State private var showingBiometric = false
    @State private var errorMessage = ""

    var body: some View {
        VStack {
            Spacer()

            Image(systemName: "lock.shield")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.accentColor)

            Text("输入密码")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }

            // Passcode input dots
            HStack(spacing: 12) {
                ForEach(0..<6) { i in
                    Circle()
                        .fill(i < passcode.count ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.top)

            // Number pad
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                ForEach(1...9, id: \.self) { num in
                    Button("\(num)") {
                        appendDigit("\(num)")
                    }
                    .buttonStyle(NumberButtonStyle())
                }

                Button {
                    showBiometricAuth()
                } label: {
                    Image(systemName: "faceid")
                }
                .buttonStyle(NumberButtonStyle())
                .opacity(appContainer.settings.isBiometricEnabled ? 1 : 0.3)

                Button("0") {
                    appendDigit("0")
                }
                .buttonStyle(NumberButtonStyle())

                Button {
                    deleteDigit()
                } label: {
                    Image(systemName: "delete.left")
                }
                .buttonStyle(NumberButtonStyle())
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    private func appendDigit(_ digit: String) {
        guard passcode.count < 6 else { return }
        passcode += digit

        if passcode.count == 6 {
            verifyPasscode()
        }
    }

    private func deleteDigit() {
        guard !passcode.isEmpty else { return }
        passcode.removeLast()
        errorMessage = ""
    }

    private func verifyPasscode() {
        guard let storedHash = appContainer.keychain.getPasscodeHash() else {
            // No passcode set yet - this shouldn't happen if passcode is enabled
            onAuthenticated()
            return
        }

        let inputHash = hashPasscode(passcode)
        if inputHash == storedHash {
            onAuthenticated()
        } else {
            errorMessage = "密码错误"
            passcode = ""
        }
    }

    private func showBiometricAuth() {
        guard appContainer.settings.isBiometricEnabled else { return }

        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "解锁 BookRoom") { success, _ in
                if success {
                    DispatchQueue.main.async {
                        onAuthenticated()
                    }
                }
            }
        }
    }

    private func hashPasscode(_ passcode: String) -> String {
        let data = Data(passcode.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

struct NumberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2)
            .fontWeight(.medium)
            .frame(width: 70, height: 70)
            .background(configuration.isPressed ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
            .clipShape(Circle())
    }
}

#Preview {
    PasscodeView(onAuthenticated: {})
        .environmentObject(AppContainer.shared)
}
