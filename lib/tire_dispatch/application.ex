defmodule TireDispatch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize MPESA token cache
    TireDispatch.Payments.MPESA.init_cache()

    children = [
      TireDispatchWeb.Telemetry,
      TireDispatch.Repo,
      {DNSCluster, query: Application.get_env(:tire_dispatch, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TireDispatch.PubSub},
      # Start the PricingCache for fast pricing rule lookups
      TireDispatch.Pricing.PricingCache,
      # Start a worker by calling: TireDispatch.Worker.start_link(arg)
      # {TireDispatch.Worker, arg},
      # Start to serve requests, typically the last entry
      TireDispatchWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TireDispatch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TireDispatchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
