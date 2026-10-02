# frozen_string_literal: true

module ::WbAiAgentCorpusGuard
  # Вторая ловушка того же класса — `AiAgent#regenerate_rag_fragments`:
  #
  #   if rag_chunk_tokens_changed? || rag_chunk_overlap_tokens_changed?
  #     RagDocumentFragment.where(target: self).delete_all
  #
  # Удаляет фрагменты и НЕ пересобирает их: у живого агента после такой правки корпус пустой, а
  # пересчёт эмбеддингов — часы и деньги. Нарезку меняют на отключённой копии и переключают свапом.
  module AgentExtension
    def wb_corpus_guard_keeps_chunking
      return if !WbAiAgentCorpusGuard.enabled?
      return if new_record?
      return if !(rag_chunk_tokens_changed? || rag_chunk_overlap_tokens_changed?)
      # защищаем и тот случай, когда агента выключают той же правкой
      return if !(enabled? || enabled_in_database)
      return if !uploads.exists?

      errors.add(:base, I18n.t("wb_ai_agent_corpus_guard.chunking_locked"))
    end
  end
end
