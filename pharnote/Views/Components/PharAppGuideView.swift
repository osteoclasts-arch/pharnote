import SwiftUI

struct PharAppGuideStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let iconName: String
    let color: Color
}

struct PharAppGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    
    let steps = [
        PharAppGuideStep(
            title: "사고의 흐름을 기록하세요",
            description: "단순히 문제를 푸는 것을 넘어, 어떤 개념을 떠올렸고 어디서 막혔는지 '사고 노드' 단위로 기록합니다.",
            iconName: "brain.head.profile",
            color: PharTheme.ColorToken.accentBlue
        ),
        PharAppGuideStep(
            title: "실시간 인강 브라우저",
            description: "노트 위에 인강 창을 띄워 필요한 부분을 즉시 캡처하고, 강의 내용을 사고 노드와 연결할 수 있습니다.",
            iconName: "play.rectangle.on.rectangle",
            color: PharTheme.ColorToken.accentMint
        ),
        PharAppGuideStep(
            title: "AI 오디오 요약 및 텍스트",
            description: "강의나 목소리를 녹음하면 AI가 핵심을 요약해주고, GoodNotes 스타일의 텍스트 상자로 깔끔하게 정리하세요.",
            iconName: "sparkles",
            color: PharTheme.ColorToken.accentButter
        ),
        PharAppGuideStep(
            title: "메타인지 BrainTree",
            description: "수집된 사고 데이터를 바탕으로 나의 실력을 시각화합니다. 어떤 노드가 약점인지 한눈에 파악하고 교정하세요.",
            iconName: "network",
            color: PharTheme.ColorToken.accentCoral
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Pharnote 사용 가이드")
                    .font(PharTypography.sectionTitle)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Content
            TabView(selection: $currentStep) {
                ForEach(0..<steps.count, id: \.self) { index in
                    guideStepPage(steps[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Footer
            VStack(spacing: 16) {
                // Page Indicator
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(currentStep == index ? steps[currentStep].color : PharTheme.ColorToken.borderSoft)
                            .frame(width: 8, height: 8)
                            .scaleEffect(currentStep == index ? 1.2 : 1.0)
                            .animation(.spring(), value: currentStep)
                    }
                }
                
                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button {
                            withAnimation {
                                currentStep -= 1
                            }
                        } label: {
                            Text("이전")
                                .font(PharTypography.bodyStrong)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(PharTheme.ColorToken.surfaceSecondary)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button {
                        if currentStep < steps.count - 1 {
                            withAnimation {
                                currentStep += 1
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(currentStep == steps.count - 1 ? "시작하기" : "다음")
                            .font(PharTypography.bodyStrong)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(steps[currentStep].color)
                            .cornerRadius(12)
                            .shadow(color: steps[currentStep].color.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color.white)
        }
        .frame(width: 420, height: 560)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    private func guideStepPage(_ step: PharAppGuideStep) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(step.color.opacity(0.1))
                    .frame(width: 160, height: 160)
                
                Image(systemName: step.iconName)
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(step.color)
                    .shadow(color: step.color.opacity(0.2), radius: 10, x: 0, y: 5)
            }
            .padding(.top, 20)
            
            VStack(spacing: 12) {
                Text(step.title)
                    .font(PharTypography.heroSubtitle)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    .multilineTextAlignment(.center)
                
                Text(step.description)
                    .font(PharTypography.body)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
            }
            
            Spacer()
        }
        .padding(.top, 20)
    }
}

#Preview {
    PharAppGuideView()
}
