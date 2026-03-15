export type ReviewCorrectness = 'correct' | 'incorrect' | 'unsure';

export type ReviewQuestionResponseType = 'single_select' | 'multi_select' | 'free_text';

export type ReviewTimeBand = 'very_fast' | 'fast' | 'normal' | 'slow' | 'very_slow';

export interface CanonicalStep {
  step_id: string;
  title_ko: string;
  summary_ko: string;
  expected_actions_ko: string[];
}

export interface FailureNode {
  node_id: string;
  label_ko: string;
  canonical_step_id: string;
  description_ko: string;
  what_to_do_next_ko: string[];
  symptom_tags: string[];
  future_braintree_node_id?: string | null;
}

export interface ReviewOption {
  option_id: string;
  label_ko: string;
  symptom_tags: string[];
}

export interface ReviewQuestion {
  question_id: string;
  prompt_ko: string;
  help_text_ko?: string;
  response_type: ReviewQuestionResponseType;
  options?: ReviewOption[];
  placeholder_ko?: string;
  required?: boolean;
}

export interface DiagnosisRuleAnswerMatch {
  question_id: string;
  option_ids: string[];
  match: 'any' | 'all';
}

export interface DiagnosisRule {
  rule_id: string;
  failure_node_id: string;
  step_ids: string[];
  weight: number;
  description_ko: string;
  conditions: {
    correctness?: ReviewCorrectness | 'any';
    confidence_min?: number;
    confidence_max?: number;
    time_band?: ReviewTimeBand | 'any';
    answer_matches?: DiagnosisRuleAnswerMatch[];
    reflection_keywords_any?: string[];
  };
}

export interface ItemReviewSpec {
  item_id: string;
  year: number;
  section: string;
  score: number;
  question_type: string;
  topic_tags: string[];
  display_title_ko: string;
  item_summary_ko: string;
  content_status: 'placeholder' | 'authored';
  expected_time_seconds: number;
  canonical_path: CanonicalStep[];
  failure_nodes: FailureNode[];
  review_questions: ReviewQuestion[];
  diagnosis_rules: DiagnosisRule[];
}

export interface UserReviewSubmission {
  item_id: string;
  correctness: ReviewCorrectness;
  confidence: number;
  time_spent_seconds: number;
  selected_option_answers: Record<string, string[]>;
  text_answers: Record<string, string>;
  free_text_reflection?: string;
}

export interface DiagnosisRuleTrace {
  rule_id: string;
  failure_node_id: string;
  failure_label_ko: string;
  matched: boolean;
  score_contribution: number;
  matched_conditions: string[];
  unmet_conditions: string[];
  why_ko: string;
}

export interface DiagnosisCandidate {
  failure_node_id: string;
  label_ko: string;
  score: number;
  canonical_step_ids: string[];
  supporting_rule_ids: string[];
  supporting_symptoms: string[];
  description_ko: string;
  what_to_do_next_ko: string[];
}

export interface DiagnosisResult {
  item_id: string;
  primary_failure_node: DiagnosisCandidate | null;
  secondary_failure_nodes: DiagnosisCandidate[];
  matched_canonical_steps: CanonicalStep[];
  confidence_score: number;
  supporting_symptoms: string[];
  short_explanation_ko: string;
  next_steps_ko: string[];
  rule_trace: DiagnosisRuleTrace[];
}
