import SwiftUI

struct SenseRowView: View {
    let hit: SenseHit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(termList(hit.sourceTerms))
                    .font(.headline)
                Spacer(minLength: 4)
                if !hit.domain.isEmpty {
                    Text(hit.domain.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
            }
            Text(termList(hit.targetTerms))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let ctx = hit.context, !ctx.isEmpty {
                Text(ctx)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func termList(_ terms: [TermDisplay]) -> String {
        terms.map(\.surface).joined(separator: "; ")
    }
}
