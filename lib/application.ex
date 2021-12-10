defmodule BroadwayRabbitMQCustomRetry.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BroadwayRabbitMQCustomRetry.Step
    ]

    opts = [strategy: :one_for_one, name: BroadwayRabbitMQCustomRetry.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
