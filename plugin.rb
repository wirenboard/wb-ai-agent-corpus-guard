# frozen_string_literal: true

# name: wb-ai-agent-corpus-guard
# about: Не даёт случайно снять базу знаний с живого ИИ-агента: пустой список файлов при сохранении больше не стирает корпус, а смена нарезки у включённого агента запрещена
# version: 1.0.0
# authors: Wiren Board
# url: https://github.com/wirenboard/wb-ai-agent-corpus-guard
# required_version: 2026.7.0

enabled_site_setting :wb_ai_agent_corpus_guard_enabled

module ::WbAiAgentCorpusGuard
  PLUGIN_NAME = "wb-ai-agent-corpus-guard"

  def self.enabled?
    SiteSetting.wb_ai_agent_corpus_guard_enabled
  end

  # защищаем только живого агента, у которого прямо сейчас есть привязанные файлы
  def self.protected?(target)
    return false if !enabled?
    return false if !target.is_a?(AiAgent)
    return false if !target.enabled?

    target.uploads.exists?
  end

  def self.log_kept(agent, kept)
    Rails.logger.warn(
      "[#{PLUGIN_NAME}] у включённого агента #{agent.id} «#{agent.name}» пришёл пустой список " \
        "файлов базы знаний; корпус не тронут, файлов оставлено: #{kept}",
    )
    UserHistory.create!(
      action: UserHistory.actions[:custom_staff],
      custom_type: "wb_corpus_guard_kept_uploads",
      acting_user_id: Discourse.system_user.id,
      subject: agent.name.to_s[0, 100],
      details:
        "agent_id: #{agent.id}\nфайлов оставлено: #{kept}\n" \
          "причина: сохранение включённого агента с пустым списком файлов базы знаний",
    )
  rescue StandardError => e
    Rails.logger.warn("[#{PLUGIN_NAME}] не удалось записать в журнал действий: #{e.message}")
  end
end

after_initialize do
  next unless defined?(RagDocumentFragment) && defined?(AiAgent)

  require_relative "lib/wb_ai_agent_corpus_guard/fragment_extension"
  require_relative "lib/wb_ai_agent_corpus_guard/agent_extension"

  # через этот метод идут все пути снятия файлов: админка, консоль, наши скрипты
  RagDocumentFragment.singleton_class.prepend(WbAiAgentCorpusGuard::FragmentExtension)

  AiAgent.include(WbAiAgentCorpusGuard::AgentExtension)
  AiAgent.validate(:wb_corpus_guard_keeps_chunking)
end
