module Instana
  module Instrumentation
    module Faraday
      def self.included(klass)
        ::Instana::Util.method_alias(::Faraday::Connection, :run_request)
      end

      def run_request_with_instana(method, url, body, headers)
        kv_payload = {}
        ::Instana.tracer.log_entry(:faraday, kv_payload)

        run_request_without_instana(method, url, body, headers)

      rescue => e
        ::Instana.tracer.log_error(e)
        raise
      ensure
        ::Instana.tracer.log_exit(:faraday, kv_payload)
      end
    end
  end
end

if defined?(::Faraday)
  ::Instana.logger.warn "Instrumenting Faraday"
  ::Instana::Util.send_include(::Faraday::Connection, ::Instana::Instrumentation::Faraday)
end
