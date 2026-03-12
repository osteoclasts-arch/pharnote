import type {
  CanonicalStep,
  DiagnosisCandidate,
  DiagnosisResult,
  DiagnosisRule,
  DiagnosisRuleAnswerMatch,
  DiagnosisRuleTrace,
  FailureNode,
  ItemReviewSpec,
  ReviewCorrectness,
  ReviewOption,
  ReviewTimeBand,
  UserReviewSubmission,
} from '../types';

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function deriveTimeBand(timeSpentSeconds: number, expectedTimeSeconds: number): ReviewTimeBand {
  const safeSeconds = Math.max(0, timeSpentSeconds);
  const baseline = Math.max(60, expectedTimeSeconds);
  const ratio = safeSeconds / baseline;

  if (ratio <= 0.45) return 'very_fast';
  if (ratio <= 0.75) return 'fast';
  if (ratio <= 1.3) return 'normal';
  if (ratio <= 1.8) return 'slow';
  return 'very_slow';
}

function buildFailureNodeMap(spec: ItemReviewSpec): Map<string, FailureNode> {
  return new Map(spec.failure_nodes.map((node) => [node.node_id, node]));
}

function buildCanonicalStepMap(spec: ItemReviewSpec): Map<string, CanonicalStep> {
  return new Map(spec.canonical_path.map((step) => [step.step_id, step]));
}

function buildOptionMap(spec: ItemReviewSpec): Map<string, ReviewOption> {
  const optionEntries = spec.review_questions.flatMap((question) =>
    (question.options || []).map((option) => [option.option_id, option] as const)
  );
  return new Map(optionEntries);
}

function matchesCorrectness(expected: DiagnosisRule['conditions']['correctness'], actual: ReviewCorrectness): boolean {
  if (!expected || expected === 'any') return true;
  return expected === actual;
}

function matchesConfidence(
  rule: DiagnosisRule,
  confidence: number,
  matchedConditions: string[],
  unmetConditions: string[]
) {
  const { confidence_min, confidence_max } = rule.conditions;

  if (typeof confidence_min === 'number') {
    if (confidence >= confidence_min) {
      matchedConditions.push(`confidence >= ${confidence_min}`);
    } else {
      unmetConditions.push(`confidence >= ${confidence_min}`);
    }
  }

  if (typeof confidence_max === 'number') {
    if (confidence <= confidence_max) {
      matchedConditions.push(`confidence <= ${confidence_max}`);
    } else {
      unmetConditions.push(`confidence <= ${confidence_max}`);
    }
  }
}

function describeAnswerMatch(
  match: DiagnosisRuleAnswerMatch,
  optionMap: Map<string, ReviewOption>
): string {
  const labels = match.option_ids.map((optionId) => optionMap.get(optionId)?.label_ko || optionId);
  return `${match.question_id} ${match.match === 'all' ? 'includes all of' : 'includes any of'} [${labels.join(', ')}]`;
}

function matchesAnswerRule(
  answerMatch: DiagnosisRuleAnswerMatch,
  submission: UserReviewSubmission,
  optionMap: Map<string, ReviewOption>
): { matched: boolean; description: string } {
  const selected = submission.selected_option_answers[answerMatch.question_id] || [];
  const matched =
    answerMatch.match === 'all'
      ? answerMatch.option_ids.every((optionId) => selected.includes(optionId))
      : answerMatch.option_ids.some((optionId) => selected.includes(optionId));

  return {
    matched,
    description: describeAnswerMatch(answerMatch, optionMap),
  };
}

function matchesReflectionKeywords(
  rule: DiagnosisRule,
  submission: UserReviewSubmission,
  matchedConditions: string[],
  unmetConditions: string[]
) {
  const keywords = rule.conditions.reflection_keywords_any;
  if (!keywords?.length) return;

  const reflection = `${submission.free_text_reflection || ''} ${Object.values(submission.text_answers).join(' ')}`
    .toLowerCase()
    .trim();

  if (!reflection) {
    unmetConditions.push(`reflection includes any of [${keywords.join(', ')}]`);
    return;
  }

  const found = keywords.find((keyword) => reflection.includes(keyword.toLowerCase()));
  if (found) {
    matchedConditions.push(`reflection includes "${found}"`);
  } else {
    unmetConditions.push(`reflection includes any of [${keywords.join(', ')}]`);
  }
}

function evaluateRule(
  rule: DiagnosisRule,
  spec: ItemReviewSpec,
  submission: UserReviewSubmission,
  timeBand: ReviewTimeBand,
  optionMap: Map<string, ReviewOption>,
  failureNodeMap: Map<string, FailureNode>
): DiagnosisRuleTrace {
  const matchedConditions: string[] = [];
  const unmetConditions: string[] = [];

  if (matchesCorrectness(rule.conditions.correctness, submission.correctness)) {
    if (rule.conditions.correctness && rule.conditions.correctness !== 'any') {
      matchedConditions.push(`correctness = ${rule.conditions.correctness}`);
    }
  } else {
    unmetConditions.push(`correctness = ${rule.conditions.correctness}`);
  }

  matchesConfidence(rule, submission.confidence, matchedConditions, unmetConditions);

  if (rule.conditions.time_band && rule.conditions.time_band !== 'any') {
    if (rule.conditions.time_band === timeBand) {
      matchedConditions.push(`time band = ${timeBand}`);
    } else {
      unmetConditions.push(`time band = ${rule.conditions.time_band}`);
    }
  }

  for (const answerMatch of rule.conditions.answer_matches || []) {
    const result = matchesAnswerRule(answerMatch, submission, optionMap);
    if (result.matched) {
      matchedConditions.push(result.description);
    } else {
      unmetConditions.push(result.description);
    }
  }

  matchesReflectionKeywords(rule, submission, matchedConditions, unmetConditions);

  const matched = unmetConditions.length === 0;
  const failureNode = failureNodeMap.get(rule.failure_node_id);

  return {
    rule_id: rule.rule_id,
    failure_node_id: rule.failure_node_id,
    failure_label_ko: failureNode?.label_ko || rule.failure_node_id,
    matched,
    score_contribution: matched ? rule.weight : 0,
    matched_conditions: matchedConditions,
    unmet_conditions: unmetConditions,
    why_ko: matched
      ? `${rule.description_ko}. 조건 ${matchedConditions.join(' + ')} 이 맞았다.`
      : `${rule.description_ko}. 불일치 조건: ${unmetConditions.join(' + ') || '없음'}.`,
  };
}

function collectSupportingSymptoms(
  submission: UserReviewSubmission,
  optionMap: Map<string, ReviewOption>,
  matchedRuleIds: Set<string>,
  ruleTrace: DiagnosisRuleTrace[],
  failureNodeId: string
) {
  const matchedTraces = ruleTrace.filter(
    (trace) => trace.failure_node_id === failureNodeId && trace.matched && matchedRuleIds.has(trace.rule_id)
  );

  const referencedLabels = new Set<string>();
  const matchedDescriptions = matchedTraces.flatMap((trace) => trace.matched_conditions);
  for (const questionAnswers of Object.values(submission.selected_option_answers)) {
    for (const optionId of questionAnswers) {
      const label = optionMap.get(optionId)?.label_ko;
      if (label && matchedDescriptions.some((description) => description.includes(label))) {
        referencedLabels.add(label);
      }
    }
  }
  return [...referencedLabels];
}

function buildCandidate(
  failureNode: FailureNode,
  score: number,
  stepIds: Set<string>,
  matchedRuleIds: Set<string>,
  supportingSymptoms: string[]
): DiagnosisCandidate {
  return {
    failure_node_id: failureNode.node_id,
    label_ko: failureNode.label_ko,
    score,
    canonical_step_ids: [...stepIds],
    supporting_rule_ids: [...matchedRuleIds],
    supporting_symptoms: supportingSymptoms,
    description_ko: failureNode.description_ko,
    what_to_do_next_ko: failureNode.what_to_do_next_ko,
  };
}

function calculateConfidenceScore(
  submission: UserReviewSubmission,
  primaryCandidate: DiagnosisCandidate | null,
  secondaryCandidates: DiagnosisCandidate[],
  matchedRuleCount: number
) {
  if (!primaryCandidate || primaryCandidate.score <= 0) return 0.18;

  const secondScore = secondaryCandidates[0]?.score || 0;
  const evidenceFactor = clamp(matchedRuleCount / 3, 0, 1);
  const separationFactor = primaryCandidate.score > 0 ? clamp((primaryCandidate.score - secondScore) / primaryCandidate.score, 0, 1) : 0;
  const certaintyPenalty = submission.correctness === 'unsure' ? 0.85 : 1;
  const confidencePenalty = submission.confidence <= 2 ? 0.92 : 1;

  return clamp((0.28 + 0.34 * evidenceFactor + 0.28 * separationFactor) * certaintyPenalty * confidencePenalty, 0.18, 0.91);
}

function buildFallbackResult(itemId: string, ruleTrace: DiagnosisRuleTrace[]): DiagnosisResult {
  return {
    item_id: itemId,
    primary_failure_node: null,
    secondary_failure_nodes: [],
    matched_canonical_steps: [],
    confidence_score: 0.18,
    supporting_symptoms: [],
    short_explanation_ko:
      '입력 신호만으로는 자동 진단을 강하게 걸기 어렵다. 이 MVP는 억지 판정보다 규칙 일치 여부를 우선하므로, 지금은 “신호 부족”으로 남긴다.',
    next_steps_ko: ['가장 막혔던 순간을 하나만 다시 고르기', '틀렸다면 어디서 방향이 바뀌었는지 한 문장으로 적기'],
    rule_trace: ruleTrace,
  };
}

export function diagnoseSubmission(spec: ItemReviewSpec, submission: UserReviewSubmission): DiagnosisResult {
  const failureNodeMap = buildFailureNodeMap(spec);
  const canonicalStepMap = buildCanonicalStepMap(spec);
  const optionMap = buildOptionMap(spec);
  const timeBand = deriveTimeBand(submission.time_spent_seconds, spec.expected_time_seconds);

  const ruleTrace = spec.diagnosis_rules.map((rule) =>
    evaluateRule(rule, spec, submission, timeBand, optionMap, failureNodeMap)
  );

  const scoreByNode = new Map<string, number>();
  const stepIdsByNode = new Map<string, Set<string>>();
  const matchedRuleIdsByNode = new Map<string, Set<string>>();

  for (const trace of ruleTrace) {
    if (!trace.matched || trace.score_contribution <= 0) continue;
    scoreByNode.set(trace.failure_node_id, (scoreByNode.get(trace.failure_node_id) || 0) + trace.score_contribution);
    if (!stepIdsByNode.has(trace.failure_node_id)) {
      stepIdsByNode.set(trace.failure_node_id, new Set<string>());
    }
    if (!matchedRuleIdsByNode.has(trace.failure_node_id)) {
      matchedRuleIdsByNode.set(trace.failure_node_id, new Set<string>());
    }

    const sourceRule = spec.diagnosis_rules.find((rule) => rule.rule_id === trace.rule_id);
    for (const stepId of sourceRule?.step_ids || []) {
      stepIdsByNode.get(trace.failure_node_id)?.add(stepId);
    }
    matchedRuleIdsByNode.get(trace.failure_node_id)?.add(trace.rule_id);
  }

  const rankedCandidates = [...scoreByNode.entries()]
    .map(([failureNodeId, score]) => {
      const failureNode = failureNodeMap.get(failureNodeId);
      if (!failureNode) return null;
      const stepIds = stepIdsByNode.get(failureNodeId) || new Set<string>([failureNode.canonical_step_id]);
      const matchedRuleIds = matchedRuleIdsByNode.get(failureNodeId) || new Set<string>();
      const supportingSymptoms = collectSupportingSymptoms(submission, optionMap, matchedRuleIds, ruleTrace, failureNodeId);
      return buildCandidate(failureNode, Number(score.toFixed(2)), stepIds, matchedRuleIds, supportingSymptoms);
    })
    .filter((candidate): candidate is DiagnosisCandidate => Boolean(candidate))
    .sort((left, right) => right.score - left.score);

  if (!rankedCandidates.length) {
    return buildFallbackResult(spec.item_id, ruleTrace);
  }

  const primaryCandidate = rankedCandidates[0];
  const secondaryCandidates = rankedCandidates.filter((candidate, index) => index > 0 && candidate.score >= primaryCandidate.score * 0.55);
  const matchedStepIds = new Set<string>(primaryCandidate.canonical_step_ids);
  if (!matchedStepIds.size) {
    matchedStepIds.add(failureNodeMap.get(primaryCandidate.failure_node_id)?.canonical_step_id || '');
  }

  const matchedSteps = spec.canonical_path.filter((step) => matchedStepIds.has(step.step_id));
  const matchedRuleCount = primaryCandidate.supporting_rule_ids.length;
  const confidenceScore = calculateConfidenceScore(submission, primaryCandidate, secondaryCandidates, matchedRuleCount);
  const supportingSymptoms = primaryCandidate.supporting_symptoms.length
    ? primaryCandidate.supporting_symptoms
    : primaryCandidate.supporting_rule_ids
        .map((ruleId) => spec.diagnosis_rules.find((rule) => rule.rule_id === ruleId)?.description_ko)
        .filter((value): value is string => Boolean(value))
        .slice(0, 2);

  const stepLabel = matchedSteps[0]?.title_ko || '해당 단계';
  const shortExplanation = supportingSymptoms.length
    ? `가장 가능성 높은 막힘은 "${primaryCandidate.label_ko}"이다. 응답에서 ${supportingSymptoms
        .slice(0, 2)
        .map((symptom) => `"${symptom}"`)
        .join(', ')} 신호가 함께 잡혀 ${stepLabel} 단계에서 끊겼을 가능성이 크다.`
    : `가장 가능성 높은 막힘은 "${primaryCandidate.label_ko}"이다. 규칙 일치 결과상 ${stepLabel} 단계에서 끊겼을 가능성이 가장 높게 나왔다.`;

  return {
    item_id: spec.item_id,
    primary_failure_node: primaryCandidate,
    secondary_failure_nodes: secondaryCandidates,
    matched_canonical_steps: matchedSteps,
    confidence_score: Number(confidenceScore.toFixed(2)),
    supporting_symptoms: supportingSymptoms,
    short_explanation_ko: shortExplanation,
    next_steps_ko: primaryCandidate.what_to_do_next_ko,
    rule_trace: ruleTrace,
  };
}
