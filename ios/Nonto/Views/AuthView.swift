import SwiftUI

struct AuthView: View {
    @Environment(\.appAccent) private var accent
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
    @State private var showsLoginCode = false
    @FocusState private var focusedField: Field?
    private enum Field { case username, email, password, code }
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
                    Picker("账号操作", selection: Binding(get: { mode }, set: {
                        mode = $0; error = nil; message = nil; code = ""; showsLoginCode = false; focusedField = nil
                    })) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).disabled(busy || sendingCode)
                    VStack(alignment: .leading, spacing: 16) {
                        if mode == .register {
                            field("用户名") {
                                TextField("设置用户名", text: $username).textContentType(.username)
                                    .focused($focusedField, equals: .username).submitLabel(.next)
                                    .onSubmit { focusedField = .email }
                            }
                        }
                        field("邮箱") {
                            TextField("输入邮箱地址", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                                .focused($focusedField, equals: .email).submitLabel(.next)
                                .onSubmit { focusedField = .password }
                        }
                        field(mode == .reset ? "新密码" : "密码") {
                            SecureField(mode == .login ? "输入密码" : "至少 8 位", text: $password)
                                .textContentType(mode == .login ? .password : .newPassword)
                                .focused($focusedField, equals: .password)
                                .submitLabel(mode == .login && !showsLoginCode ? .go : .next)
                                .onSubmit {
                                    if mode == .login && !showsLoginCode {
                                        if canSubmit { Task { await submit() } }
                                    } else { focusedField = .code }
                                }
                        }
                        if mode == .login {
                            DisclosureGroup("需要邮箱验证码？", isExpanded: $showsLoginCode) {
                                verificationField.padding(.top, 10)
                            }.font(.subheadline)
                        } else { verificationField }
                    }.textInputAutocapitalization(.never).autocorrectionDisabled().disabled(busy || sendingCode)
                    if mode == .register {
                        Toggle("我已阅读并同意用户协议和隐私政策", isOn: $accepted).font(.footnote)
                    }
                    HStack {
                        NavigationLink("服务条款") { PolicyView(kind: "terms") }
                        NavigationLink("隐私政策") { PolicyView(kind: "privacy") }
                    }.font(.footnote)
                    ErrorBanner(text: error)
                    if let message { Text(message).font(.subheadline).foregroundStyle(accent.textColor) }
                    Button { Task { await submit() } } label: {
                        HStack(spacing: 8) { if busy { ProgressView().tint(accent.foregroundColor) }; Text(mode == .reset ? "重设密码" : mode.rawValue) }
                            .frame(maxWidth: .infinity, minHeight: 24).foregroundStyle(accent.foregroundColor)
                    }.buttonStyle(.glassProminent).controlSize(.large)
                        .disabled(!canSubmit)
                }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 440)
            }.frame(maxWidth: .infinity).scrollDismissesKeyboard(.interactively)
                .onAppear {
                    if let notice = session.authenticationMessage { message = notice; session.authenticationMessage = nil }
                }
                .onReceive(timer) { _ in if cooldown > 0 { cooldown -= 1 } }
        }
    }
    private var canSubmit: Bool {
        !busy && !sendingCode && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
            && (mode != .register || (accepted && !username.isEmpty && !code.isEmpty))
            && (mode != .reset || !code.isEmpty)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            content().textFieldStyle(.plain).padding(.horizontal, 14).padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        }
    }
    private var verificationField: some View {
        HStack(alignment: .bottom, spacing: 12) {
            field("邮箱验证码") {
                TextField("6 位验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .code)
            }
            Button { Task { await sendOTP() } } label: {
                HStack(spacing: 4) {
                    if sendingCode { ProgressView() }
                    Text(cooldown > 0 ? "\(cooldown) 秒" : "发送验证码")
                }.font(.subheadline).frame(minHeight: 32)
            }.buttonStyle(.glass).controlSize(.regular).fixedSize(horizontal: true, vertical: false)
                .disabled(sendingCode || cooldown > 0 || !email.contains("@") || busy)
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
        guard canSubmit else { return }
        focusedField = nil
        busy = true; error = nil; message = nil; defer { busy = false }
        do {
            if mode != .login && password.count < 8 { throw APIError(status: 0, message: "密码至少需要 8 位") }
            let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if mode == .reset {
                _ = try await session.api.request("/auth/reset-password", method: "POST", body: .object(["email": .text(address), "code": .text(code), "new_password": .text(password)]), authenticated: false)
                mode = .login; password = ""; code = ""; message = "密码已重设，请使用新密码登录。"
            } else {
                try await session.authenticate(email: address, password: password, code: code,
                                               username: mode == .register ? username.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
            }
        } catch { self.error = error.localizedDescription }
    }
}
