require 'test_helper'

class SidekiqServerTest < Minitest::Test
  def test_config_defaults
    assert ::Instana.config[:'sidekiq-worker'].is_a?(Hash)
    assert ::Instana.config[:'sidekiq-worker'].key?(:enabled)
    assert_equal true, ::Instana.config[:'sidekiq-worker'][:enabled]
  end

  def test_successful_worker_starts_new_trace
    clear_all!
    $sidekiq_mode = :server
    inject_instrumentation

    ::Sidekiq.redis_pool.with do |redis|
      redis.sadd('queues'.freeze, 'important')
      redis.lpush(
        'queue:important',
        <<-JSON
        {
          "class":"SidekiqJobOne",
          "args":[1,2,3],
          "queue":"important",
          "jid":"123456789"
        }
        JSON
      )
    end
    sleep 1

    assert_equal 1, ::Instana.processor.queue_count
    assert_successful_worker_trace(::Instana.processor.queued_traces.first)

    $sidekiq_mode = :client
  end

  def test_failed_worker_starts_new_trace
    clear_all!
    $sidekiq_mode = :server
    inject_instrumentation

    ::Sidekiq.redis_pool.with do |redis|
      redis.sadd('queues'.freeze, 'important')
      redis.lpush(
        'queue:important',
        <<-JSON
        {
          "class":"SidekiqJobTwo",
          "args":[1,2,3],
          "queue":"important",
          "jid":"123456789"
        }
        JSON
      )
    end
    sleep 1
    assert_equal 1, ::Instana.processor.queue_count
    assert_failed_worker_trace(::Instana.processor.queued_traces.first)

    $sidekiq_mode = :client
  end

  def test_successful_worker_continues_previous_trace
    clear_all!
    $sidekiq_mode = :server
    inject_instrumentation

    Instana.tracer.start_or_continue_trace(:sidekiqtests) do
      ::Sidekiq::Client.push(
        'queue' => 'important',
        'class' => ::SidekiqJobOne,
        'args' => [1, 2, 3]
      )
    end
    sleep 1
    assert_equal 2, ::Instana.processor.queue_count
    client_trace, worker_trace = Instana.processor.queued_traces.to_a
    assert_successful_client_trace(client_trace)
    assert_successful_worker_trace(worker_trace)

    # Worker trace and client trace are in the same trace
    assert_equal client_trace.spans.first['t'], worker_trace.spans.first['t']

    $sidekiq_mode = :client
  end

  private

  def inject_instrumentation
    # Add the instrumentation again to ensure injection in server mode
    ::Sidekiq.configure_server do |cfg|
      cfg.server_middleware do |chain|
        chain.add ::Instana::Instrumentation::SidekiqWorker
      end
    end
  end

  def assert_successful_worker_trace(worker_trace)
    assert_equal 1, worker_trace.spans.count
    span = worker_trace.spans.first

    assert_equal :sdk, span[:n]
    data = span[:data][:sdk]

    assert_equal :'sidekiq-worker', data[:name]
    assert_equal 'important', data[:custom][:'sidekiq-worker'][:queue]
    assert_equal 'SidekiqJobOne', data[:custom][:'sidekiq-worker'][:job]
    assert_equal false, data[:custom][:'sidekiq-worker'][:job_id].nil?
  end

  def assert_successful_client_trace(client_trace)
    assert_equal 2, client_trace.spans.count
    first_span, second_span = client_trace.spans.to_a

    assert_equal :sdk, first_span[:n]
    assert_equal :sidekiqtests, first_span[:data][:sdk][:name]

    assert_equal first_span.id, second_span[:p]

    assert_equal :sdk, second_span[:n]
    data = second_span[:data][:sdk]

    assert_equal :'sidekiq-client', data[:name]
    assert_equal 'important', data[:custom][:'sidekiq-client'][:queue]
    assert_equal 'SidekiqJobOne', data[:custom][:'sidekiq-client'][:job]
  end

  def assert_failed_worker_trace(worker_trace)
    assert_equal 1, worker_trace.spans.count
    span = worker_trace.spans.first

    assert_equal :sdk, span[:n]
    data = span[:data][:sdk]

    assert_equal :'sidekiq-worker', data[:name]
    assert_equal 'important', data[:custom][:'sidekiq-worker'][:queue]
    assert_equal 'SidekiqJobTwo', data[:custom][:'sidekiq-worker'][:job]
    assert_equal false, data[:custom][:'sidekiq-worker'][:job_id].nil?

    assert_equal true, data[:custom][:'sidekiq-worker'][:error]
    assert_equal 'Fail to execute the job', data[:custom][:log][:message]
  end
end
