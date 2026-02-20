import SwiftUI

struct LoginView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.house.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)

            Text("Welcome to Swifotine")
                .font(.title)
                .bold()

            VStack(spacing: 12) {
                TextField("Soulseek Username", text: $username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 300)

            if let error = sessionStore.lastError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button("Connect") {
                Task {
                    await sessionStore.connect(username: username, passcode: password)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || sessionStore.connectionState == .connecting)

            if sessionStore.connectionState == .connecting {
                ProgressView()
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
