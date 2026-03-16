import SwiftUI

struct PrivacyExplainerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy contract")
                .font(.title3.weight(.bold))
            Text("Local model inference is the default path. Live Search calls the backend only when the user enables it for a prompt or turns it on by default in Settings.")
                .foregroundStyle(AppTheme.textSecondary)
        }
        .glassCard()
    }
}
