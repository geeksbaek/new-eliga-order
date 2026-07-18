import SwiftUI

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var email = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 32) {
                        hero
                        loginCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 16 : 38)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .appScrollEdgeStyle()
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if email.isEmpty { email = store.userIDHint }
            }
            .sensoryFeedback(.error, trigger: errorMessage)
        }
    }

    private var hero: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 18) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(
                        width: dynamicTypeSize.isAccessibilitySize ? 64 : 88,
                        height: dynamicTypeSize.isAccessibilitySize ? 64 : 88
                    )
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 38 : 52, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.tint, Color(.systemBackground))
            }
            .appGlassSurface(cornerRadius: dynamicTypeSize.isAccessibilitySize ? 32 : 44)
            .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text("엘리가오더")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("login.brand")
                Text("식단과 카페 주문을 한곳에서")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

        }
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("로그인")
                    .font(.title2.bold())
                Text("엘리가 계정으로 안전하게 계속하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(2)
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "at")
                        .foregroundStyle(focusedField == .email ? Color.accentColor : Color.secondary)
                        .frame(width: 24)
                    TextField("이메일", text: $email, prompt: Text("name@kakaocorp.com"))
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .accessibilityIdentifier("login.email")
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 52)

                HStack(spacing: 12) {
                    Image(systemName: "lock")
                        .foregroundStyle(focusedField == .password ? Color.accentColor : Color.secondary)
                        .frame(width: 24)
                    Group {
                        if showsPassword {
                            TextField("비밀번호", text: $password)
                        } else {
                            SecureField("비밀번호", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .privacySensitive()
                    .accessibilityIdentifier("login.password")

                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(showsPassword ? "비밀번호 숨기기" : "비밀번호 보기")
                }
                .frame(minHeight: 56)
                .padding(.leading, 16)
                .padding(.trailing, 6)
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.5)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("login.error")
                    .accessibilityAddTraits(.updatesFrequently)
            }

            AppPrimaryActionButton(
                title: store.authenticationState == .authenticating ? "로그인 중…" : "로그인",
                systemImage: "arrow.right",
                isWorking: store.authenticationState == .authenticating,
                action: submit
            )
            .disabled(store.authenticationState == .authenticating)
            .accessibilityHint(canSubmit ? "로그인합니다" : "이메일과 비밀번호를 먼저 입력하세요")
            .accessibilityIdentifier("login.submit")
        }
        .padding(22)
        .background(
            Color(.systemBackground).opacity(colorScheme == .dark ? 0.72 : 0.82),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .appGlassSurface(cornerRadius: 28)
    }

    private func submit() {
        guard store.authenticationState != .authenticating else { return }
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            focusedField = .email
            return
        }
        guard !password.isEmpty else {
            focusedField = .password
            return
        }
        focusedField = nil
        errorMessage = nil
        Task {
            do { try await store.login(userID: email, password: password) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }
}
