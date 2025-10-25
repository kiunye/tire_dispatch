defmodule TireDispatchWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    # Attach telemetry handlers for logging
    attach_telemetry_handlers()

    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp attach_telemetry_handlers do
    # Attach handler for job lifecycle events
    :telemetry.attach_many(
      "tire-dispatch-job-events",
      [
        [:tire_dispatch, :jobs, :created],
        [:tire_dispatch, :jobs, :accepted],
        [:tire_dispatch, :jobs, :completed],
        [:tire_dispatch, :jobs, :cancelled]
      ],
      &handle_job_event/4,
      nil
    )

    # Attach handler for payment events
    :telemetry.attach_many(
      "tire-dispatch-payment-events",
      [
        [:tire_dispatch, :payments, :initiated],
        [:tire_dispatch, :payments, :completed],
        [:tire_dispatch, :payments, :failed]
      ],
      &handle_payment_event/4,
      nil
    )

    # Attach handler for payout events
    :telemetry.attach_many(
      "tire-dispatch-payout-events",
      [
        [:tire_dispatch, :payouts, :processed],
        [:tire_dispatch, :payouts, :failed]
      ],
      &handle_payout_event/4,
      nil
    )
  end

  defp handle_job_event(event_name, measurements, metadata, _config) do
    require Logger

    case event_name do
      [:tire_dispatch, :jobs, :created] ->
        Logger.info("Job created telemetry event",
          job_id: metadata[:job_id],
          service_type: metadata[:service_type],
          urgency_tier: metadata[:urgency_tier]
        )

      [:tire_dispatch, :jobs, :accepted] ->
        Logger.info("Job accepted telemetry event",
          job_id: metadata[:job_id],
          provider_id: metadata[:provider_id],
          response_time_ms: measurements[:response_time]
        )

      [:tire_dispatch, :jobs, :completed] ->
        Logger.info("Job completed telemetry event",
          job_id: metadata[:job_id],
          completion_time_ms: measurements[:completion_time],
          final_price_cents: metadata[:final_price_cents]
        )

      [:tire_dispatch, :jobs, :cancelled] ->
        Logger.info("Job cancelled telemetry event",
          job_id: metadata[:job_id],
          reason: metadata[:cancellation_reason]
        )

      _ ->
        :ok
    end
  end

  defp handle_payment_event(event_name, measurements, metadata, _config) do
    require Logger

    case event_name do
      [:tire_dispatch, :payments, :initiated] ->
        Logger.info("Payment initiated telemetry event",
          transaction_id: metadata[:transaction_id],
          payment_method: metadata[:payment_method],
          amount_cents: metadata[:amount_cents]
        )

      [:tire_dispatch, :payments, :completed] ->
        Logger.info("Payment completed telemetry event",
          transaction_id: metadata[:transaction_id],
          payment_method: metadata[:payment_method],
          processing_time_ms: measurements[:processing_time]
        )

      [:tire_dispatch, :payments, :failed] ->
        Logger.error("Payment failed telemetry event",
          transaction_id: metadata[:transaction_id],
          payment_method: metadata[:payment_method],
          error: metadata[:error]
        )

      _ ->
        :ok
    end
  end

  defp handle_payout_event(event_name, _measurements, metadata, _config) do
    require Logger

    case event_name do
      [:tire_dispatch, :payouts, :processed] ->
        Logger.info("Payout processed telemetry event",
          payout_id: metadata[:payout_id],
          provider_id: metadata[:provider_id],
          amount_cents: metadata[:amount_cents],
          payment_method: metadata[:payment_method]
        )

      [:tire_dispatch, :payouts, :failed] ->
        Logger.error("Payout failed telemetry event",
          payout_id: metadata[:payout_id],
          provider_id: metadata[:provider_id],
          error: metadata[:error]
        )

      _ ->
        :ok
    end
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("tire_dispatch.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("tire_dispatch.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("tire_dispatch.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("tire_dispatch.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("tire_dispatch.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Custom Business Metrics - Job Lifecycle
      counter("tire_dispatch.jobs.created.count",
        tags: [:service_type, :urgency_tier],
        description: "Total number of jobs created"
      ),
      counter("tire_dispatch.jobs.accepted.count",
        tags: [:service_type],
        description: "Total number of jobs accepted by providers"
      ),
      counter("tire_dispatch.jobs.completed.count",
        tags: [:service_type],
        description: "Total number of jobs completed"
      ),
      counter("tire_dispatch.jobs.cancelled.count",
        tags: [:cancellation_reason],
        description: "Total number of jobs cancelled"
      ),
      summary("tire_dispatch.jobs.completion_time",
        unit: {:native, :millisecond},
        tags: [:service_type],
        description: "Time from job creation to completion"
      ),
      summary("tire_dispatch.jobs.response_time",
        unit: {:native, :millisecond},
        tags: [:service_type],
        description: "Time from job creation to provider acceptance"
      ),

      # Payment Metrics
      counter("tire_dispatch.payments.initiated.count",
        tags: [:payment_method],
        description: "Total number of payment attempts"
      ),
      counter("tire_dispatch.payments.completed.count",
        tags: [:payment_method],
        description: "Total number of successful payments"
      ),
      counter("tire_dispatch.payments.failed.count",
        tags: [:payment_method],
        description: "Total number of failed payments"
      ),
      summary("tire_dispatch.payments.amount",
        unit: :unit,
        tags: [:payment_method],
        description: "Payment amounts in cents"
      ),
      summary("tire_dispatch.payments.processing_time",
        unit: {:native, :millisecond},
        tags: [:payment_method],
        description: "Time to process payment"
      ),

      # Payout Metrics
      counter("tire_dispatch.payouts.processed.count",
        tags: [:payment_method],
        description: "Total number of payouts processed"
      ),
      counter("tire_dispatch.payouts.failed.count",
        tags: [:payment_method],
        description: "Total number of failed payouts"
      ),
      summary("tire_dispatch.payouts.amount",
        unit: :unit,
        tags: [:payment_method],
        description: "Payout amounts in cents"
      ),

      # Refund Metrics
      counter("tire_dispatch.refunds.processed.count",
        tags: [:payment_method],
        description: "Total number of refunds processed"
      ),
      summary("tire_dispatch.refunds.amount",
        unit: :unit,
        tags: [:payment_method],
        description: "Refund amounts in cents"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {TireDispatchWeb, :count_users, []}
    ]
  end
end
