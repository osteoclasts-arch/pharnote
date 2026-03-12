import type { FormEvent } from 'react';
import { useEffect, useState } from 'react';
import { REVIEW_SPECS_2022_COMMON_4PT } from './data/reviewSpecs';
import { diagnoseSubmission, deriveTimeBand } from './engine/diagnosisEngine';
import type {
  DiagnosisResult,
  ItemReviewSpec,
  ReviewCorrectness,
  UserReviewSubmission,
} from './types';

type ScenarioPreset = {
  preset_id: string;
  label_ko: string;
  description_ko: string;
  item_id: string;
  correctness: ReviewCorrectness;
  confidence: number;
  time_spent_minutes: number;
  selected_option_answers: Record<string, string[]>;
  free_text_reflection?: string;
};

const SCENARIO_PRESETS: ScenarioPreset[] = [
  {
    preset_id: 'a_split_skip',
    label_ko: 'A | 분기점 놓침',
    description_ko: '케이스를 안 나누고 한 식으로 밀어붙인 오답 시나리오',
    item_id: '2022-common-4pt-a',
    correctness: 'incorrect',
    confidence: 4,
    time_spent_minutes: 5,
    selected_option_answers: {
      entry_point: ['single_expression_push'],
      casework_symptoms: ['missed_switch_point', 'boundary_unstable'],
      split_memory: ['never_split'],
      verification: ['checked_only_final'],
    },
    free_text_reflection: '케이스를 나눠야 하는데 그냥 한 번에 정리하려다 막혔다.',
  },
  {
    preset_id: 'b_index_shift',
    label_ko: 'B | 인덱스 검산 누락',
    description_ko: '규칙은 잡았지만 n, n+1과 초항 반영이 흔들린 시나리오',
    item_id: '2022-common-4pt-b',
    correctness: 'incorrect',
    confidence: 3,
    time_spent_minutes: 4,
    selected_option_answers: {
      first_move: ['transform_relation'],
      stuck_signals: ['index_shift_confusion', 'initial_value_unstable'],
      finish_state: ['late_algebra'],
      index_check: ['didnt_check_index'],
    },
    free_text_reflection: '마지막에 초항을 어디서 반영했는지 헷갈렸다.',
  },
  {
    preset_id: 'c_double_count',
    label_ko: 'C | 중복 계산 누수',
    description_ko: '조건은 봤지만 같은 경우를 두 번 빼는 오답 시나리오',
    item_id: '2022-common-4pt-c',
    correctness: 'incorrect',
    confidence: 2,
    time_spent_minutes: 4,
    selected_option_answers: {
      sample_space_start: ['total_then_complement'],
      restriction_signals: ['cases_overlap', 'double_subtraction', 'no_small_case_check'],
      counting_route: ['counted_total_then_filtered'],
      final_check: ['no_validation'],
    },
    free_text_reflection: '전체에서 빼는 식으로 가다가 같은 경우를 두 번 뺀 것 같다.',
  },
];

const CORRECTNESS_OPTIONS: Array<{ value: ReviewCorrectness; label: string }> = [
  { value: 'correct', label: '맞음' },
  { value: 'incorrect', label: '틀림' },
  { value: 'unsure', label: '잘 모르겠음' },
];

function buildInitialSelectedAnswers(spec: ItemReviewSpec): Record<string, string[]> {
  return spec.review_questions
    .filter((question) => question.response_type !== 'free_text')
    .reduce<Record<string, string[]>>((acc, question) => {
      acc[question.question_id] = [];
      return acc;
    }, {});
}

function buildInitialTextAnswers(spec: ItemReviewSpec): Record<string, string> {
  return spec.review_questions
    .filter((question) => question.response_type === 'free_text')
    .reduce<Record<string, string>>((acc, question) => {
      acc[question.question_id] = '';
      return acc;
    }, {});
}

export default function App() {
  const [selectedItemId, setSelectedItemId] = useState(REVIEW_SPECS_2022_COMMON_4PT[0].item_id);
  const selectedSpec =
    REVIEW_SPECS_2022_COMMON_4PT.find((spec) => spec.item_id === selectedItemId) || REVIEW_SPECS_2022_COMMON_4PT[0];

  const [correctness, setCorrectness] = useState<ReviewCorrectness>('incorrect');
  const [confidence, setConfidence] = useState(3);
  const [timeSpentMinutes, setTimeSpentMinutes] = useState('4');
  const [selectedOptionAnswers, setSelectedOptionAnswers] = useState<Record<string, string[]>>(
    buildInitialSelectedAnswers(selectedSpec)
  );
  const [textAnswers, setTextAnswers] = useState<Record<string, string>>(buildInitialTextAnswers(selectedSpec));
  const [freeTextReflection, setFreeTextReflection] = useState('');
  const [validationError, setValidationError] = useState('');
  const [result, setResult] = useState<DiagnosisResult | null>(null);

  useEffect(() => {
    setCorrectness('incorrect');
    setConfidence(3);
    setTimeSpentMinutes('4');
    setSelectedOptionAnswers(buildInitialSelectedAnswers(selectedSpec));
    setTextAnswers(buildInitialTextAnswers(selectedSpec));
    setFreeTextReflection('');
    setValidationError('');
    setResult(null);
  }, [selectedSpec]);

  const matchingPresets = SCENARIO_PRESETS.filter((preset) => preset.item_id === selectedSpec.item_id);
  const derivedTimeBand = deriveTimeBand(Math.round(Number(timeSpentMinutes || 0) * 60), selectedSpec.expected_time_seconds);

  function updateSingleAnswer(questionId: string, optionId: string) {
    setSelectedOptionAnswers((current) => ({
      ...current,
      [questionId]: [optionId],
    }));
  }

  function updateMultiAnswer(questionId: string, optionId: string, checked: boolean) {
    setSelectedOptionAnswers((current) => {
      const previous = current[questionId] || [];
      const next = checked
        ? [...previous, optionId]
        : previous.filter((existing) => existing !== optionId);

      return {
        ...current,
        [questionId]: Array.from(new Set(next)),
      };
    });
  }

  function applyScenario(preset: ScenarioPreset) {
    setCorrectness(preset.correctness);
    setConfidence(preset.confidence);
    setTimeSpentMinutes(String(preset.time_spent_minutes));
    setSelectedOptionAnswers({
      ...buildInitialSelectedAnswers(selectedSpec),
      ...preset.selected_option_answers,
    });
    setFreeTextReflection(preset.free_text_reflection || '');
    setValidationError('');
    setResult(null);
  }

  function buildSubmission(): UserReviewSubmission | null {
    for (const question of selectedSpec.review_questions) {
      if (!question.required) continue;

      if (question.response_type === 'free_text') {
        const value = textAnswers[question.question_id]?.trim();
        if (!value) {
          setValidationError(`"${question.prompt_ko}" 문항에 응답이 필요합니다.`);
          return null;
        }
      } else {
        const value = selectedOptionAnswers[question.question_id] || [];
        if (!value.length) {
          setValidationError(`"${question.prompt_ko}" 문항에서 선택이 필요합니다.`);
          return null;
        }
      }
    }

    const numericMinutes = Number(timeSpentMinutes);
    if (!Number.isFinite(numericMinutes) || numericMinutes <= 0) {
      setValidationError('풀이 시간은 1분 이상으로 입력해 주세요.');
      return null;
    }

    setValidationError('');

    return {
      item_id: selectedSpec.item_id,
      correctness,
      confidence,
      time_spent_seconds: Math.round(numericMinutes * 60),
      selected_option_answers: selectedOptionAnswers,
      text_answers: textAnswers,
      free_text_reflection: freeTextReflection.trim(),
    };
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const submission = buildSubmission();
    if (!submission) return;

    setResult(diagnoseSubmission(selectedSpec, submission));
  }

  return (
    <div className="app-shell">
      <header className="hero-card">
        <div className="hero-copy">
          <span className="eyebrow">PharNote CSAT Review MVP</span>
          <h1>2022 수능 공통 4점 전용 메타인지 리뷰</h1>
          <p>
            생성형 진단을 과장하지 않고, 사전 저술된 문항 스펙과 구조화된 복기 입력만으로 막힘 지점을 좁히는 MVP다.
          </p>
        </div>
        <div className="hero-side">
          <div className="meta-pill">{selectedSpec.year} · {selectedSpec.section} · {selectedSpec.score}점</div>
          <div className="meta-pill subtle">{selectedSpec.content_status === 'placeholder' ? 'placeholder authored spec' : 'authored spec'}</div>
          <div className="meta-pill subtle">예상 시간 {Math.round(selectedSpec.expected_time_seconds / 60)}분 30초 내외</div>
        </div>
      </header>

      <main className="workspace">
        <section className="panel form-panel">
          <div className="panel-header">
            <div>
              <p className="section-label">1. Spec 선택</p>
              <h2>아이템 리뷰 입력</h2>
            </div>
            <select
              className="select-input"
              value={selectedItemId}
              onChange={(event) => setSelectedItemId(event.target.value)}
            >
              {REVIEW_SPECS_2022_COMMON_4PT.map((spec) => (
                <option key={spec.item_id} value={spec.item_id}>
                  {spec.display_title_ko}
                </option>
              ))}
            </select>
          </div>

          <div className="spec-summary">
            <p>{selectedSpec.item_summary_ko}</p>
            <div className="tag-row">
              {selectedSpec.topic_tags.map((tag) => (
                <span key={tag} className="tag-chip">
                  {tag}
                </span>
              ))}
            </div>
          </div>

          <div className="canonical-card">
            <p className="section-label">Authored canonical path</p>
            <ol className="canonical-list">
              {selectedSpec.canonical_path.map((step, index) => {
                const matched = result?.matched_canonical_steps.some((matchedStep) => matchedStep.step_id === step.step_id);
                return (
                  <li key={step.step_id} className={matched ? 'matched' : ''}>
                    <span className="step-number">{index + 1}</span>
                    <div>
                      <strong>{step.title_ko}</strong>
                      <p>{step.summary_ko}</p>
                    </div>
                  </li>
                );
              })}
            </ol>
          </div>

          <div className="preset-card">
            <p className="section-label">시나리오 프리셋</p>
            <div className="preset-list">
              {matchingPresets.map((preset) => (
                <button key={preset.preset_id} type="button" className="preset-button" onClick={() => applyScenario(preset)}>
                  <strong>{preset.label_ko}</strong>
                  <span>{preset.description_ko}</span>
                </button>
              ))}
            </div>
          </div>

          <form className="review-form" onSubmit={handleSubmit}>
            <div className="field-grid">
              <fieldset className="field-card">
                <legend>정답 여부</legend>
                <div className="choice-row">
                  {CORRECTNESS_OPTIONS.map((option) => (
                    <label key={option.value} className={correctness === option.value ? 'toggle-chip active' : 'toggle-chip'}>
                      <input
                        type="radio"
                        name="correctness"
                        value={option.value}
                        checked={correctness === option.value}
                        onChange={() => setCorrectness(option.value)}
                      />
                      {option.label}
                    </label>
                  ))}
                </div>
              </fieldset>

              <fieldset className="field-card">
                <legend>확신도</legend>
                <div className="choice-row compact">
                  {[1, 2, 3, 4, 5].map((value) => (
                    <button
                      key={value}
                      type="button"
                      className={confidence === value ? 'score-button active' : 'score-button'}
                      onClick={() => setConfidence(value)}
                    >
                      {value}
                    </button>
                  ))}
                </div>
                <small>1은 거의 감, 5는 꽤 확신</small>
              </fieldset>

              <label className="field-card">
                <span>풀이 시간(분)</span>
                <input
                  className="text-input"
                  type="number"
                  min="1"
                  step="0.5"
                  value={timeSpentMinutes}
                  onChange={(event) => setTimeSpentMinutes(event.target.value)}
                />
                <small>현재 시간대 해석: {derivedTimeBand}</small>
              </label>
            </div>

            {selectedSpec.review_questions.map((question) => (
              <section key={question.question_id} className="question-card">
                <div className="question-header">
                  <div>
                    <h3>{question.prompt_ko}</h3>
                    {question.help_text_ko ? <p>{question.help_text_ko}</p> : null}
                  </div>
                  <span className="question-badge">{question.response_type}</span>
                </div>

                {question.response_type === 'single_select' ? (
                  <div className="choice-column">
                    {(question.options || []).map((option) => (
                      <label
                        key={option.option_id}
                        className={
                          selectedOptionAnswers[question.question_id]?.includes(option.option_id)
                            ? 'answer-option active'
                            : 'answer-option'
                        }
                      >
                        <input
                          type="radio"
                          name={question.question_id}
                          checked={selectedOptionAnswers[question.question_id]?.includes(option.option_id) || false}
                          onChange={() => updateSingleAnswer(question.question_id, option.option_id)}
                        />
                        <span>{option.label_ko}</span>
                      </label>
                    ))}
                  </div>
                ) : null}

                {question.response_type === 'multi_select' ? (
                  <div className="choice-column">
                    {(question.options || []).map((option) => (
                      <label
                        key={option.option_id}
                        className={
                          selectedOptionAnswers[question.question_id]?.includes(option.option_id)
                            ? 'answer-option active'
                            : 'answer-option'
                        }
                      >
                        <input
                          type="checkbox"
                          checked={selectedOptionAnswers[question.question_id]?.includes(option.option_id) || false}
                          onChange={(event) => updateMultiAnswer(question.question_id, option.option_id, event.target.checked)}
                        />
                        <span>{option.label_ko}</span>
                      </label>
                    ))}
                  </div>
                ) : null}

                {question.response_type === 'free_text' ? (
                  <textarea
                    className="textarea-input"
                    placeholder={question.placeholder_ko || '짧게 적어줘'}
                    value={textAnswers[question.question_id] || ''}
                    onChange={(event) =>
                      setTextAnswers((current) => ({
                        ...current,
                        [question.question_id]: event.target.value,
                      }))
                    }
                  />
                ) : null}
              </section>
            ))}

            <label className="question-card">
              <div className="question-header">
                <div>
                  <h3>짧은 복기 한 줄</h3>
                  <p>선택지로 안 잡히는 느낌이 있으면 한 줄만 적어도 된다.</p>
                </div>
                <span className="question-badge">optional</span>
              </div>
              <textarea
                className="textarea-input"
                placeholder="예: 케이스를 나누는 기준은 알겠는데 마지막 경계값에서 흔들렸다."
                value={freeTextReflection}
                onChange={(event) => setFreeTextReflection(event.target.value)}
              />
            </label>

            {validationError ? <p className="validation-error">{validationError}</p> : null}

            <div className="submit-row">
              <button type="submit" className="primary-button">
                막힘 진단 보기
              </button>
              <span className="submit-note">진단은 rule trace와 함께 노출된다.</span>
            </div>
          </form>
        </section>

        <section className="panel result-panel">
          <div className="panel-header">
            <div>
              <p className="section-label">2. Diagnosis</p>
              <h2>진단 결과</h2>
            </div>
            {result ? <div className="confidence-pill">confidence {Math.round(result.confidence_score * 100)}%</div> : null}
          </div>

          {!result ? (
            <div className="empty-state">
              <strong>아직 진단 전</strong>
              <p>왼쪽 입력을 채우고 제출하면, 어떤 canonical step에서 끊겼는지와 어떤 규칙이 그 판단을 만들었는지 바로 볼 수 있다.</p>
            </div>
          ) : (
            <>
              <div className="result-card highlight">
                <p className="section-label">Main blockage point</p>
                <h3>{result.primary_failure_node?.label_ko || '신호 부족으로 자동 판정 보류'}</h3>
                <p>{result.short_explanation_ko}</p>
              </div>

              <div className="result-grid">
                <div className="result-card">
                  <p className="section-label">Likely step break</p>
                  <ul className="bullet-list">
                    {result.matched_canonical_steps.length ? (
                      result.matched_canonical_steps.map((step) => (
                        <li key={step.step_id}>
                          <strong>{step.title_ko}</strong>
                          <span>{step.summary_ko}</span>
                        </li>
                      ))
                    ) : (
                      <li>
                        <strong>명확한 단계 미확정</strong>
                        <span>현재 입력만으로는 특정 단계로 강하게 묶기 어렵다.</span>
                      </li>
                    )}
                  </ul>
                </div>

                <div className="result-card">
                  <p className="section-label">Supporting symptoms</p>
                  <ul className="bullet-list">
                    {result.supporting_symptoms.length ? (
                      result.supporting_symptoms.map((symptom) => (
                        <li key={symptom}>
                          <strong>{symptom}</strong>
                          <span>선택한 복기 신호에서 직접 잡힌 증상</span>
                        </li>
                      ))
                    ) : (
                      <li>
                        <strong>증상 신호 부족</strong>
                        <span>규칙은 매칭됐지만 선택지 기반 증상이 충분히 모이지 않았다.</span>
                      </li>
                    )}
                  </ul>
                </div>
              </div>

              <div className="result-card">
                <p className="section-label">What to do next</p>
                <ul className="bullet-list">
                  {(result.next_steps_ko.length ? result.next_steps_ko : ['추가 복기 입력이 필요하다']).map((step) => (
                    <li key={step}>
                      <strong>{step}</strong>
                      <span>다음 풀이 직후 바로 적용할 행동 지시</span>
                    </li>
                  ))}
                </ul>
              </div>

              {result.secondary_failure_nodes.length ? (
                <div className="result-card">
                  <p className="section-label">Secondary candidates</p>
                  <div className="secondary-list">
                    {result.secondary_failure_nodes.map((candidate) => (
                      <div key={candidate.failure_node_id} className="secondary-item">
                        <strong>{candidate.label_ko}</strong>
                        <span>score {candidate.score.toFixed(1)}</span>
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}

              <details className="trace-card" open>
                <summary>Rule trace</summary>
                <div className="trace-list">
                  {result.rule_trace.map((trace) => (
                    <article key={trace.rule_id} className={trace.matched ? 'trace-item matched' : 'trace-item'}>
                      <div className="trace-top">
                        <strong>{trace.failure_label_ko}</strong>
                        <span>
                          {trace.rule_id} · {trace.matched ? `+${trace.score_contribution}` : 'no match'}
                        </span>
                      </div>
                      <p>{trace.why_ko}</p>
                      {trace.matched_conditions.length ? (
                        <div className="trace-meta">
                          matched: {trace.matched_conditions.join(' / ')}
                        </div>
                      ) : null}
                      {trace.unmet_conditions.length ? (
                        <div className="trace-meta muted">
                          unmet: {trace.unmet_conditions.join(' / ')}
                        </div>
                      ) : null}
                    </article>
                  ))}
                </div>
              </details>
            </>
          )}
        </section>
      </main>
    </div>
  );
}
