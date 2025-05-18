defmodule Argos.MixProject do
  use Mix.Project

  def project do
    [
      app: :argos,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Argos.CLI],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Argos.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 2.0"},
      {:hackney, "~> 1.18"},
      {:tortoise, "~> 0.9"},
      {:websockex, "~> 0.4"},
      {:meck, "~> 0.9.2", only: :test},
      {:plug_cowboy, "~> 2.6", only: :test},
      {:jason, "~> 1.4"}
    ]
  end
end
