import SwiftUI

struct PersistenceRecoveryView: View {
    @Bindable var state: PersistenceState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ContentUnavailableView {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundStyle(KonomiTheme.persimmon)
                            .accessibilityHidden(true)
                        Text("Konomi Couldn't Open Your Library")
                            .font(.title2.bold())
                    }
                } description: {
                    Text("Your on-device data has not been deleted. Try again. If the problem continues, keep Konomi installed so the library remains available for recovery.")
                } actions: {
                    Button {
                        Task { await state.retry() }
                    } label: {
                        if state.isRetrying {
                            ProgressView()
                                .tint(KonomiTheme.onPersimmon)
                                .accessibilityLabel("Trying Again")
                        } else {
                            Text("Try Again")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KonomiTheme.persimmon)
                    .disabled(state.isRetrying)
                }

                DisclosureGroup("Technical Details") {
                    Text(state.failureDetails)
                        .font(.footnote.monospaced())
                        .foregroundStyle(KonomiTheme.inkSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding(16)
                .background(KonomiTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius)
                        .stroke(KonomiTheme.hairline, lineWidth: 1)
                }
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(KonomiTheme.canvas)
    }
}
