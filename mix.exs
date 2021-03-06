defmodule BroadwayRabbitMQCustomRetry.MixProject do
  use Mix.Project

  def project do
    [
      app: :broadway_rabbitmq_custom_retry,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BroadwayRabbitMQCustomRetry.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:broadway_rabbitmq, "~> 0.7"}
    ]
  end
end
