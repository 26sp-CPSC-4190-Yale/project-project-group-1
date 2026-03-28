//
//  SessionHistoryView.swift
//  Unplugged.Features.History
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct SessionHistoryView: View {
    @State private var viewModel = SessionHistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { index, session in
                HStack(spacing: .spacingMd) {
                    // Star circle icon
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.tertiaryColor.opacity(0.4))

                    // Title + date
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.tertiaryColor)
                            .lineLimit(1)

                        Text(session.date)
                            .font(.captionFont)
                            .foregroundColor(.tertiaryColor.opacity(0.4))
                    }

                    Spacer()

                    // Duration
                    Text(session.duration)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.tertiaryColor.opacity(0.7))

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.tertiaryColor.opacity(0.3))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, .spacingMd)

                // Divider (not after last item)
                if index < viewModel.sessions.count - 1 {
                    Divider()
                        .background(Color.tertiaryColor.opacity(0.1))
                        .padding(.leading, 56)
                }
            }
        }
    }
}

#Preview {
    SessionHistoryView()
        .padding()
        .background(Color.primaryColor)
}
