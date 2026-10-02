# frozen_string_literal: true

module ::WbAiAgentCorpusGuard
  # Штатный `RagDocumentFragment.update_target_uploads` трактует пустой список файлов как «снять всё»:
  #
  #   if upload_ids.blank?
  #     RagDocumentFragment.where(target: target).destroy_all
  #     UploadReference.where(target: target).destroy_all
  #
  # А список собирается из параметров запроса: `ai_agent_params[:rag_uploads].to_a`. Если поля
  # `rag_uploads` в запросе нет вовсе — например, админка сохраняет агента из формы, где этого поля
  # не было, — список выходит пустым, и корпус живого бота пропадает молча, вместе с фрагментами.
  # Так 02.10.2026 живой бот остался без базы знаний на пять часов.
  #
  # Пустой список для включённого агента, у которого файлы есть, считаем ошибкой, а не приказом:
  # файлы остаются, в журнал действий пишется запись (штатный логгер изменение файлов не отражает).
  module FragmentExtension
    def update_target_uploads(target, upload_ids)
      if upload_ids.blank? && WbAiAgentCorpusGuard.protected?(target)
        WbAiAgentCorpusGuard.log_kept(target, target.uploads.count)
        return
      end

      super
    end
  end
end
