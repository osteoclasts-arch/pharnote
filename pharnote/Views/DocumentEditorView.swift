import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentEditorLaunchTarget: Hashable {
    let document: PharDocument
    let initialPageKey: String?
}

enum WritingPenStyle: String, CaseIterable, Identifiable {
    case ballpoint = "볼펜"
    case pencil = "연필"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .ballpoint:
            return "pencil.tip"
        case .pencil:
            return "pencil.and.scribble"
        }
    }
}

struct DocumentEditorView: View {
    let document: PharDocument
    let initialPageKey: String?

    init(document: PharDocument, initialPageKey: String? = nil) {
        self.document = document
        self.initialPageKey = initialPageKey
    }

    var body: some View {
        switch document.type {
        case .blankNote:
            BlankNoteEditorView(document: document, initialPageKey: initialPageKey)
        case .pdf:
            PDFDocumentEditorView(document: document, initialPageKey: initialPageKey)
        }
    }
}

struct WritingWorkspaceDocumentChip: Identifiable, Hashable {
    let id: UUID
    let title: String
    let isCurrent: Bool
}

enum WritingChromePalette {
    static let accent = Color(.sRGB, red: 1.0, green: 0.439, blue: 0.0, opacity: 1.0)
    static let ink = Color(.sRGB, red: 0.117, green: 0.156, blue: 0.262, opacity: 1.0)
    static let paper = Color(.sRGB, red: 0.965, green: 0.963, blue: 0.938, opacity: 1.0)
    static let chip = Color(.sRGB, red: 0.928, green: 0.923, blue: 0.847, opacity: 1.0)
    static let chipBorder = Color(.sRGB, red: 0.741, green: 0.733, blue: 0.651, opacity: 1.0)
    static let chromeBorder = Color(.sRGB, red: 0.58, green: 0.565, blue: 0.506, opacity: 1.0)
    static let paletteFill = Color(.sRGB, red: 0.932, green: 0.914, blue: 0.742, opacity: 1.0)
    static let canvas = Color(.sRGB, red: 0.973, green: 0.973, blue: 0.973, opacity: 1.0)
    static let hintFill = Color(.sRGB, red: 0.952, green: 0.698, blue: 0.467, opacity: 1.0)
    static let hintText = Color(.sRGB, red: 0.678, green: 0.384, blue: 0.125, opacity: 1.0)
    static let shadow = Color.black.opacity(0.12)
}

struct WritingChromeCapsule<Content: View>: View {
    let fill: Color
    let content: Content

    init(fill: Color = .white, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(WritingChromePalette.chromeBorder, lineWidth: 1.2)
            )
    }
}

struct WritingDocumentChipStrip: View {
    let chips: [WritingWorkspaceDocumentChip]
    var onSelect: (UUID) -> Void = { _ in }
    var onClose: (UUID) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    HStack(spacing: 10) {
                        Button {
                            onSelect(chip.id)
                        } label: {
                            Text(chip.title)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(chip.isCurrent ? Color.white : WritingChromePalette.ink.opacity(0.62))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onClose(chip.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(chip.isCurrent ? Color.white : WritingChromePalette.ink.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(
                        Capsule(style: .continuous)
                            .fill(chip.isCurrent ? WritingChromePalette.accent : WritingChromePalette.chip)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(chip.isCurrent ? WritingChromePalette.accent : WritingChromePalette.chipBorder, lineWidth: 1.2)
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct WritingChromeIconButton: View {
    let systemName: String
    var accentTint: Bool = false
    var isSelected: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: 36, height: 36)
                .background(
                    Group {
                        if isSelected {
                            Circle()
                                .fill(WritingChromePalette.accent)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        }
        return accentTint ? WritingChromePalette.accent : WritingChromePalette.ink
    }
}

struct WritingChromePlaceholderIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(WritingChromePalette.ink)
            .frame(width: 36, height: 36)
            .opacity(0.9)
    }
}

struct WritingToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(WritingChromePalette.chromeBorder.opacity(0.8))
            .frame(width: 1, height: 28)
    }
}

struct WritingStrokePresetButton: View {
    let slotIndex: Int
    let width: CGFloat
    let isSelected: Bool
    let action: () -> Void
    var onLongPress: (() -> Void)?

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.black.opacity(0.12))
                }

                WritingStrokePresetSample(width: width)
                    .foregroundStyle(WritingChromePalette.ink)
            }
            .frame(width: 48, height: 32)

            Text("\(slotIndex + 1)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(WritingChromePalette.ink.opacity(0.62))
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: action)
        .onLongPressGesture(minimumDuration: 0.35) {
            onLongPress?()
        }
    }
}

struct WritingStrokePresetConfiguration: Equatable {
    let values: [Double]
    let selectedIndex: Int
}

enum WritingStrokePresetStore {
    static let defaultValues: [Double] = [2, 5, 9]
    static let defaultSelectedIndex = 1

    static func configuration(toolKey: String, userDefaults: UserDefaults) -> WritingStrokePresetConfiguration {
        let valuesKey = "pharnote.stroke-presets.\(toolKey).values"
        let selectedIndexKey = "pharnote.stroke-presets.\(toolKey).selected-index"

        let storedValues = userDefaults.array(forKey: valuesKey) as? [Double]
        let normalizedValues = normalizedPresetValues(from: storedValues)
        let storedSelectedIndex = userDefaults.integer(forKey: selectedIndexKey)
        let normalizedSelectedIndex = min(max(storedSelectedIndex, 0), normalizedValues.count - 1)

        return WritingStrokePresetConfiguration(
            values: normalizedValues,
            selectedIndex: normalizedSelectedIndex
        )
    }

    static func save(
        toolKey: String,
        values: [Double],
        selectedIndex: Int,
        userDefaults: UserDefaults
    ) {
        let valuesKey = "pharnote.stroke-presets.\(toolKey).values"
        let selectedIndexKey = "pharnote.stroke-presets.\(toolKey).selected-index"

        let normalizedValues = normalizedPresetValues(from: values)
        let normalizedSelectedIndex = min(max(selectedIndex, 0), normalizedValues.count - 1)

        userDefaults.set(normalizedValues, forKey: valuesKey)
        userDefaults.set(normalizedSelectedIndex, forKey: selectedIndexKey)
    }

    private static func normalizedPresetValues(from values: [Double]?) -> [Double] {
        guard let values, values.count == defaultValues.count else {
            return defaultValues
        }
        return values.map { min(max($0, 1), 16) }
    }
}

struct WritingStrokePresetEditorView: View {
    let slotIndex: Int
    @Binding var width: Double
    var range: ClosedRange<Double> = 1...16

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("굵기 프리셋 \(slotIndex + 1)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(WritingChromePalette.ink)

            HStack(spacing: 12) {
                Circle()
                    .fill(WritingChromePalette.paper)
                    .overlay(
                        WritingStrokePresetSample(width: CGFloat(width))
                            .foregroundStyle(WritingChromePalette.ink)
                    )
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%.1f pt", width))
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(WritingChromePalette.ink)

                    Text("길게 눌러 저장 슬롯을 열고, 슬라이더로 세밀하게 조정합니다.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(WritingChromePalette.ink.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Slider(value: $width, in: range, step: 0.5)
                .tint(WritingChromePalette.accent)
        }
        .padding(16)
        .frame(width: 260)
    }
}

struct WritingPenStyleButton: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : WritingChromePalette.ink)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? WritingChromePalette.accent : Color.white.opacity(0.72))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? WritingChromePalette.accent : WritingChromePalette.chromeBorder.opacity(0.55),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

private struct WritingStrokePresetSample: View {
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.15, y: size.height * 0.68))
            path.addCurve(
                to: CGPoint(x: size.width * 0.48, y: size.height * 0.28),
                control1: CGPoint(x: size.width * 0.24, y: size.height * 0.18),
                control2: CGPoint(x: size.width * 0.34, y: size.height * 0.82)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.85, y: size.height * 0.62),
                control1: CGPoint(x: size.width * 0.61, y: size.height * 0.06),
                control2: CGPoint(x: size.width * 0.71, y: size.height * 0.9)
            )
            context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }
}

struct WritingColorSwatchButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(isSelected ? 0.55 : 0.18), lineWidth: isSelected ? 2.5 : 1.2)
                )
                .background(
                    Circle()
                        .fill(Color.white.opacity(isSelected ? 0.35 : 0))
                        .frame(width: 40, height: 40)
                )
        }
        .buttonStyle(.plain)
    }
}

struct WritingShareFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 74, height: 74)
                .background(
                    Circle()
                        .fill(WritingChromePalette.accent)
                )
                .shadow(color: WritingChromePalette.shadow, radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct WritingAnalyzeHintBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(WritingChromePalette.hintText)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(WritingChromePalette.hintFill.opacity(0.9))
            )
    }
}

struct WritingAccentActionButton: View {
    let title: String
    let systemName: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.241, green: 0.147, blue: 0.049))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WritingChromePalette.hintFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: WritingChromePalette.shadow.opacity(0.8), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct DocumentAudioRecording: Codable, Hashable, Identifiable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    var duration: TimeInterval
    var pageKey: String?
    var pageLabel: String?

    var displayTitle: String {
        if let pageLabel, !pageLabel.isEmpty {
            return pageLabel
        }
        return "오디오 메모"
    }

    var formattedDuration: String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedCreatedAt: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

final class DocumentAudioStore {
    private struct RecordingIndex: Codable {
        let version: Int
        let recordings: [DocumentAudioRecording]
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadRecordings(documentURL: URL) throws -> [DocumentAudioRecording] {
        let indexURL = metadataFileURL(for: documentURL)
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }

        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingIndex.self, from: data)
            .recordings
            .sorted { $0.createdAt > $1.createdAt }
    }

    func makeRecordingURL(documentURL: URL, recordingID: UUID) throws -> URL {
        try ensureAudioDirectoryExists(documentURL: documentURL)
        return audioDirectoryURL(for: documentURL)
            .appendingPathComponent("\(recordingID.uuidString.lowercased()).m4a", isDirectory: false)
    }

    func appendRecording(_ recording: DocumentAudioRecording, documentURL: URL) throws {
        var recordings = try loadRecordings(documentURL: documentURL)
        recordings.insert(recording, at: 0)
        try saveRecordings(recordings, documentURL: documentURL)
    }

    func deleteRecording(_ recording: DocumentAudioRecording, documentURL: URL) throws {
        let fileURL = audioDirectoryURL(for: documentURL).appendingPathComponent(recording.fileName, isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        let updated = try loadRecordings(documentURL: documentURL).filter { $0.id != recording.id }
        try saveRecordings(updated, documentURL: documentURL)
    }

    func deleteRecordingFile(named fileName: String, documentURL: URL) {
        let fileURL = audioDirectoryURL(for: documentURL).appendingPathComponent(fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    func recordingFileURL(for recording: DocumentAudioRecording, documentURL: URL) -> URL {
        audioDirectoryURL(for: documentURL).appendingPathComponent(recording.fileName, isDirectory: false)
    }

    private func saveRecordings(_ recordings: [DocumentAudioRecording], documentURL: URL) throws {
        try ensureAudioDirectoryExists(documentURL: documentURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(
            RecordingIndex(version: 1, recordings: recordings.sorted { $0.createdAt > $1.createdAt })
        )
        try data.write(to: metadataFileURL(for: documentURL), options: .atomic)
    }

    private func ensureAudioDirectoryExists(documentURL: URL) throws {
        let directoryURL = audioDirectoryURL(for: documentURL)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
        if exists {
            if isDirectory.boolValue { return }
            try fileManager.removeItem(at: directoryURL)
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func audioDirectoryURL(for documentURL: URL) -> URL {
        documentURL.appendingPathComponent("AudioRecordings", isDirectory: true)
    }

    private func metadataFileURL(for documentURL: URL) -> URL {
        audioDirectoryURL(for: documentURL).appendingPathComponent("Recordings.json", isDirectory: false)
    }
}

@MainActor
final class DocumentAudioController: NSObject, ObservableObject {
    struct Anchor {
        let pageKey: String?
        let pageLabel: String?
    }

    enum PermissionState {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var recordings: [DocumentAudioRecording] = []
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var activeRecordingDuration: TimeInterval = 0
    @Published private(set) var playingRecordingID: UUID?
    @Published private(set) var permissionState: PermissionState = .unknown
    @Published var errorMessage: String?

    private let store: DocumentAudioStore
    private let libraryStore: LibraryStore
    private let anchorProvider: @MainActor () -> Anchor
    private var document: PharDocument
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var activeDraft: DocumentAudioRecording?
    private var durationTimer: Timer?
    private var didLoad = false

    init(
        document: PharDocument,
        store: DocumentAudioStore? = nil,
        libraryStore: LibraryStore? = nil,
        anchorProvider: @escaping @MainActor () -> Anchor
    ) {
        self.document = document
        self.store = store ?? DocumentAudioStore()
        self.libraryStore = libraryStore ?? LibraryStore()
        self.anchorProvider = anchorProvider
        super.init()
    }

    func loadRecordingsIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        loadRecordings()
    }

    func loadRecordings() {
        do {
            recordings = try store.loadRecordings(documentURL: documentURL)
        } catch {
            errorMessage = "오디오 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording()
            }
        }
    }

    func togglePlayback(for recording: DocumentAudioRecording) {
        if playingRecordingID == recording.id {
            stopPlayback()
        } else {
            play(recording)
        }
    }

    func deleteRecording(_ recording: DocumentAudioRecording) {
        if playingRecordingID == recording.id {
            stopPlayback()
        }

        do {
            try store.deleteRecording(recording, documentURL: documentURL)
            recordings.removeAll { $0.id == recording.id }
            touchDocumentUpdatedAt()
        } catch {
            errorMessage = "오디오를 삭제하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func handleBackgroundTransition() {
        if isRecording {
            stopRecording()
        }
        if playingRecordingID != nil {
            stopPlayback()
        }
    }

    func tearDown() {
        handleBackgroundTransition()
        durationTimer?.invalidate()
        durationTimer = nil
    }

    var activeRecordingDurationText: String {
        let totalSeconds = max(Int(activeRecordingDuration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startRecording() async {
        let allowed = await requestRecordPermissionIfNeeded()
        guard allowed else {
            errorMessage = "마이크 접근이 필요합니다. 설정에서 마이크 권한을 허용해 주세요."
            return
        }

        stopPlayback()

        let recordingID = UUID()
        let anchor = anchorProvider()

        do {
            try configureSessionForRecording()

            let recordingURL = try store.makeRecordingURL(documentURL: documentURL, recordingID: recordingID)
            let recorder = try AVAudioRecorder(url: recordingURL, settings: Self.recordingSettings)
            recorder.delegate = self
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw NSError(domain: "DocumentAudioController", code: -1, userInfo: [NSLocalizedDescriptionKey: "녹음을 시작하지 못했습니다."])
            }

            self.recorder = recorder
            self.activeDraft = DocumentAudioRecording(
                id: recordingID,
                fileName: recordingURL.lastPathComponent,
                createdAt: Date(),
                duration: 0,
                pageKey: anchor.pageKey,
                pageLabel: anchor.pageLabel
            )
            self.isRecording = true
            self.activeRecordingDuration = 0
            startDurationTimer()
        } catch {
            store.deleteRecordingFile(named: "\(recordingID.uuidString.lowercased()).m4a", documentURL: documentURL)
            errorMessage = "녹음을 시작하지 못했습니다: \(error.localizedDescription)"
            deactivateSessionIfIdle()
        }
    }

    private func stopRecording() {
        recorder?.stop()
    }

    private func play(_ recording: DocumentAudioRecording) {
        if isRecording {
            stopRecording()
        }

        do {
            try configureSessionForPlayback()
            let url = store.recordingFileURL(for: recording, documentURL: documentURL)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()

            guard player.play() else {
                throw NSError(domain: "DocumentAudioController", code: -2, userInfo: [NSLocalizedDescriptionKey: "재생을 시작하지 못했습니다."])
            }

            self.player = player
            self.playingRecordingID = recording.id
        } catch {
            errorMessage = "오디오를 재생하지 못했습니다: \(error.localizedDescription)"
            stopPlayback()
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playingRecordingID = nil
        deactivateSessionIfIdle()
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder else { return }
                self.activeRecordingDuration = recorder.currentTime
            }
        }
        durationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finishRecording(successfully flag: Bool) {
        durationTimer?.invalidate()
        durationTimer = nil

        let recordedDuration = recorder?.currentTime ?? 0
        recorder = nil
        isRecording = false
        activeRecordingDuration = 0

        guard flag, var draft = activeDraft else {
            if let failedDraft = activeDraft {
                store.deleteRecordingFile(named: failedDraft.fileName, documentURL: documentURL)
            }
            activeDraft = nil
            deactivateSessionIfIdle()
            return
        }

        draft.duration = recordedDuration

        do {
            try store.appendRecording(draft, documentURL: documentURL)
            recordings = try store.loadRecordings(documentURL: documentURL)
            touchDocumentUpdatedAt()
        } catch {
            errorMessage = "녹음을 저장하지 못했습니다: \(error.localizedDescription)"
            store.deleteRecordingFile(named: draft.fileName, documentURL: documentURL)
        }

        activeDraft = nil
        deactivateSessionIfIdle()
    }

    private func requestRecordPermissionIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                permissionState = .granted
                return true
            case .denied:
                permissionState = .denied
                return false
            case .undetermined:
                let granted = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { isGranted in
                        continuation.resume(returning: isGranted)
                    }
                }
                permissionState = granted ? .granted : .denied
                return granted
            @unknown default:
                permissionState = .denied
                return false
            }
        }

        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            permissionState = .granted
            return true
        case .denied:
            permissionState = .denied
            return false
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
            permissionState = granted ? .granted : .denied
            return granted
        @unknown default:
            permissionState = .denied
            return false
        }
    }

    private func configureSessionForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func configureSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateSessionIfIdle() {
        guard !isRecording, player == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func touchDocumentUpdatedAt() {
        var updatedDocument = document
        updatedDocument.updatedAt = Date()
        if let savedDocument = try? libraryStore.updateDocument(updatedDocument) {
            document = savedDocument
        } else {
            document = updatedDocument
        }
    }

    private var documentURL: URL {
        URL(fileURLWithPath: document.path, isDirectory: true)
    }

    private static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }
}

extension DocumentAudioController: AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finishRecording(successfully: flag)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
        }
    }
}

struct DocumentAudioPanelView: View {
    @ObservedObject var controller: DocumentAudioController

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                    Text("오디오")
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    Text(controller.isRecording ? "현재 문서에 음성 메모를 녹음 중입니다." : "문서별 음성 메모를 저장하고 재생할 수 있습니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                }

                Spacer(minLength: 0)

                PharTagPill(
                    text: "\(controller.recordings.count)개",
                    tint: controller.isRecording ? PharTheme.ColorToken.accentPeach.opacity(0.24) : PharTheme.ColorToken.surfaceSecondary,
                    foreground: PharTheme.ColorToken.inkPrimary
                )
            }

            if controller.isRecording {
                HStack(spacing: PharTheme.Spacing.small) {
                    Circle()
                        .fill(PharTheme.ColorToken.destructive)
                        .frame(width: 10, height: 10)

                    Text("녹음 중 \(controller.activeRecordingDurationText)")
                        .font(PharTypography.bodyStrong.monospacedDigit())
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                    Spacer(minLength: 0)

                    Button("정지") {
                        controller.toggleRecording()
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                }
                .padding(.horizontal, PharTheme.Spacing.small)
                .padding(.vertical, PharTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                        .fill(PharTheme.ColorToken.accentPeach.opacity(0.14))
                )
            } else if controller.recordings.isEmpty {
                Text("아직 오디오 메모가 없습니다. 상단의 마이크 버튼으로 녹음을 시작할 수 있습니다.")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
                    .padding(.horizontal, PharTheme.Spacing.small)
                    .padding(.vertical, PharTheme.Spacing.small)
                    .background(
                        RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                            .fill(PharTheme.ColorToken.surfaceSecondary.opacity(0.72))
                    )
            }

            if !controller.recordings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PharTheme.Spacing.small) {
                        ForEach(controller.recordings) { recording in
                            audioCard(for: recording)
                        }
                    }
                    .padding(.vertical, PharTheme.Spacing.xxxSmall)
                }
            }
        }
    }

    private func audioCard(for recording: DocumentAudioRecording) -> some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfaceSecondary.opacity(0.92)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.displayTitle)
                            .font(PharTypography.bodyStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            .lineLimit(1)

                        Text(recording.formattedCreatedAt)
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button {
                        controller.deleteRecording(recording)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
                    .accessibilityLabel("오디오 삭제")
                }

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    PharTagPill(
                        text: recording.formattedDuration,
                        tint: PharTheme.ColorToken.surfaceTertiary,
                        foreground: PharTheme.ColorToken.inkPrimary
                    )

                    if let pageLabel = recording.pageLabel {
                        PharTagPill(
                            text: pageLabel,
                            tint: PharTheme.ColorToken.accentBlue.opacity(0.12),
                            foreground: PharTheme.ColorToken.accentBlue
                        )
                    }
                }

                Button {
                    controller.togglePlayback(for: recording)
                } label: {
                    Label(
                        controller.playingRecordingID == recording.id ? "재생 중지" : "재생",
                        systemImage: controller.playingRecordingID == recording.id ? "stop.fill" : "play.fill"
                    )
                }
                .modifier(ActivePlaybackButtonStyle(isActive: controller.playingRecordingID == recording.id))
            }
            .frame(width: 244, alignment: .leading)
        }
    }
}

private struct ActivePlaybackButtonStyle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.buttonStyle(PharPrimaryButtonStyle())
        } else {
            content.buttonStyle(PharSoftButtonStyle())
        }
    }
}

struct WritingDocumentShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum WritingDocumentShareSource {
    static func activityItems(for document: PharDocument) -> [Any] {
        let packageURL = URL(fileURLWithPath: document.path, isDirectory: true)
        if document.type == .pdf {
            let preferredPDFURL = packageURL.appendingPathComponent("Original.pdf", isDirectory: false)
            if FileManager.default.fileExists(atPath: preferredPDFURL.path) {
                return [preferredPDFURL]
            }
        }
        return [packageURL]
    }
}

struct WritingSharedFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum DocumentWorkspaceAttachmentKind: String, Codable, Hashable, CaseIterable {
    case image
    case file

    var title: String {
        switch self {
        case .image:
            return "사진"
        case .file:
            return "파일"
        }
    }

    var systemImage: String {
        switch self {
        case .image:
            return "photo"
        case .file:
            return "doc"
        }
    }
}

struct DocumentWorkspaceTextEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let pageKey: String?
    let pageLabel: String?
    let createdAt: Date
    var updatedAt: Date
    var text: String
}

struct DocumentWorkspaceAttachmentPlacement: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var normalizedRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func clamped(minDimension: CGFloat = 0.12, maxDimension: CGFloat = 0.92) -> DocumentWorkspaceAttachmentPlacement {
        let clampedWidth = min(max(CGFloat(width), minDimension), maxDimension)
        let clampedHeight = min(max(CGFloat(height), minDimension), maxDimension)
        let clampedX = min(max(CGFloat(x), 0), max(0, 1 - clampedWidth))
        let clampedY = min(max(CGFloat(y), 0), max(0, 1 - clampedHeight))

        return DocumentWorkspaceAttachmentPlacement(
            x: Double(clampedX),
            y: Double(clampedY),
            width: Double(clampedWidth),
            height: Double(clampedHeight)
        )
    }

    func scaled(by factor: CGFloat) -> DocumentWorkspaceAttachmentPlacement {
        let clampedFactor = min(max(factor, 0.55), 1.6)
        let currentCenterX = CGFloat(x) + CGFloat(width) / 2
        let currentCenterY = CGFloat(y) + CGFloat(height) / 2
        let scaledWidth = CGFloat(width) * clampedFactor
        let scaledHeight = CGFloat(height) * clampedFactor

        return DocumentWorkspaceAttachmentPlacement(
            x: Double(currentCenterX - scaledWidth / 2),
            y: Double(currentCenterY - scaledHeight / 2),
            width: Double(scaledWidth),
            height: Double(scaledHeight)
        ).clamped()
    }

    func fitted(to imageSize: CGSize, scale: CGFloat) -> DocumentWorkspaceAttachmentPlacement {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return scaled(by: scale)
        }

        let aspectRatio = imageSize.width / imageSize.height
        let originalCenterX = CGFloat(x) + CGFloat(width) / 2
        let originalCenterY = CGFloat(y) + CGFloat(height) / 2
        let currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        var fittedSize = AVMakeRect(
            aspectRatio: imageSize,
            insideRect: CGRect(origin: .zero, size: currentSize)
        ).size

        let clampedScale = min(max(scale, 0.55), 1.6)
        fittedSize.width *= clampedScale
        fittedSize.height *= clampedScale

        let minimumWidth: CGFloat = 0.12
        let minimumHeight = minimumWidth / max(aspectRatio, 0.2)
        let maximumWidth: CGFloat = 0.92
        let maximumHeight: CGFloat = 0.92

        if fittedSize.width < minimumWidth {
            fittedSize = CGSize(width: minimumWidth, height: minimumWidth / aspectRatio)
        }
        if fittedSize.height < minimumHeight {
            fittedSize = CGSize(width: minimumHeight * aspectRatio, height: minimumHeight)
        }
        if fittedSize.width > maximumWidth {
            fittedSize = CGSize(width: maximumWidth, height: maximumWidth / aspectRatio)
        }
        if fittedSize.height > maximumHeight {
            fittedSize = CGSize(width: maximumHeight * aspectRatio, height: maximumHeight)
        }

        return DocumentWorkspaceAttachmentPlacement(
            x: Double(originalCenterX - fittedSize.width / 2),
            y: Double(originalCenterY - fittedSize.height / 2),
            width: Double(fittedSize.width),
            height: Double(fittedSize.height)
        ).clamped()
    }

    static func defaultPlacement(for imageSize: CGSize) -> DocumentWorkspaceAttachmentPlacement {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return DocumentWorkspaceAttachmentPlacement(
                x: 0.27,
                y: 0.16,
                width: 0.46,
                height: 0.28
            )
        }

        let maxBox = CGSize(width: 0.46, height: 0.32)
        let fittedSize = AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: .zero, size: maxBox)).size
        let width = max(0.18, fittedSize.width)
        let height = max(0.14, fittedSize.height)

        return DocumentWorkspaceAttachmentPlacement(
            x: Double((1 - width) / 2),
            y: 0.16,
            width: Double(width),
            height: Double(height)
        ).clamped()
    }
}

struct DocumentWorkspaceAttachmentItem: Codable, Hashable, Identifiable {
    let id: UUID
    let kind: DocumentWorkspaceAttachmentKind
    var storedFileName: String
    var originalFileName: String
    let pageKey: String?
    let pageLabel: String?
    let createdAt: Date
    var byteCount: Int64
    var placement: DocumentWorkspaceAttachmentPlacement?

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var displayTitle: String {
        originalFileName.isEmpty ? storedFileName : originalFileName
    }
}

struct WritingImportedImageDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    let suggestedFileName: String?
}

struct WritingImageEditorContext: Identifiable {
    let id = UUID()
    let draft: WritingImportedImageDraft
    let attachmentID: UUID?
    let basePlacement: DocumentWorkspaceAttachmentPlacement?
}

struct DocumentWorkspaceIndex: Codable {
    let version: Int
    var textEntries: [DocumentWorkspaceTextEntry]
    var attachments: [DocumentWorkspaceAttachmentItem]
}

actor DocumentWorkspaceStore {
    enum StoreError: LocalizedError {
        case invalidAttachmentData

        var errorDescription: String? {
            switch self {
            case .invalidAttachmentData:
                return "첨부 데이터를 읽지 못했습니다."
            }
        }
    }

    private let fileManager = FileManager.default
    private let metadataFileName = "WorkspaceSupplements.json"
    private let attachmentsDirectoryName = "WorkspaceAttachments"

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load(documentURL: URL) throws -> DocumentWorkspaceIndex {
        let metadataURL = metadataFileURL(for: documentURL)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return DocumentWorkspaceIndex(version: 1, textEntries: [], attachments: [])
        }

        let data = try Data(contentsOf: metadataURL)
        return try decoder.decode(DocumentWorkspaceIndex.self, from: data)
    }

    func save(index: DocumentWorkspaceIndex, documentURL: URL) throws {
        try ensureAttachmentsDirectoryExists(documentURL: documentURL)
        let data = try encoder.encode(index)
        try data.write(to: metadataFileURL(for: documentURL), options: .atomic)
    }

    func makeAttachmentURL(
        documentURL: URL,
        attachmentID: UUID,
        originalFileName: String,
        fallbackExtension: String?
    ) throws -> URL {
        try ensureAttachmentsDirectoryExists(documentURL: documentURL)

        let originalExtension = URL(fileURLWithPath: originalFileName).pathExtension
        let resolvedExtension = originalExtension.isEmpty ? (fallbackExtension ?? "") : originalExtension
        let normalizedExtension = resolvedExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = attachmentID.uuidString.lowercased()
        let fileName = normalizedExtension.isEmpty ? baseName : "\(baseName).\(normalizedExtension)"
        return attachmentsDirectoryURL(for: documentURL).appendingPathComponent(fileName, isDirectory: false)
    }

    func saveAttachmentData(_ data: Data, to destinationURL: URL) throws -> Int64 {
        guard !data.isEmpty else {
            throw StoreError.invalidAttachmentData
        }
        try data.write(to: destinationURL, options: .atomic)
        return Int64(data.count)
    }

    func importAttachment(from sourceURL: URL, to destinationURL: URL) throws -> Int64 {
        let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var coordinationError: NSError?
        var copyError: Error?
        var copiedFileSize: Int64 = 0
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: destinationURL)
                let values = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
                if let totalAllocatedSize = values.totalFileAllocatedSize {
                    copiedFileSize = Int64(totalAllocatedSize)
                } else if let fileSize = values.fileSize {
                    copiedFileSize = Int64(fileSize)
                }
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }

        if copiedFileSize == 0 {
            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            copiedFileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }

        return copiedFileSize
    }

    func deleteAttachment(_ attachment: DocumentWorkspaceAttachmentItem, documentURL: URL) {
        let fileURL = attachmentFileURL(for: attachment, documentURL: documentURL)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    func attachmentFileURL(for attachment: DocumentWorkspaceAttachmentItem, documentURL: URL) -> URL {
        attachmentsDirectoryURL(for: documentURL).appendingPathComponent(attachment.storedFileName, isDirectory: false)
    }

    private func ensureAttachmentsDirectoryExists(documentURL: URL) throws {
        let directoryURL = attachmentsDirectoryURL(for: documentURL)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
        if exists {
            if isDirectory.boolValue { return }
            try fileManager.removeItem(at: directoryURL)
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func metadataFileURL(for documentURL: URL) -> URL {
        documentURL.appendingPathComponent(metadataFileName, isDirectory: false)
    }

    private func attachmentsDirectoryURL(for documentURL: URL) -> URL {
        documentURL.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
    }
}

@MainActor
final class DocumentWorkspaceController: ObservableObject {
    struct Anchor {
        let pageKey: String?
        let pageLabel: String?
    }

    @Published private(set) var textEntries: [DocumentWorkspaceTextEntry] = []
    @Published private(set) var attachments: [DocumentWorkspaceAttachmentItem] = []
    @Published private(set) var selectedAttachmentID: UUID?
    @Published var errorMessage: String?

    private let store: DocumentWorkspaceStore
    private let libraryStore: LibraryStore
    private let anchorProvider: @MainActor () -> Anchor
    private var document: PharDocument
    private var didLoad = false

    init(
        document: PharDocument,
        store: DocumentWorkspaceStore? = nil,
        libraryStore: LibraryStore? = nil,
        anchorProvider: @escaping @MainActor () -> Anchor
    ) {
        self.document = document
        self.store = store ?? DocumentWorkspaceStore()
        self.libraryStore = libraryStore ?? LibraryStore()
        self.anchorProvider = anchorProvider
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        load()
    }

    func load() {
        Task {
            do {
                let index = try await store.load(documentURL: documentURL)
                textEntries = index.textEntries.sorted { $0.updatedAt > $1.updatedAt }
                let sortedAttachments = index.attachments.sorted { $0.createdAt > $1.createdAt }
                let migratedAttachments = migrateLegacyImagePlacements(in: sortedAttachments)
                attachments = migratedAttachments
                if migratedAttachments != sortedAttachments {
                    persistWorkspaceState()
                }
            } catch {
                errorMessage = "페이지 보조 자료를 불러오지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    func addTextEntry(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let anchor = anchorProvider()
        let now = Date()
        let entry = DocumentWorkspaceTextEntry(
            id: UUID(),
            pageKey: anchor.pageKey,
            pageLabel: anchor.pageLabel,
            createdAt: now,
            updatedAt: now,
            text: trimmedText
        )

        textEntries.insert(entry, at: 0)
        persistWorkspaceState()
    }

    func importImageData(
        _ data: Data,
        suggestedFileName: String?,
        preferredPlacement: DocumentWorkspaceAttachmentPlacement? = nil
    ) {
        let attachmentID = UUID()
        let originalFileName = normalizedFileName(
            suggestedFileName,
            fallbackBaseName: "image-\(attachmentID.uuidString.lowercased())",
            fallbackExtension: "jpg"
        )
        let anchor = anchorProvider()

        Task {
            do {
                let destinationURL = try await store.makeAttachmentURL(
                    documentURL: documentURL,
                    attachmentID: attachmentID,
                    originalFileName: originalFileName,
                    fallbackExtension: "jpg"
                )
                let byteCount = try await store.saveAttachmentData(data, to: destinationURL)
                let imageSize = UIImage(data: data)?.size ?? CGSize(width: 1600, height: 1200)
                let attachment = DocumentWorkspaceAttachmentItem(
                    id: attachmentID,
                    kind: .image,
                    storedFileName: destinationURL.lastPathComponent,
                    originalFileName: originalFileName,
                    pageKey: anchor.pageKey,
                    pageLabel: anchor.pageLabel,
                    createdAt: Date(),
                    byteCount: byteCount,
                    placement: preferredPlacement ?? DocumentWorkspaceAttachmentPlacement.defaultPlacement(for: imageSize)
                )
                attachments.insert(attachment, at: 0)
                selectedAttachmentID = attachment.id
                persistWorkspaceState()
            } catch {
                errorMessage = "사진을 첨부하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    func makeImageDraft(from data: Data, suggestedFileName: String?) -> WritingImportedImageDraft? {
        guard let image = UIImage(data: data)?.normalizedForCanvasPlacement() else {
            errorMessage = "사진을 불러오지 못했습니다."
            return nil
        }

        return WritingImportedImageDraft(image: image, suggestedFileName: suggestedFileName)
    }

    func makeImageEditorContext(for attachmentID: UUID) -> WritingImageEditorContext? {
        guard let attachment = attachment(withID: attachmentID), attachment.kind == .image else {
            errorMessage = "편집할 사진을 찾지 못했습니다."
            return nil
        }

        let fileURL = attachmentFileURL(for: attachment)
        guard let image = UIImage(contentsOfFile: fileURL.path)?.normalizedForCanvasPlacement() else {
            errorMessage = "사진을 다시 불러오지 못했습니다."
            return nil
        }

        return WritingImageEditorContext(
            draft: WritingImportedImageDraft(
                image: image,
                suggestedFileName: attachment.originalFileName
            ),
            attachmentID: attachmentID,
            basePlacement: attachment.placement
        )
    }

    func pastedImageDraft() -> WritingImportedImageDraft? {
        if let pngData = UIPasteboard.general.data(forPasteboardType: UTType.png.identifier) {
            return makeImageDraft(from: pngData, suggestedFileName: pastedImageFileName(fileExtension: "png"))
        }

        if let jpegData = UIPasteboard.general.data(forPasteboardType: UTType.jpeg.identifier) {
            return makeImageDraft(from: jpegData, suggestedFileName: pastedImageFileName(fileExtension: "jpg"))
        }

        if let image = UIPasteboard.general.image?.normalizedForCanvasPlacement() {
            return WritingImportedImageDraft(
                image: image,
                suggestedFileName: pastedImageFileName(fileExtension: "png")
            )
        }

        errorMessage = "클립보드에 붙여넣을 사진이 없습니다."
        return nil
    }

    func importImageFromPasteboard() {
        if let pngData = UIPasteboard.general.data(forPasteboardType: UTType.png.identifier) {
            importImageData(pngData, suggestedFileName: pastedImageFileName(fileExtension: "png"))
            return
        }

        if let jpegData = UIPasteboard.general.data(forPasteboardType: UTType.jpeg.identifier) {
            importImageData(jpegData, suggestedFileName: pastedImageFileName(fileExtension: "jpg"))
            return
        }

        if let image = UIPasteboard.general.image, let pngData = image.pngData() {
            importImageData(pngData, suggestedFileName: pastedImageFileName(fileExtension: "png"))
            return
        }

        errorMessage = "클립보드에 붙여넣을 사진이 없습니다."
    }

    func importPastedImageProviders(_ providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            errorMessage = "붙여넣을 수 있는 사진을 찾지 못했습니다."
            return
        }

        let suggestedName = provider.suggestedName
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard let self else { return }

            Task { @MainActor in
                guard let data else {
                    self.errorMessage = "클립보드 사진을 읽지 못했습니다."
                    return
                }

                self.importImageData(data, suggestedFileName: suggestedName)
            }
        }
    }

    func importFile(from sourceURL: URL) {
        let attachmentID = UUID()
        let originalFileName = normalizedFileName(
            sourceURL.lastPathComponent,
            fallbackBaseName: "attachment-\(attachmentID.uuidString.lowercased())",
            fallbackExtension: sourceURL.pathExtension
        )
        let anchor = anchorProvider()

        Task {
            do {
                let destinationURL = try await store.makeAttachmentURL(
                    documentURL: documentURL,
                    attachmentID: attachmentID,
                    originalFileName: originalFileName,
                    fallbackExtension: sourceURL.pathExtension
                )
                let byteCount = try await store.importAttachment(from: sourceURL, to: destinationURL)
                let attachment = DocumentWorkspaceAttachmentItem(
                    id: attachmentID,
                    kind: .file,
                    storedFileName: destinationURL.lastPathComponent,
                    originalFileName: originalFileName,
                    pageKey: anchor.pageKey,
                    pageLabel: anchor.pageLabel,
                    createdAt: Date(),
                    byteCount: byteCount,
                    placement: nil
                )
                attachments.insert(attachment, at: 0)
                selectedAttachmentID = nil
                persistWorkspaceState()
            } catch {
                errorMessage = "파일을 첨부하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    func deleteTextEntry(_ entry: DocumentWorkspaceTextEntry) {
        textEntries.removeAll { $0.id == entry.id }
        persistWorkspaceState()
    }

    func deleteAttachment(_ attachment: DocumentWorkspaceAttachmentItem) {
        attachments.removeAll { $0.id == attachment.id }
        if selectedAttachmentID == attachment.id {
            selectedAttachmentID = nil
        }
        Task {
            await store.deleteAttachment(attachment, documentURL: documentURL)
        }
        persistWorkspaceState()
    }

    func selectAttachment(_ attachmentID: UUID?) {
        selectedAttachmentID = attachmentID
    }

    func clearAttachmentSelection() {
        selectedAttachmentID = nil
    }

    func attachment(withID attachmentID: UUID) -> DocumentWorkspaceAttachmentItem? {
        attachments.first { $0.id == attachmentID }
    }

    func imageAttachments(for pageKey: String?) -> [DocumentWorkspaceAttachmentItem] {
        filteredAttachments(pageKey: pageKey)
            .filter { $0.kind == .image }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func updateAttachmentPlacement(
        id attachmentID: UUID,
        placement: DocumentWorkspaceAttachmentPlacement,
        persist: Bool
    ) {
        guard let attachmentIndex = attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
        attachments[attachmentIndex].placement = placement.clamped()
        if persist {
            persistWorkspaceState()
        }
    }

    func replaceImageAttachmentData(
        id attachmentID: UUID,
        data: Data,
        suggestedFileName: String?,
        preferredPlacement: DocumentWorkspaceAttachmentPlacement?
    ) {
        guard let attachmentIndex = attachments.firstIndex(where: { $0.id == attachmentID }) else {
            errorMessage = "편집할 사진을 찾지 못했습니다."
            return
        }

        let currentAttachment = attachments[attachmentIndex]
        guard currentAttachment.kind == .image else {
            errorMessage = "사진 첨부만 편집할 수 있습니다."
            return
        }

        let originalFileName = normalizedFileName(
            suggestedFileName ?? currentAttachment.originalFileName,
            fallbackBaseName: "image-\(attachmentID.uuidString.lowercased())",
            fallbackExtension: "jpg"
        )

        Task {
            do {
                let destinationURL = try await store.makeAttachmentURL(
                    documentURL: documentURL,
                    attachmentID: attachmentID,
                    originalFileName: originalFileName,
                    fallbackExtension: "jpg"
                )
                let previousURL = attachmentFileURL(for: currentAttachment)
                let byteCount = try await store.saveAttachmentData(data, to: destinationURL)
                if previousURL.path != destinationURL.path {
                    try? FileManager.default.removeItem(at: previousURL)
                }

                guard let refreshedIndex = attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
                let editedImageSize = UIImage(data: data)?.size ?? CGSize(width: 1600, height: 1200)
                attachments[refreshedIndex].storedFileName = destinationURL.lastPathComponent
                attachments[refreshedIndex].originalFileName = originalFileName
                attachments[refreshedIndex].byteCount = byteCount
                attachments[refreshedIndex].placement = preferredPlacement
                    ?? attachments[refreshedIndex].placement?.fitted(to: editedImageSize, scale: 1)
                    ?? DocumentWorkspaceAttachmentPlacement.defaultPlacement(for: editedImageSize)
                selectedAttachmentID = attachmentID
                persistWorkspaceState()
            } catch {
                errorMessage = "사진 편집 내용을 저장하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    func attachmentFileURL(for attachment: DocumentWorkspaceAttachmentItem) -> URL {
        URL(fileURLWithPath: document.path, isDirectory: true)
            .appendingPathComponent("WorkspaceAttachments", isDirectory: true)
            .appendingPathComponent(attachment.storedFileName, isDirectory: false)
    }

    var currentPageTextEntries: [DocumentWorkspaceTextEntry] {
        let pageKey = anchorProvider().pageKey
        return filteredTextEntries(pageKey: pageKey)
    }

    var currentPageAttachments: [DocumentWorkspaceAttachmentItem] {
        let pageKey = anchorProvider().pageKey
        return filteredAttachments(pageKey: pageKey)
    }

    var currentPageImageAttachments: [DocumentWorkspaceAttachmentItem] {
        let pageKey = anchorProvider().pageKey
        return imageAttachments(for: pageKey)
    }

    var currentPageHasSupplements: Bool {
        !currentPageTextEntries.isEmpty || !currentPageAttachments.isEmpty
    }

    private func filteredTextEntries(pageKey: String?) -> [DocumentWorkspaceTextEntry] {
        textEntries.filter { $0.pageKey == pageKey }
    }

    private func filteredAttachments(pageKey: String?) -> [DocumentWorkspaceAttachmentItem] {
        attachments.filter { $0.pageKey == pageKey }
    }

    private func persistWorkspaceState() {
        let index = DocumentWorkspaceIndex(version: 1, textEntries: textEntries, attachments: attachments)

        Task {
            do {
                try await store.save(index: index, documentURL: documentURL)
                touchDocumentUpdatedAt()
            } catch {
                errorMessage = "페이지 보조 자료를 저장하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func touchDocumentUpdatedAt() {
        var updatedDocument = document
        updatedDocument.updatedAt = Date()
        if let savedDocument = try? libraryStore.updateDocument(updatedDocument) {
            document = savedDocument
        } else {
            document = updatedDocument
        }
    }

    private func normalizedFileName(_ proposedName: String?, fallbackBaseName: String, fallbackExtension: String) -> String {
        let trimmedName = (proposedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let normalizedExtension = fallbackExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedExtension.isEmpty {
            return fallbackBaseName
        }

        return "\(fallbackBaseName).\(normalizedExtension)"
    }

    private var documentURL: URL {
        URL(fileURLWithPath: document.path, isDirectory: true)
    }

    private func pastedImageFileName(fileExtension: String) -> String {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return "pasted-image-\(timestamp).\(fileExtension)"
    }

    private func migrateLegacyImagePlacements(in sourceAttachments: [DocumentWorkspaceAttachmentItem]) -> [DocumentWorkspaceAttachmentItem] {
        sourceAttachments.map { attachment in
            guard attachment.kind == .image, attachment.placement == nil else {
                return attachment
            }

            var updatedAttachment = attachment
            let fileURL = attachmentFileURL(for: attachment)
            let imageSize = UIImage(contentsOfFile: fileURL.path)?.size ?? CGSize(width: 1600, height: 1200)
            updatedAttachment.placement = DocumentWorkspaceAttachmentPlacement.defaultPlacement(for: imageSize)
            return updatedAttachment
        }
    }
}

struct WritingTextComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    let pageLabel: String?
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                if let pageLabel, !pageLabel.isEmpty {
                    PharTagPill(
                        text: pageLabel,
                        tint: PharTheme.ColorToken.accentBlue.opacity(0.16),
                        foreground: PharTheme.ColorToken.accentBlue
                    )
                }

                TextEditor(text: $text)
                    .font(PharTypography.body)
                    .padding(PharTheme.Spacing.small)
                    .frame(minHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                            .fill(PharTheme.ColorToken.surfaceSecondary.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                            .stroke(PharTheme.ColorToken.border.opacity(0.35), lineWidth: 1)
                    )

                Text("텍스트 메모는 현재 페이지에 연결되어 저장됩니다.")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)

                Spacer(minLength: 0)
            }
            .padding(PharTheme.Spacing.medium)
            .navigationTitle("텍스트 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct WritingPhotoLibraryPicker: UIViewControllerRepresentable {
    let onSelect: (Data, String?) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = .images

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onSelect: (Data, String?) -> Void
        private let onCancel: () -> Void

        init(onSelect: @escaping (Data, String?) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                onCancel()
                return
            }

            let suggestedName = result.itemProvider.suggestedName
            if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else {
                        DispatchQueue.main.async {
                            self.onCancel()
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self.onSelect(data, suggestedName)
                    }
                }
            } else {
                onCancel()
            }
        }
    }
}

struct WritingAttachmentFilePicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onSelect: (URL) -> Void
        private let onCancel: () -> Void

        init(onSelect: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let firstURL = urls.first else {
                onCancel()
                return
            }
            onSelect(firstURL)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

@MainActor
final class WritingImageCropSession: ObservableObject {
    fileprivate weak var cropView: WritingImageCropCanvasView?

    func attach(_ cropView: WritingImageCropCanvasView) {
        self.cropView = cropView
    }

    func reset() {
        cropView?.resetToDefaultPosition()
    }

    func croppedImage(fallback image: UIImage) -> UIImage {
        cropView?.croppedImage() ?? image
    }
}

struct WritingImageInsertionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cropSession = WritingImageCropSession()
    @State private var insertionScale: Double = 1.0

    let draft: WritingImportedImageDraft
    let basePlacement: DocumentWorkspaceAttachmentPlacement?
    let onConfirm: (Data, String?, DocumentWorkspaceAttachmentPlacement) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                WritingImageCropCanvasRepresentable(
                    session: cropSession,
                    image: draft.image
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                        .fill(Color.black.opacity(0.92))
                )
                .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous))

                VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                    HStack {
                        Text("삽입 크기")
                            .font(PharTypography.bodyStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                        Spacer(minLength: 0)

                        Text("\(Int(insertionScale * 100))%")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)
                    }

                    Slider(value: $insertionScale, in: 0.6...1.4, step: 0.05)
                        .tint(WritingChromePalette.accent)

                    Text("핀치로 확대하고 드래그로 위치를 조정한 뒤 삽입하세요.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                }
            }
            .padding(PharTheme.Spacing.medium)
            .navigationTitle("사진 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("초기화") {
                        cropSession.reset()
                        insertionScale = 1.0
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("삽입") {
                        handleConfirm()
                    }
                }
            }
        }
    }

    private func handleConfirm() {
        let croppedImage = cropSession.croppedImage(fallback: draft.image).normalizedForCanvasPlacement()
        guard let encoded = croppedImage.preferredAttachmentEncoding else { return }
        let placement = (basePlacement?.fitted(to: croppedImage.size, scale: insertionScale.cgFloatValue)
            ?? DocumentWorkspaceAttachmentPlacement
                .defaultPlacement(for: croppedImage.size)
                .scaled(by: insertionScale.cgFloatValue))
        let resolvedFileName = resolvedSuggestedFileName(forExtension: encoded.fileExtension)
        onConfirm(encoded.data, resolvedFileName, placement)
        dismiss()
    }

    private func resolvedSuggestedFileName(forExtension fileExtension: String) -> String? {
        let trimmed = draft.suggestedFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }

        let baseName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        return "\(baseName).\(fileExtension)"
    }
}

private extension Double {
    var cgFloatValue: CGFloat { CGFloat(self) }
}

struct WritingImageCropCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var session: WritingImageCropSession
    let image: UIImage

    func makeUIView(context: Context) -> WritingImageCropCanvasView {
        let view = WritingImageCropCanvasView(image: image)
        session.attach(view)
        return view
    }

    func updateUIView(_ uiView: WritingImageCropCanvasView, context: Context) {
        session.attach(uiView)
    }
}

@MainActor
final class WritingImageCropCanvasView: UIView, UIScrollViewDelegate {
    private let image: UIImage
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let maskLayer = CAShapeLayer()
    private let cropBorderLayer = CAShapeLayer()
    private var baseImageSize: CGSize = .zero
    private var didConfigureInitialViewport = false

    init(image: UIImage) {
        self.image = image
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        addSubview(scrollView)

        imageView.image = image
        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)

        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.56).cgColor
        layer.addSublayer(maskLayer)

        cropBorderLayer.strokeColor = UIColor.white.cgColor
        cropBorderLayer.fillColor = UIColor.clear.cgColor
        cropBorderLayer.lineWidth = 2
        cropBorderLayer.shadowColor = UIColor.black.cgColor
        cropBorderLayer.shadowOpacity = 0.18
        cropBorderLayer.shadowRadius = 10
        cropBorderLayer.shadowOffset = CGSize(width: 0, height: 6)
        layer.addSublayer(cropBorderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cropFrame = computedCropFrame()
        scrollView.frame = cropFrame
        updateOverlayPath(cropFrame: cropFrame)
        configureImageViewportIfNeeded(for: cropFrame)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func resetToDefaultPosition() {
        didConfigureInitialViewport = false
        setNeedsLayout()
        layoutIfNeeded()
    }

    func croppedImage() -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard baseImageSize.width > 0, baseImageSize.height > 0 else { return nil }

        let cropWidthScale = CGFloat(cgImage.width) / baseImageSize.width
        let cropHeightScale = CGFloat(cgImage.height) / baseImageSize.height
        let visibleRect = CGRect(
            x: scrollView.contentOffset.x / scrollView.zoomScale,
            y: scrollView.contentOffset.y / scrollView.zoomScale,
            width: scrollView.bounds.width / scrollView.zoomScale,
            height: scrollView.bounds.height / scrollView.zoomScale
        )
        let pixelCropRect = CGRect(
            x: visibleRect.origin.x * cropWidthScale,
            y: visibleRect.origin.y * cropHeightScale,
            width: visibleRect.width * cropWidthScale,
            height: visibleRect.height * cropHeightScale
        ).integral.intersection(CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))

        guard let croppedCGImage = cgImage.cropping(to: pixelCropRect), !pixelCropRect.isNull else {
            return image
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: .up)
    }

    private func configureImageViewportIfNeeded(for cropFrame: CGRect) {
        let fittedSize = aspectFillSize(for: image.size, in: cropFrame.size)
        let shouldReconfigure = !didConfigureInitialViewport || abs(fittedSize.width - baseImageSize.width) > 0.5 || abs(fittedSize.height - baseImageSize.height) > 0.5

        guard shouldReconfigure else { return }

        baseImageSize = fittedSize
        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        scrollView.contentSize = fittedSize
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.zoomScale = 1
        scrollView.contentOffset = CGPoint(
            x: max((fittedSize.width - cropFrame.width) / 2, 0),
            y: max((fittedSize.height - cropFrame.height) / 2, 0)
        )
        didConfigureInitialViewport = true
    }

    private func computedCropFrame() -> CGRect {
        let outerBounds = bounds.insetBy(dx: 24, dy: 24)
        let cropSize = AVMakeRect(aspectRatio: image.size, insideRect: outerBounds).size
        return CGRect(
            x: (bounds.width - cropSize.width) / 2,
            y: (bounds.height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        ).integral
    }

    private func updateOverlayPath(cropFrame: CGRect) {
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(roundedRect: cropFrame, cornerRadius: 20))
        maskLayer.path = path.cgPath

        cropBorderLayer.path = UIBezierPath(roundedRect: cropFrame, cornerRadius: 20).cgPath
    }

    private func aspectFillSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return containerSize }
        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let scale = max(widthScale, heightScale)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

struct DocumentWorkspaceAttachmentCanvasLayer: UIViewRepresentable {
    @ObservedObject var controller: DocumentWorkspaceController
    let pageKey: String?
    let allowsInteraction: Bool
    var onEditAttachment: ((UUID) -> Void)? = nil

    func makeUIView(context: Context) -> DocumentWorkspaceAttachmentCanvasUIView {
        let view = DocumentWorkspaceAttachmentCanvasUIView(
            controller: controller,
            onEditAttachment: onEditAttachment
        )
        view.update(pageKey: pageKey, allowsInteraction: allowsInteraction)
        return view
    }

    func updateUIView(_ uiView: DocumentWorkspaceAttachmentCanvasUIView, context: Context) {
        uiView.onEditAttachment = onEditAttachment
        uiView.update(pageKey: pageKey, allowsInteraction: allowsInteraction)
    }
}

@MainActor
final class DocumentWorkspaceAttachmentCanvasUIView: UIView {
    private let controller: DocumentWorkspaceController
    var onEditAttachment: ((UUID) -> Void)?
    private var pageKey: String?
    private var allowsInteraction = false
    private var cancellables: Set<AnyCancellable> = []
    private var imageViews: [UUID: DocumentWorkspacePlacedImageView] = [:]
    private var moveStartPlacements: [UUID: DocumentWorkspaceAttachmentPlacement] = [:]
    private var resizeStartPlacements: [UUID: DocumentWorkspaceAttachmentPlacement] = [:]

    init(
        controller: DocumentWorkspaceController,
        onEditAttachment: ((UUID) -> Void)? = nil
    ) {
        self.controller = controller
        self.onEditAttachment = onEditAttachment
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        subscribeToController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(pageKey: String?, allowsInteraction: Bool) {
        self.pageKey = pageKey
        self.allowsInteraction = allowsInteraction
        syncImageViews()
        updateSelectionState()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutImageViews()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard allowsInteraction else { return false }

        for imageView in subviews.reversed() {
            let convertedPoint = imageView.convert(point, from: self)
            if imageView.point(inside: convertedPoint, with: event) {
                return true
            }
        }

        return false
    }

    private func subscribeToController() {
        controller.$attachments
            .combineLatest(controller.$selectedAttachmentID)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.syncImageViews()
                self.updateSelectionState()
                self.setNeedsLayout()
            }
            .store(in: &cancellables)
    }

    private func syncImageViews() {
        let visibleAttachments = controller.imageAttachments(for: pageKey)
        let visibleIDs = Set(visibleAttachments.map(\.id))

        for (id, imageView) in imageViews where !visibleIDs.contains(id) {
            imageView.removeFromSuperview()
            imageViews.removeValue(forKey: id)
            moveStartPlacements.removeValue(forKey: id)
            resizeStartPlacements.removeValue(forKey: id)
        }

        for attachment in visibleAttachments {
            if imageViews[attachment.id] == nil {
                let imageView = makeImageView(for: attachment)
                imageViews[attachment.id] = imageView
                addSubview(imageView)
            }
        }
    }

    private func updateSelectionState() {
        for (id, imageView) in imageViews {
            imageView.updateSelection(
                isSelected: controller.selectedAttachmentID == id,
                allowsInteraction: allowsInteraction
            )
        }
    }

    private func layoutImageViews() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let visibleAttachments = controller.imageAttachments(for: pageKey)
        for attachment in visibleAttachments {
            guard let imageView = imageViews[attachment.id] else { continue }

            let placement = attachment.placement ?? defaultPlacement(for: attachment)
            imageView.frame = frame(for: placement)
            imageView.updateSelection(
                isSelected: controller.selectedAttachmentID == attachment.id,
                allowsInteraction: allowsInteraction
            )

            if controller.selectedAttachmentID == attachment.id {
                bringSubviewToFront(imageView)
            }
        }
    }

    private func makeImageView(for attachment: DocumentWorkspaceAttachmentItem) -> DocumentWorkspacePlacedImageView {
        let fileURL = controller.attachmentFileURL(for: attachment)
        let image = UIImage(contentsOfFile: fileURL.path) ?? UIImage()
        let imageView = DocumentWorkspacePlacedImageView(attachmentID: attachment.id, image: image)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleItemTap(_:)))
        imageView.addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleItemPan(_:)))
        panGesture.maximumNumberOfTouches = 1
        imageView.addGestureRecognizer(panGesture)

        let resizePanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        resizePanGesture.maximumNumberOfTouches = 1
        imageView.resizeHandle.addGestureRecognizer(resizePanGesture)

        imageView.editButton.addTarget(self, action: #selector(handleEditButtonTap(_:)), for: .touchUpInside)

        return imageView
    }

    @objc
    private func handleItemTap(_ gesture: UITapGestureRecognizer) {
        guard allowsInteraction,
              let imageView = gesture.view as? DocumentWorkspacePlacedImageView else { return }
        controller.selectAttachment(imageView.attachmentID)
    }

    @objc
    private func handleItemPan(_ gesture: UIPanGestureRecognizer) {
        guard allowsInteraction,
              let imageView = gesture.view as? DocumentWorkspacePlacedImageView,
              let attachment = controller.attachment(withID: imageView.attachmentID) else { return }

        let attachmentID = imageView.attachmentID
        let startingPlacement = attachment.placement ?? defaultPlacement(for: attachment)

        switch gesture.state {
        case .began:
            controller.selectAttachment(attachmentID)
            moveStartPlacements[attachmentID] = startingPlacement
        case .changed:
            guard let initialPlacement = moveStartPlacements[attachmentID] else { return }
            let translation = gesture.translation(in: self)
            let updatedPlacement = DocumentWorkspaceAttachmentPlacement(
                x: initialPlacement.x + Double(translation.x / bounds.width),
                y: initialPlacement.y + Double(translation.y / bounds.height),
                width: initialPlacement.width,
                height: initialPlacement.height
            ).clamped()
            controller.updateAttachmentPlacement(id: attachmentID, placement: updatedPlacement, persist: false)
        case .ended, .cancelled, .failed:
            moveStartPlacements.removeValue(forKey: attachmentID)
            if let finalPlacement = controller.attachment(withID: attachmentID)?.placement {
                controller.updateAttachmentPlacement(id: attachmentID, placement: finalPlacement, persist: true)
            }
        default:
            break
        }
    }

    @objc
    private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard allowsInteraction,
              let handleView = gesture.view,
              let imageView = handleView.superview as? DocumentWorkspacePlacedImageView,
              let attachment = controller.attachment(withID: imageView.attachmentID) else { return }

        let attachmentID = imageView.attachmentID
        let startingPlacement = attachment.placement ?? defaultPlacement(for: attachment)
        let aspectRatio = max(CGFloat(startingPlacement.width / max(startingPlacement.height, 0.0001)), 0.2)

        switch gesture.state {
        case .began:
            controller.selectAttachment(attachmentID)
            resizeStartPlacements[attachmentID] = startingPlacement
        case .changed:
            guard let initialPlacement = resizeStartPlacements[attachmentID] else { return }
            let translation = gesture.translation(in: self)
            let scaleX = 1 + (translation.x / max(bounds.width, 1))
            let scaleY = 1 + (translation.y / max(bounds.height, 1))
            let scale = max(0.45, max(scaleX, scaleY))

            var proposedWidth = CGFloat(initialPlacement.width) * scale
            proposedWidth = min(max(proposedWidth, 0.12), 1 - CGFloat(initialPlacement.x))
            let proposedHeight = min(max(proposedWidth / aspectRatio, 0.12), 1 - CGFloat(initialPlacement.y))
            proposedWidth = min(max(proposedHeight * aspectRatio, 0.12), 1 - CGFloat(initialPlacement.x))

            let updatedPlacement = DocumentWorkspaceAttachmentPlacement(
                x: initialPlacement.x,
                y: initialPlacement.y,
                width: Double(proposedWidth),
                height: Double(proposedHeight)
            ).clamped()
            controller.updateAttachmentPlacement(id: attachmentID, placement: updatedPlacement, persist: false)
        case .ended, .cancelled, .failed:
            resizeStartPlacements.removeValue(forKey: attachmentID)
            if let finalPlacement = controller.attachment(withID: attachmentID)?.placement {
                controller.updateAttachmentPlacement(id: attachmentID, placement: finalPlacement, persist: true)
            }
        default:
            break
        }
    }

    @objc
    private func handleEditButtonTap(_ sender: UIButton) {
        guard allowsInteraction,
              let imageView = sender.superview as? DocumentWorkspacePlacedImageView else { return }
        controller.selectAttachment(imageView.attachmentID)
        onEditAttachment?(imageView.attachmentID)
    }

    private func frame(for placement: DocumentWorkspaceAttachmentPlacement) -> CGRect {
        CGRect(
            x: bounds.width * placement.normalizedRect.origin.x,
            y: bounds.height * placement.normalizedRect.origin.y,
            width: bounds.width * placement.normalizedRect.width,
            height: bounds.height * placement.normalizedRect.height
        ).integral
    }

    private func defaultPlacement(for attachment: DocumentWorkspaceAttachmentItem) -> DocumentWorkspaceAttachmentPlacement {
        let fileURL = controller.attachmentFileURL(for: attachment)
        let imageSize = UIImage(contentsOfFile: fileURL.path)?.size ?? CGSize(width: 1600, height: 1200)
        return DocumentWorkspaceAttachmentPlacement.defaultPlacement(for: imageSize)
    }
}

private final class DocumentWorkspacePlacedImageView: UIView {
    let attachmentID: UUID
    let resizeHandle = UIView()
    let editButton = UIButton(type: .system)

    private let imageView = UIImageView()
    private let selectionBorder = CAShapeLayer()
    private let accentColor = UIColor(red: 1.0, green: 0.439, blue: 0.0, alpha: 1.0)

    init(attachmentID: UUID, image: UIImage) {
        self.attachmentID = attachmentID
        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = false

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.black.withAlphaComponent(0.06).cgColor
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.08
        imageView.layer.shadowRadius = 14
        imageView.layer.shadowOffset = CGSize(width: 0, height: 8)
        addSubview(imageView)

        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.strokeColor = accentColor.cgColor
        selectionBorder.lineWidth = 2
        selectionBorder.lineDashPattern = [8, 6]
        selectionBorder.isHidden = true
        layer.addSublayer(selectionBorder)

        resizeHandle.backgroundColor = accentColor
        resizeHandle.layer.cornerRadius = 13
        resizeHandle.layer.borderWidth = 3
        resizeHandle.layer.borderColor = UIColor.white.cgColor
        resizeHandle.layer.shadowColor = UIColor.black.cgColor
        resizeHandle.layer.shadowOpacity = 0.12
        resizeHandle.layer.shadowRadius = 6
        resizeHandle.layer.shadowOffset = CGSize(width: 0, height: 3)
        resizeHandle.isHidden = true
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)

        var config = UIButton.Configuration.filled()
        config.title = "자르기"
        config.baseBackgroundColor = accentColor
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        editButton.configuration = config
        editButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        editButton.isHidden = true
        addSubview(editButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        selectionBorder.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerRadius: 12
        ).cgPath
        editButton.sizeToFit()
        let editSize = editButton.bounds.size
        editButton.frame = CGRect(x: 8, y: 8, width: max(editSize.width, 56), height: max(editSize.height, 32))
        resizeHandle.frame = CGRect(x: bounds.maxX - 26, y: bounds.maxY - 26, width: 26, height: 26)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if !editButton.isHidden && editButton.frame.insetBy(dx: -12, dy: -12).contains(point) {
            return true
        }
        if !resizeHandle.isHidden {
            let expandedHandleFrame = resizeHandle.frame.insetBy(dx: -18, dy: -18)
            if expandedHandleFrame.contains(point) {
                return true
            }
        }
        return bounds.insetBy(dx: -8, dy: -8).contains(point)
    }

    func updateSelection(isSelected: Bool, allowsInteraction: Bool) {
        selectionBorder.isHidden = !(isSelected && allowsInteraction)
        resizeHandle.isHidden = !(isSelected && allowsInteraction)
        editButton.isHidden = !(isSelected && allowsInteraction)
    }
}

private struct WritingPreferredAttachmentEncoding {
    let data: Data
    let fileExtension: String
}

private extension UIImage {
    func normalizedForCanvasPlacement() -> UIImage {
        guard imageOrientation != .up else { return self }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = scale
        return UIGraphicsImageRenderer(size: size, format: rendererFormat).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    var preferredAttachmentEncoding: WritingPreferredAttachmentEncoding? {
        if hasAlphaChannel(), let pngData = pngData() {
            return WritingPreferredAttachmentEncoding(data: pngData, fileExtension: "png")
        }

        if let jpegData = jpegData(compressionQuality: 0.94) {
            return WritingPreferredAttachmentEncoding(data: jpegData, fileExtension: "jpg")
        }

        return nil
    }

    private func hasAlphaChannel() -> Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}
