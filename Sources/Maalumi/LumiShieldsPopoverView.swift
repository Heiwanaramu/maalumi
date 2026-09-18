import SwiftUI
import MaalumiCore

// Notification sent by the Filter Lists and Global Settings buttons
// so ContentView can open the settings popover on the right page.
extension Notification.Name {
    static let openSettingsOnPage = Notification.Name("com.maalumi.openSettingsOnPage")
}

struct LumiShieldsPopoverView: View {
    let activeDomain: String

    @AppStorage("kShieldsAdBlockEnabled")         private var adBlockEnabled:    Bool = true
    @AppStorage("kBlockScripts")                   private var blockScripts:      Bool = true
    @AppStorage("kHTTPSOnlyMode")                  private var httpsOnlyMode:     Bool = true
    @AppStorage("kExperimentalCanvasProtection")   private var fingerprinting:    Bool = true
    @AppStorage("kSendDNT")                        private var sendDNT:           Bool = true

    @State private var showAdvanced = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(adBlockEnabled
                              ? Color.blue.opacity(0.12)
                              : Color.secondary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: adBlockEnabled ? "checkmark.shield.fill" : "shield.slash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(adBlockEnabled ? Color.blue : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeDomain.isEmpty ? "New Tab" : activeDomain)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(adBlockEnabled ? "LumiShields Active" : "LumiShields Off")
                        .font(.caption)
                        .foregroundStyle(adBlockEnabled ? Color.green : Color.secondary)
                }

                Spacer()

                Toggle("", isOn: $adBlockEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // ── Stats Row ─────────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "shield.checkerboard")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
                Text("Trackers & ads blocked on this page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Active")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(adBlockEnabled ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(adBlockEnabled
                                       ? Color.green.opacity(0.12)
                                       : Color.secondary.opacity(0.1))
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // ── Per-Site Toggles ──────────────────────────────────────────────
            VStack(spacing: 0) {
                shieldToggleRow(
                    icon:  "xmark.shield.fill",
                    color: .orange,
                    label: "Block Trackers & Ads",
                    binding: $adBlockEnabled
                )

                Divider().padding(.leading, 48)

                shieldToggleRow(
                    icon:  "curlybraces",
                    color: .purple,
                    label: "Block Scripts",
                    binding: $blockScripts,
                    disabled: !adBlockEnabled
                )

                Divider().padding(.leading, 48)

                shieldToggleRow(
                    icon:  "lock.fill",
                    color: .blue,
                    label: "HTTPS-Only Mode",
                    binding: $httpsOnlyMode
                )

                Divider().padding(.leading, 48)

                shieldToggleRow(
                    icon:  "eye.slash.fill",
                    color: .indigo,
                    label: "Block Fingerprinting",
                    binding: $fingerprinting
                )

                Divider().padding(.leading, 48)

                shieldToggleRow(
                    icon:  "hand.raised.fill",
                    color: .teal,
                    label: "Send 'Do Not Track'",
                    binding: $sendDNT
                )
            }
            .padding(.vertical, 4)

            Divider()

            // ── Footer Action Buttons ─────────────────────────────────────────
            HStack(spacing: 8) {
                // Filter Lists → opens Settings on the Filters page
                Button(action: {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .openSettingsOnPage,
                        object: "filters"
                    )
                }) {
                    Label("Filter Lists", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                // Global Settings → opens Settings on the Shields page
                Button(action: {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .openSettingsOnPage,
                        object: "shields"
                    )
                }) {
                    Label("All Settings", systemImage: "gearshape.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Row Helper

    @ViewBuilder
    private func shieldToggleRow(
        icon: String, color: Color, label: String,
        binding: Binding<Bool>, disabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(disabled ? .secondary : color)
                .frame(width: 28)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(disabled ? .secondary : .primary)

            Spacer()

            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(disabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
