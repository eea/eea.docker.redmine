if Rails.env.test?
  # Redmine 6.1 expects advisory-lock helpers in Issue nested set operations.
  # Some runtime images do not include with_advisory_lock; provide a safe no-op fallback for tests.
  unless ActiveRecord::Base.respond_to?(:with_advisory_lock!)
    class << ActiveRecord::Base
      def with_advisory_lock!(_lock_name = nil, **_options)
        return yield if block_given?
        true
      end
    end
  end

  # Keep plugin tests deterministic/offline by avoiding external LLM calls.
  # This only affects test env and only when a real provider would otherwise be used.
  module RedmineAiHelperTestFakeLlm
    Response = Struct.new(:content)

    class Chat
      def initialize
        @messages = []
      end

      def add_message(role:, content:)
        @messages << { role: role, content: content }
        self
      end

      def with_instructions(_instructions)
        self
      end

      def with_temperature(_temperature)
        self
      end

      def on_end_message(_callback = nil, &block)
        @on_end_message = _callback || block
        self
      end

      def ask(content, **_options)
        payload = case content
        when /"generate_steps_required"/
          { goal: "Test goal", generate_steps_required: false }.to_json
        when /"steps"/
          { steps: [] }.to_json
        when /"summary".*"keywords"/m
          { summary: "Test summary", keywords: ["test", "issue", "redmine"] }.to_json
        else
          "Test response"
        end

        @on_end_message&.call(payload)
        Response.new(payload)
      end
    end

    module ProviderPatch
      def create_chat(*_args, **_kwargs)
        Chat.new
      end

      def embed(_text)
        Array.new(3072, 0.0)
      end
    end
  end

  Rails.application.config.to_prepare do
    %w[
      RedmineAiHelper::LlmClient::OpenAiProvider
      RedmineAiHelper::LlmClient::OpenAiCompatibleProvider
      RedmineAiHelper::LlmClient::GeminiProvider
      RedmineAiHelper::LlmClient::AnthropicProvider
      RedmineAiHelper::LlmClient::AzureOpenAiProvider
    ].each do |provider_name|
      provider = provider_name.safe_constantize
      next unless provider
      next if provider.ancestors.include?(RedmineAiHelperTestFakeLlm::ProviderPatch)

      provider.prepend(RedmineAiHelperTestFakeLlm::ProviderPatch)
    end
  end
end
