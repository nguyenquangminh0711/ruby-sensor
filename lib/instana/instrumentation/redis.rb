module Instana
  module Instrumentation
    class Redis
      def self.get_host(client)
        client.host
      end

      def self.get_port(client)
        client.port
      end

      def self.pipeline_operation(pipeline)
        pipeline.is_a?(::Redis::Pipeline::Multi) ? 'MULTI' : 'PIPELINE'
      end

      def self.stringify_command(command)
        command.join(' ')
      end

      def self.stringify_pipeline_command(pipeline)
        pipeline.commands.map do |command|
          command.join(' ')
        end.join("\n")
      end
    end
  end
end

if defined?(::Redis) && ::Instana.config[:redis][:enabled]
  ::Redis::Client.class_eval do
    def call_with_instana(*args, &block)
      kv_payload = { redis: {} }

      if !Instana.tracer.tracing?
        return call_without_instana(*args, &block)
      end

      kv_payload[:redis] = {
        host: ::Instana::Instrumentation::Redis.get_host(self),
        port: ::Instana::Instrumentation::Redis.get_port(self),
        db: db,
        operation: args[0][0].to_s,
        command: ::Instana::Instrumentation::Redis.stringify_command(args[0])
      }
      ::Instana.tracer.log_entry(:redis, kv_payload)

      call_without_instana(*args, &block)
    rescue => e
      kv_payload[:redis][:error] = true
      ::Instana.tracer.log_info(kv_payload)
      ::Instana.tracer.log_error(e)
      raise
    ensure
      ::Instana.tracer.log_exit(:redis, {})
    end

    ::Instana.logger.info "Instrumenting Redis"

    alias call_without_instana call
    alias call call_with_instana

    def call_pipeline_with_instana(*args, &block)
      kv_payload = { redis: {} }

      if !Instana.tracer.tracing?
        return call_pipeline_without_instana(*args, &block)
      end

      pipeline = args.first
      kv_payload[:redis] = {
        host: ::Instana::Instrumentation::Redis.get_host(self),
        port: ::Instana::Instrumentation::Redis.get_port(self),
        db: db,
        operation: ::Instana::Instrumentation::Redis.pipeline_operation(pipeline),
        command: ::Instana::Instrumentation::Redis.stringify_pipeline_command(pipeline)
      }
      ::Instana.tracer.log_entry(:redis, kv_payload)

      call_pipeline_without_instana(*args, &block)
    rescue => e
      kv_payload[:redis][:error] = true
      ::Instana.tracer.log_info(kv_payload)
      ::Instana.tracer.log_error(e)
      raise
    ensure
      ::Instana.tracer.log_exit(:redis, {})
    end

    alias call_pipeline_without_instana call_pipeline
    alias call_pipeline call_pipeline_with_instana
  end
end
