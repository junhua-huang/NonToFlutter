import SwiftUI

struct AuthView: View {
    enum Mode: String, CaseIterable { case login = "登录", register = "注册", reset = "找回密码" }
    @EnvironmentObject private var session: AppSession
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var code = ""
    @State private var error: String?
    @State private var message: String?
    @State private var busy = false
    @State private var sendingCode = false
    @State private var cooldown = 0
    @State private var accepted = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var purpose: String { mode == .register ? "register" : (mode == .reset ? "reset_password" : "login") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "sparkle").font(.system(size: 44, weight: .light)).foregroundStyle(Color.brand)
                        Text("南图").font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("发现世界的动态，遇见同频的人。").foregroundStyle(.secondary)
                    }.padding(.vertical, 24)
                    Picker("账号操作", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    VStack(spacing: 18) {
                        if mode == .register { TextField("用户名", text: $username).textContentType(.username) }
                        TextField("邮箱", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                        SecureField(mode == .reset ? "新密码（至少 8 位）" : "密码", text: $password).textContentType(mode == .login ? .password : .newPassword)
                        HStack {
                            TextField(mode == .login ? "验证码（如服务器要求）" : "6 位邮箱验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            Button(cooldown > 0 ? "\(cooldown) 秒" : "发送验证码") { Task { await sendOTP() } }
                                .disabled(sendingCode || cooldown > 0 || !email.contains("@") || busy)
                        }
                    }.textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    if mode == .register {
                        Toggle("我已阅读并同意用户协议和隐私政策", isOn: $accepted).font(.footnote)
                    }
                    HStack {
                        NavigationLink("用户协议") { PolicyView(kind: "terms") }
                        NavigationLink("隐私政策") { PolicyView(kind: "privacy") }
                    }.font(.footnote)
                    ErrorBanner(text: error)
                    if let message { Text(message).font(.subheadline).foregroundStyle(Color.brand) }
                    Button { Task { await submit() } } label: {
                        HStack { Spacer(); if busy { ProgressView().tint(.white) }; Text(mode == .reset ? "重设密码" : mode.rawValue); Spacer() }.padding(.vertical, 8)
                    }.buttonStyle(.glassProminent).controlSize(.large)
                        .disabled(busy || email.isEmpty || password.isEmpty || (mode == .register && (!accepted || username.isEmpty || code.isEmpty)) || (mode == .reset && code.isEmpty))
                }.padding(28).frame(maxWidth: 520)
            }.frame(maxWidth: .infinity).scrollDismissesKeyboard(.interactively)
                .onChange(of: mode) { _, _ in error = nil; message = nil; code = "" }
                .onReceive(timer) { _ in if cooldown > 0 { cooldown -= 1 } }
        }
    }
    private func sendOTP() async {
        sendingCode = true; error = nil; defer { sendingCode = false }
        do {
            _ = try await session.api.request("/auth/send-otp", method: "POST", body: .object(["email": .text(email.trimmingCharacters(in: .whitespaces)), "purpose": .text(purpose)]), authenticated: false)
            cooldown = 60; message = "验证码已发送，请查收邮箱。"
        } catch { self.error = error.localizedDescription }
    }
    private func submit() async {
        busy = true; error = nil; message = nil; defer { busy = false }
        do {
            if mode != .login && password.count < 8 { throw APIError(status: 0, message: "密码至少需要 8 位") }
            let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if mode == .reset {
                _ = try await session.api.request("/auth/reset-password", method: "POST", body: .object(["email": .text(address), "code": .text(code), "new_password": .text(password)]), authenticated: false)
                mode = .login; password = ""; message = "密码已重设，请使用新密码登录。"
            } else {
                try await session.authenticate(email: address, password: password, code: code,
                                               username: mode == .register ? username.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
            }
        } catch { self.error = error.localizedDescription }
    }
}
