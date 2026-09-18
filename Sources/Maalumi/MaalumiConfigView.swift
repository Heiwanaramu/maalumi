import SwiftUI
import MaalumiCore

struct MaalumiConfigView: View {
    @AppStorage("defaultSearchEngine") private var defaultSearchEngine: String = "DuckDuckGo"
    @AppStorage("kShieldsAdBlockEnabled") private var adBlockEnabled: Bool = true
    @AppStorage("kBlockScripts") private var blockScripts: Bool = true
    @AppStorage("kHTTPSOnlyMode") private var httpsOnlyMode: Bool = true
    @AppStorage("kExperimentalCanvasProtection") private var canvasProtection: Bool = true
    @AppStorage("kExperimentalWebRTCBlock") private var webRTCBlock: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("m:config — Internal Engine Configuration")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        Text("Core Environment")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Engine Module:")
                                    .fontWeight(.medium)
                                Text("MaalumiCore (v1.0.0-macOS)")
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Target Platform:")
                                    .fontWeight(.medium)
                                Text("macOS 13.0+")
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Default Search Provider:")
                                    .fontWeight(.medium)
                                Text(defaultSearchEngine)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    Group {
                        Text("LumiShields Active Engine Policies")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: adBlockEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(adBlockEnabled ? .green : .red)
                                Text("Ad & Tracker Block Engine: \(adBlockEnabled ? "Active" : "Disabled")")
                            }
                            HStack {
                                Image(systemName: blockScripts ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(blockScripts ? .green : .red)
                                Text("Script Execution Filter: \(blockScripts ? "Active" : "Disabled")")
                            }
                            HStack {
                                Image(systemName: httpsOnlyMode ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(httpsOnlyMode ? .green : .red)
                                Text("HTTPS Upgrader Enforcement: \(httpsOnlyMode ? "Active" : "Disabled")")
                            }
                            HStack {
                                Image(systemName: canvasProtection ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(canvasProtection ? .green : .red)
                                Text("Canvas Fingerprinting Defenses: \(canvasProtection ? "Active" : "Disabled")")
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
