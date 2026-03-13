import SwiftUI

struct PastQuestionsDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PastQuestionsDebugViewModel()

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                lookupSection

                if let lookupResponse = viewModel.lookupResponse {
                    lookupResultSection(lookupResponse)
                }

                searchSection

                if let searchResponse = viewModel.searchResponse {
                    searchResultSection(searchResponse)
                }
            }
            .navigationTitle("기출 DB")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            viewModel.loadValidationPreset()
            viewModel.refreshConfigurationFields()
        }
        .alert("기출 DB 오류", isPresented: errorPresented) {
            Button("확인", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var connectionSection: some View {
        Section("연결 설정") {
            LabeledContent("Exact lookup", value: viewModel.isLookupConfigured ? "준비됨" : "미설정")
            LabeledContent("Search", value: viewModel.isSearchConfigured ? "준비됨" : "미설정")
            LabeledContent("소스", value: viewModel.configurationSourceLabel)
            LabeledContent("현재 키", value: viewModel.maskedAnonKey)

            TextField("PAST_QUESTIONS_API_BASE_URL", text: $viewModel.apiBaseURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            TextField("PAST_QUESTIONS_SUPABASE_URL", text: $viewModel.baseURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            TextField("PAST_QUESTIONS_SUPABASE_ANON_KEY", text: $viewModel.anonKey, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(3 ... 6)

            HStack {
                Button("새로고침") {
                    viewModel.refreshConfigurationFields()
                }
                Spacer()
                Button("저장") {
                    viewModel.saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Exact lookup은 TutorHub API base URL을, search는 Supabase URL + anon key를 사용합니다. iOS 앱은 `.env`를 자동 로드하지 않습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !viewModel.isLookupConfigured {
                Text("TutorHub API base URL을 저장해야 exact lookup 버튼이 활성화됩니다.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !viewModel.isSearchConfigured {
                Text("추천 검색까지 쓰려면 Supabase URL과 anon key도 함께 저장해야 합니다.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var lookupSection: some View {
        Section("Exact Lookup") {
            TextField("과목", text: $viewModel.lookupSubject)

            HStack {
                TextField("연도", text: $viewModel.lookupYearText)
                    .keyboardType(.numberPad)
                TextField("월", text: $viewModel.lookupMonthText)
                    .keyboardType(.numberPad)
                TextField("문항", text: $viewModel.lookupQuestionNumberText)
                    .keyboardType(.numberPad)
            }

            TextField("exam_type (예: 9월 모의평가)", text: $viewModel.lookupExamType)
            TextField("exam_variant (예: 공통, 미적분, 기하, 가형)", text: $viewModel.lookupExamVariant)
            Toggle("image_url 필수", isOn: $viewModel.lookupRequireImage)
            TextField("require_points (예: 4)", text: $viewModel.lookupRequirePointsText)
                .keyboardType(.numberPad)

            HStack {
                Button("2026 9월 22 프리셋") {
                    viewModel.loadValidationPreset()
                }
                Spacer()
                Button {
                    Task {
                        await viewModel.runLookup()
                    }
                } label: {
                    if viewModel.isRunningLookup {
                        ProgressView()
                    } else {
                        Text("조회")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunningLookup || !viewModel.isLookupConfigured)
            }
        }
    }

    @ViewBuilder
    private func lookupResultSection(_ response: PastQuestionLookupResponse) -> some View {
        Section("Lookup 결과") {
            if let match = response.match {
                PastQuestionResultCard(
                    record: match,
                    snippet: match.contentPreview,
                    score: nil,
                    matchedTokens: []
                )
            } else {
                Text(response.message ?? "결과가 없습니다.")
                    .foregroundStyle(.secondary)
            }

            if response.candidates.count > 1 {
                Text("후보 \(response.candidates.count)건")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(Array(response.candidates.dropFirst().prefix(3))) { candidate in
                    PastQuestionResultCard(
                        record: candidate,
                        snippet: candidate.contentPreview,
                        score: nil,
                        matchedTokens: []
                    )
                }
            }
        }
    }

    private var searchSection: some View {
        Section("Search") {
            TextField("검색어", text: $viewModel.searchQuery, axis: .vertical)
                .lineLimit(2 ... 4)

            HStack {
                TextField("과목 힌트", text: $viewModel.searchSubjectHint)
                TextField("topK", text: $viewModel.searchTopKText)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 80)
            }

            Button {
                Task {
                    await viewModel.runSearch()
                }
            } label: {
                if viewModel.isRunningSearch {
                    ProgressView()
                } else {
                    Text("검색")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRunningSearch || !viewModel.isSearchConfigured)
        }
    }

    @ViewBuilder
    private func searchResultSection(_ response: PastQuestionSearchResponse) -> some View {
        Section("Search 결과") {
            Text("후보 \(response.totalCandidates)건 중 \(response.items.count)건 반환")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if response.items.isEmpty {
                Text("검색 결과가 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(response.items) { hit in
                    PastQuestionResultCard(
                        record: hit.record,
                        snippet: hit.snippet,
                        score: hit.score,
                        matchedTokens: hit.matchedTokens
                    )
                }
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { shouldShow in
                if !shouldShow {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

private struct PastQuestionResultCard: View {
    let record: PastQuestionRecord
    let snippet: String
    let score: Int?
    let matchedTokens: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recordTitle)
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            PastQuestionBadge(text: record.subject, tint: .blue)
                            if let variant = record.examVariant {
                                PastQuestionBadge(text: variant, tint: .green)
                            }
                            if let paperSection = record.paperSection {
                                PastQuestionBadge(text: paperSection, tint: .mint)
                            }
                            if let points = record.points {
                                PastQuestionBadge(text: "\(points)점", tint: .pink)
                            }
                            if let difficulty = record.difficulty?.trimmingCharacters(in: .whitespacesAndNewlines), !difficulty.isEmpty {
                                PastQuestionBadge(text: difficulty, tint: .orange)
                            }
                            PastQuestionBadge(text: record.hasImage ? "image" : "no image", tint: record.hasImage ? .teal : .gray)
                            if let score {
                                PastQuestionBadge(text: "score \(score)", tint: .purple)
                            }
                        }
                    }
                }

                Spacer(minLength: 8)
            }

            if !matchedTokens.isEmpty {
                Text("matched: \(matchedTokens.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(snippet.isEmpty ? record.contentPreview : snippet)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let answer = record.answerPreview {
                LabeledContent("정답", value: answer)
                    .font(.subheadline)
            }

            if let unit = record.metadata.unit {
                LabeledContent("단원", value: unit)
                    .font(.footnote)
            }

            if !record.metadata.keywords.isEmpty {
                Text(record.metadata.keywords.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let imageURL = record.imageURL {
                VStack(alignment: .leading, spacing: 8) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                                ProgressView()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)

                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        case .failure:
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .overlay(
                                    Label("이미지를 불러오지 못했습니다.", systemImage: "exclamationmark.triangle")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                )

                        @unknown default:
                            EmptyView()
                        }
                    }

                    Text(imageURL.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var recordTitle: String {
        let year = record.year.map { "\($0)학년도" } ?? "연도 미상"
        let month = record.month.map { "\($0)월" } ?? "월 미상"
        return "\(year) \(month) \(record.examType) \(record.questionNumber)번"
    }
}

private struct PastQuestionBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

#Preview {
    PastQuestionsDebugView()
}
