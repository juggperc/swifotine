import AppKit
import SwiftUI

struct AppLaunchView: View {
    @State private var showMainApp = false

    var body: some View {
        ZStack {
            if showMainApp {
                AppShell()
                    .transition(.opacity.combined(with: .scale(scale: 1.01)))
            } else {
                LaunchSplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showMainApp)
        .task {
            guard !showMainApp else { return }
            try? await Task.sleep(nanoseconds: 1_350_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                showMainApp = true
            }
        }
    }
}

private struct LaunchSplashView: View {
    @State private var floatOrbs = false
    @State private var pulseIcon = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.22),
                        Color(NSColor.windowBackgroundColor),
                        Color.accentColor.opacity(0.1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 360, height: 360)
                    .blur(radius: 24)
                    .offset(
                        x: floatOrbs ? -proxy.size.width * 0.18 : proxy.size.width * 0.12,
                        y: floatOrbs ? -110 : 90
                    )

                Circle()
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: 280, height: 280)
                    .blur(radius: 28)
                    .offset(
                        x: floatOrbs ? proxy.size.width * 0.16 : -proxy.size.width * 0.1,
                        y: floatOrbs ? 95 : -80
                    )

                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.regularMaterial)
                            .frame(width: 104, height: 104)

                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                    }
                    .scaleEffect(pulseIcon ? 1.03 : 0.98)
                    .shadow(color: Color.black.opacity(0.16), radius: 14, y: 8)

                    Text("Swifotine")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))

                    Text("Loading your library and network")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ProgressView()
                        .controlSize(.small)
                        .tint(.accentColor)
                }
                .padding(28)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                floatOrbs.toggle()
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulseIcon.toggle()
            }
        }
    }
}
