import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL

    private let githubLink = URL(string: "https://github.com/ghostty-org/ghostty")

    /// Read the commit from the bundle.
    private var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }
    private var commit: String? { Bundle.main.infoDictionary?["GhosttyCommit"] as? String }
    private var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    private var copyright: String? { Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String }

    private var properties: [KeyValue<String>] {
        let list: [KeyValue<String?>] = [
            .init(key: "Version", value: version),
            .init(key: "Build", value: build),
            .init(key: "Commit", value: commit == "" ? nil : commit)
        ]

        return list.compactMap {
            guard let value = $0.value else { return nil }
            return .init(key: $0.key, value: value)
        }
    }

    private struct KeyValue<Value: Equatable>: Identifiable {
        var id = UUID()
        public let key: LocalizedStringResource
        public let value: Value
    }

    #if os(macOS)
    // This creates a background style similar to the Apple "About My Mac" Window
    private struct VisualEffectBackground: NSViewRepresentable {
        let material: NSVisualEffectView.Material
        let blendingMode: NSVisualEffectView.BlendingMode
        let isEmphasized: Bool

        init(material: NSVisualEffectView.Material,
             blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
             isEmphasized: Bool = false)
        {
            self.material = material
            self.blendingMode = blendingMode
            self.isEmphasized = isEmphasized
        }

        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
            nsView.material = material
            nsView.blendingMode = blendingMode
            nsView.isEmphasized = isEmphasized
        }

        func makeNSView(context: Context) -> NSVisualEffectView {
            let visualEffect = NSVisualEffectView()
            visualEffect.autoresizingMask = [.width, .height]
            return visualEffect
        }
    }
    #endif

    var body: some View {
        VStack(alignment: .center) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 128)

            VStack(alignment: .center, spacing: 32) {
                VStack(alignment: .center, spacing: 8) {
                    Text("Ghostty")
                        .bold()
                        .font(.title)
                    Text("Fast, native, feature-rich terminal \nemulator pushing modern features.")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.caption)
                        .tint(.secondary)
                        .opacity(0.8)
                }
                .textSelection(.enabled)
                VStack(spacing: 2) {
                    ForEach(properties) { item in
                        HStack(spacing: 4) {
                                Text(item.key)
                                    .frame(width: 126, alignment: .trailing)
                                    .padding(.trailing, 2)
                                Text(item.value)
                                    .frame(width: 125, alignment: .leading)
                                    .padding(.leading, 2)
                                    .tint(.secondary)
                                    .opacity(0.8)
                        }
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    if let url = githubLink {
                        Button("GitHub") {
                            openURL(url)
                        }
                    }

                }

                if let copy = self.copyright {
                    Text(copy)
                        .font(.caption)
                        .textSelection(.enabled)
                        .tint(.secondary)
                        .opacity(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .padding(32)
        .frame(minWidth: 256)
        #if os(macOS)
        .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
        #endif
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
