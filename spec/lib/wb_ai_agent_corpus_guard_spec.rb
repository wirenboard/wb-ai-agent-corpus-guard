# frozen_string_literal: true

RSpec.describe WbAiAgentCorpusGuard do
  fab!(:cloudflare_embedding_def)
  fab!(:live_agent) { Fabricate(:ai_agent, enabled: true) }
  fab!(:staging_agent) { Fabricate(:ai_agent, enabled: false) }

  before do
    enable_current_plugin
    SiteSetting.ai_embeddings_selected_model = cloudflare_embedding_def.id
    SiteSetting.ai_embeddings_enabled = true
    SiteSetting.authorized_extensions = "md|txt|pdf"
  end

  # файл корпуса, привязанный к агенту, и один фрагмент от него
  def attach_corpus(target)
    upload = Fabricate(:upload, original_filename: "corpus.md", extension: "md")
    UploadReference.create!(target: target, upload: upload)
    RagDocumentFragment.create!(
      target: target,
      upload: upload,
      fragment: "текст корпуса",
      fragment_number: 1,
    )
    upload
  end

  def counts(target)
    [UploadReference.where(target: target).count, RagDocumentFragment.where(target: target).count]
  end

  it "не снимает корпус живого агента, когда список файлов пришёл пустым" do
    attach_corpus(live_agent)
    RagDocumentFragment.update_target_uploads(live_agent, [])
    expect(counts(live_agent)).to eq([1, 1])
  end

  it "пишет в журнал действий, что корпус не тронут" do
    attach_corpus(live_agent)
    expect { RagDocumentFragment.update_target_uploads(live_agent, []) }.to change {
      UserHistory.where(custom_type: "wb_corpus_guard_kept_uploads").count
    }.by(1)
    entry = UserHistory.where(custom_type: "wb_corpus_guard_kept_uploads").last
    expect(entry.details).to include("agent_id: #{live_agent.id}")
  end

  it "с выключенным предохранителем снимает корпус, как штатный Discourse" do
    SiteSetting.wb_ai_agent_corpus_guard_enabled = false
    attach_corpus(live_agent)
    RagDocumentFragment.update_target_uploads(live_agent, [])
    expect(counts(live_agent)).to eq([0, 0])
  end

  it "не мешает снимать корпус у выключенного агента: staging под защиту не попадает" do
    attach_corpus(staging_agent)
    RagDocumentFragment.update_target_uploads(staging_agent, [])
    expect(counts(staging_agent)).to eq([0, 0])
  end

  it "пропускает непустой список: подмена файла работает как обычно" do
    attach_corpus(live_agent)
    fresh = Fabricate(:upload, original_filename: "corpus_new.md", extension: "md")
    RagDocumentFragment.update_target_uploads(live_agent, [fresh.id])
    expect(UploadReference.where(target: live_agent).pluck(:upload_id)).to eq([fresh.id])
    expect(RagDocumentFragment.where(target: live_agent).count).to eq(0)
  end

  describe "смена нарезки" do
    it "отклоняется у живого агента с файлами, фрагменты целы" do
      attach_corpus(live_agent)
      expect(live_agent.update(rag_chunk_tokens: 500)).to eq(false)
      expect(live_agent.errors.full_messages.join).to include(
        I18n.t("wb_ai_agent_corpus_guard.chunking_locked"),
      )
      expect(counts(live_agent)).to eq([1, 1])
    end

    it "отклоняется и когда агента выключают той же правкой" do
      attach_corpus(live_agent)
      expect(live_agent.update(enabled: false, rag_chunk_overlap_tokens: 40)).to eq(false)
    end

    it "разрешена у выключенного агента" do
      attach_corpus(staging_agent)
      expect(staging_agent.update(rag_chunk_tokens: 500)).to eq(true)
    end

    it "не мешает обычной правке живого агента" do
      attach_corpus(live_agent)
      expect(live_agent.update(system_prompt: "новый промпт")).to eq(true)
      expect(counts(live_agent)).to eq([1, 1])
    end
  end
end
