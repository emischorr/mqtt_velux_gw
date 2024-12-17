defmodule MqttVeluxGw.MixProject do
  use Mix.Project

  def project do
    [
      app: :mqtt_velux_gw,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        mqtt_velux_gw: []
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MqttVeluxGw.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tortoise311, "~> 0.12.0"},
      {:klf200, "~> 0.1.0"}
    ]
  end
end
