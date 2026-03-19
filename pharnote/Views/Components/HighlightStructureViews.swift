import SwiftUI

struct HighlightStructurePaletteView: View {
    @Binding var mode: HighlightStructureMode
    @Binding var selectedRole: HighlightStructureRole
    let colorBinding: (HighlightStructureRole) -> Binding<Color>

    var body: some View {
        WritingChromeCapsule(fill: WritingChromePalette.paletteFill) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(HighlightStructureMode.allCases, id: \.self) { candidate in
                        modeButton(for: candidate)
                    }

                    Spacer(minLength: 0)

                    Text(mode.subtitle)
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                }

                if mode == .structured {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach(HighlightStructureRole.allCases, id: \.self) { role in
                                roleChip(for: role)
                            }
                        }

                        HStack(spacing: 10) {
                            Text("현재 역할 색상")
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                            ColorPicker("", selection: colorBinding(selectedRole))
                                .labelsHidden()
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(PharTheme.ColorToken.border.opacity(0.5), lineWidth: 1)
                                )

                            Text(selectedRole.subtitle)
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.subtleText)
                        }
                    }
                } else {
                    Text("기본 모드는 가볍게 표시만 합니다. 구조가 필요할 때만 구조화 모드로 전환하세요.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func modeButton(for candidate: HighlightStructureMode) -> some View {
        Button {
            mode = candidate
        } label: {
            HStack(spacing: 6) {
                Image(systemName: candidate == .basic ? "highlighter" : "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(candidate.title)
                    .font(PharTypography.captionStrong)
            }
            .foregroundStyle(candidate == mode ? Color.white : PharTheme.ColorToken.inkPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(candidate == mode ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.surfaceSecondary)
            )
        }
        .buttonStyle(.plain)
    }

    private func roleChip(for role: HighlightStructureRole) -> some View {
        Button {
            selectedRole = role
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(colorBinding(role).wrappedValue)
                    .frame(width: 9, height: 9)
                Text(role.title)
                    .font(PharTypography.captionStrong)
            }
            .foregroundStyle(selectedRole == role ? Color.white : PharTheme.ColorToken.inkPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(selectedRole == role ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.surfaceSecondary)
            )
        }
        .buttonStyle(.plain)
    }
}

struct HighlightStructureSidebarView: View {
    let snapshot: HighlightStructureSnapshot?
    var onSelectRole: ((HighlightStructureRole) -> Void)? = nil

    @State private var expandedRoles: Set<HighlightStructureRole> = [.core]

    var body: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.94)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                header

                if let snapshot {
                    roleSummaryRow(snapshot: snapshot)
                    summaryCard(snapshot: snapshot)
                    roleOutlineList(snapshot: snapshot)
                } else {
                    emptyState
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("구조 하이라이트")
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                Text("하이라이트를 역할로 묶어 바로 다시 읽을 수 있게 정리합니다.")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }

            Spacer(minLength: 0)

            if let snapshot {
                PharTagPill(
                    text: "\(snapshot.totalCount)개",
                    tint: PharTheme.ColorToken.accentBlue.opacity(0.14),
                    foreground: PharTheme.ColorToken.accentBlue
                )
            }
        }
    }

    private func roleSummaryRow(snapshot: HighlightStructureSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PharTheme.Spacing.xSmall) {
                ForEach(snapshot.roleSummaries) { summary in
                    Button {
                        onSelectRole?(summary.role)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: summary.colorHex) ?? Color.gray)
                                .frame(width: 8, height: 8)
                            Text("\(summary.role.title) \(summary.count)")
                                .font(PharTypography.captionStrong)
                        }
                        .foregroundStyle(summary.count > 0 ? PharTheme.ColorToken.inkPrimary : PharTheme.ColorToken.subtleText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(PharTheme.ColorToken.surfaceSecondary)
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(summary.count > 0 ? 1 : 0.55)
                }
            }
            .padding(.vertical, PharTheme.Spacing.xxxSmall)
        }
    }

    private func summaryCard(snapshot: HighlightStructureSnapshot) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
            HStack {
                Text("시험 직전 요약")
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                Spacer(minLength: 0)
                Text(snapshot.summaryLine)
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
                    .lineLimit(1)
            }

            if snapshot.summaryBullets.isEmpty {
                Text("하이라이트를 더 쌓으면 자동 요약이 나타납니다.")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(snapshot.summaryBullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(PharTheme.ColorToken.accentBlue)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(bullet)
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(PharTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .fill(PharTheme.ColorToken.surfaceSecondary)
        )
    }

    private func roleOutlineList(snapshot: HighlightStructureSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("자동 아웃라인")
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)

            if snapshot.outlineEntries.isEmpty {
                Text("역할을 지정한 하이라이트가 쌓이면 계층이 보입니다.")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.outlineEntries) { entry in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedRoles.contains(entry.role) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedRoles.insert(entry.role)
                                    } else {
                                        expandedRoles.remove(entry.role)
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let previewText = entry.previewText, !previewText.isEmpty {
                                    Text(previewText)
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                                        .lineLimit(2)
                                }
                                Text(entry.subtitle)
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.subtleText)
                            }
                            .padding(.top, 4)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                Circle()
                                    .fill(Color(hex: entry.colorHex) ?? Color.gray)
                                    .frame(width: 10, height: 10)
                                Text(entry.title)
                                    .font(PharTypography.captionStrong)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                Spacer(minLength: 0)
                                PharTagPill(
                                    text: "\(entry.count)",
                                    tint: PharTheme.ColorToken.surfaceSecondary,
                                    foreground: PharTheme.ColorToken.inkPrimary
                                )
                            }
                            .padding(.vertical, 4)
                            .padding(.leading, CGFloat(entry.depth) * 10)
                        }
                        .onTapGesture {
                            onSelectRole?(entry.role)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("구조화 하이라이트가 아직 없습니다.")
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
            Text("형광펜을 구조화 모드로 바꾸고 핵심, 근거, 예시, 질문을 표시해 보세요.")
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.subtleText)
        }
        .padding(.vertical, 4)
    }
}
