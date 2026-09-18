import SwiftUI
import MaalumiCore

struct SiteSettingsPopoverView: View {
    let domain: String

    @AppStorage("kUseReaderWhenAvailable") private var useReader: Bool = false
    @AppStorage("kShieldsAdBlockEnabled") private var enableContentBlockers: Bool = true
    
    @State private var pageZoom: String = "100%"
    @State private var autoPlay: String = "Stop Media with Sound"
    @State private var popups: String = "Block and Notify"
    
    @State private var cameraPermission: String = "Ask"
    @State private var micPermission: String = "Ask"
    @State private var screenSharingPermission: String = "Ask"
    @State private var locationPermission: String = "Ask"

    var displayDomain: String {
        domain.isEmpty ? "this website" : domain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("When visiting \(displayDomain):")
                .font(.headline)
                .lineLimit(1)
                .padding(.bottom, 2)
            
            // Top Toggles
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use Reader when available", isOn: $useReader)
                Toggle("Enable content blockers", isOn: $enableContentBlockers)
            }
            .controlSize(.regular)
            
            Divider()
            
            // Page Preferences Pickers
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Page Zoom:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $pageZoom) {
                        Text("75%").tag("75%")
                        Text("100%").tag("100%")
                        Text("115%").tag("115%")
                        Text("125%").tag("125%")
                        Text("150%").tag("150%")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                
                GridRow {
                    Text("Auto-Play:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $autoPlay) {
                        Text("Stop Media with Sound").tag("Stop Media with Sound")
                        Text("Allow All Auto-Play").tag("Allow All Auto-Play")
                        Text("Never Auto-Play").tag("Never Auto-Play")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                
                GridRow {
                    Text("Pop-up Windows:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $popups) {
                        Text("Block and Notify").tag("Block and Notify")
                        Text("Block").tag("Block")
                        Text("Allow").tag("Allow")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            // Hardware Permissions Pickers
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Camera:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $cameraPermission) {
                        Text("Ask").tag("Ask")
                        Text("Deny").tag("Deny")
                        Text("Allow").tag("Allow")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                
                GridRow {
                    Text("Microphone:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $micPermission) {
                        Text("Ask").tag("Ask")
                        Text("Deny").tag("Deny")
                        Text("Allow").tag("Allow")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                
                GridRow {
                    Text("Screen Sharing:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $screenSharingPermission) {
                        Text("Ask").tag("Ask")
                        Text("Deny").tag("Deny")
                        Text("Allow").tag("Allow")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                
                GridRow {
                    Text("Location:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $locationPermission) {
                        Text("Ask").tag("Ask")
                        Text("Deny").tag("Deny")
                        Text("Allow").tag("Allow")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
