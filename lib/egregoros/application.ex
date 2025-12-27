defmodule Egregoros.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EgregorosWeb.Telemetry,
      Egregoros.Repo,
      Egregoros.RateLimiter.ETS,
      {Oban, Application.fetch_env!(:egregoros, Oban)},
      {DNSCluster, query: Application.get_env(:egregoros, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Egregoros.PubSub},
      # Start a worker by calling: Egregoros.Worker.start_link(arg)
      # {Egregoros.Worker, arg},
      # Start to serve requests, typically the last entry
      EgregorosWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Egregoros.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EgregorosWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
