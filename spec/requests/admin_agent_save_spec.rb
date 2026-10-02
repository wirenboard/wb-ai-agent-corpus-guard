# frozen_string_literal: true

# Воспроизведение случая 02.10.2026: правка агента из админки без поля rag_uploads снимала корпус.
RSpec.describe "сохранение ИИ-агента из админки", type: :request do
  fab!(:admin)
  fab!(:cloudflare_embedding_def)
  fab!(:agent) { Fabricate(:ai_agent, enabled: true) }

  before do
    enable_current_plugin
    SiteSetting.discourse_ai_enabled = true
    SiteSetting.ai_embeddings_selected_model = cloudflare_embedding_def.id
    SiteSetting.ai_embeddings_enabled = true
    SiteSetting.authorized_extensions = "md|txt|pdf"
    upload = Fabricate(:upload, original_filename: "corpus.md", extension: "md")
    UploadReference.create!(target: agent, upload: upload)
    RagDocumentFragment.create!(
      target: agent,
      upload: upload,
      fragment: "текст",
      fragment_number: 1,
    )
    sign_in(admin)
  end

  def save_without_uploads
    put "/admin/plugins/discourse-ai/ai-agents/#{agent.id}.json",
        params: {
          ai_agent: {
            system_prompt: "правка без поля файлов",
          },
        }
  end

  it "сохраняет правку и оставляет корпус на месте" do
    save_without_uploads
    expect(response.status).to eq(200)
    expect(agent.reload.system_prompt).to eq("правка без поля файлов")
    expect(UploadReference.where(target: agent).count).to eq(1)
    expect(RagDocumentFragment.where(target: agent).count).to eq(1)
  end

  it "без предохранителя корпус пропадает — так и ломалось" do
    SiteSetting.wb_ai_agent_corpus_guard_enabled = false
    save_without_uploads
    expect(response.status).to eq(200)
    expect(UploadReference.where(target: agent).count).to eq(0)
    expect(RagDocumentFragment.where(target: agent).count).to eq(0)
  end
end
