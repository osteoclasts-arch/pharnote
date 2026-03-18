import SwiftUI

struct AppGuideStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let systemImage: String
    let accentColor: Color
}

struct AppGuidePopupView: View {
    @Binding var isPresented: Bool
    @State private var currentStepIndex = 0
    
    let steps: [AppGuideStep] = [
        AppGuideStep(
            title: "Thinking Tracing의 시작",
            description: "단순히 맞고 틀리는 것을 넘어, 학생의 논리적 병목(Block)을 추적합니다. PharNote는 당신의 사고 과정을 데이터화합니다.",
            systemImage: "brain.head.profile",
            accentColor: PharTheme.ColorToken.accentBlue
        ),
        AppGuideStep(
            title: "스마트 레이어 캡처",
            description: "인강 판서나 문제 이미지를 탭 한 번으로 깨끗하게 추출하세요. 인강 모드에서 비디오 아이콘을 눌러 시작할 수 있습니다.",
            systemImage: "plus.viewfinder",
            accentColor: PharTheme.ColorToken.accentMint
        ),
        AppGuideStep(
            title: "사고과정 복기 (Review)",
            description: "문제 풀이 직후, 확신도와 '선택지 기반 사고 복기'를 통해 본인이 어디서 막혔는지 정밀하게 기록합니다.",
            systemImage: "arrow.counterclockwise.circle",
            accentColor: PharTheme.ColorToken.accentPeach
        ),
        AppGuideStep(
            title: "BrainTree 분석",
            description: "추적된 데이터를 바탕으로 인지 구조 지도를 그립니다. 어떤 노드(개념)에서 병목이 발생하는지 즉각적으로 시각화합니다.",
            systemImage: "tree",
            accentColor: PharTheme.ColorToken.accentButter
        ),
        AppGuideStep(
            title: "플로팅 인강 모드",
            description: "이제 인강 브라우저를 자유롭게 옮기고 고정할 수 있습니다. 필기 공간을 방해받지 않고 효율적으로 학습하세요.",
            systemImage: "video.fill",
            accentColor: PharTheme.ColorToken.heroBlueStart
        )
    ]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
            
            VStack(spacing: 0) {
                // 상단 진행 바
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule()
                            .fill(index <= currentStepIndex ? steps[currentStepIndex].accentColor : PharTheme.ColorToken.borderSoft)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // 컨텐츠 영역
                VStack(spacing: 32) {
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(steps[currentStepIndex].accentColor.opacity(0.12))
                            .frame(width: 160, height: 160)
                        
                        Image(systemName: steps[currentStepIndex].systemImage)
                            .font(.system(size: 80))
                            .foregroundColor(steps[currentStepIndex].accentColor)
                    }
                    
                    VStack(spacing: 16) {
                        Text(steps[currentStepIndex].title)
                            .font(PharTypography.heroDisplay)
                            .multilineTextAlignment(.center)
                        
                        Text(steps[currentStepIndex].description)
                            .font(PharTypography.body)
                            .foregroundColor(PharTheme.ColorToken.inkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .lineSpacing(4)
                    }
                    
                    Spacer()
                }
                .frame(height: 400)
                
                // 하단 버튼
                HStack(spacing: 12) {
                    if currentStepIndex > 0 {
                        Button {
                            withAnimation { currentStepIndex -= 1 }
                        } label: {
                            Text("이전")
                                .font(PharTypography.bodyStrong)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(PharTheme.ColorToken.surfaceSecondary)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button {
                        if currentStepIndex < steps.count - 1 {
                            withAnimation { currentStepIndex += 1 }
                        } else {
                            isPresented = false
                        }
                    } label: {
                        Text(currentStepIndex == steps.count - 1 ? "시작하기" : "다음")
                            .font(PharTypography.bodyStrong)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(steps[currentStepIndex].accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
            .frame(width: 420)
            .background(Color.white)
            .cornerRadius(PharTheme.CornerRadius.large)
            .shadow(color: Color.black.opacity(0.15), radius: 30, x: 0, y: 15)
            .padding(40)
        }
    }
}
