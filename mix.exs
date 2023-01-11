defmodule EctoReplaySandbox.Mixfile do
  use Mix.Project

  @version "2.1.0"

  def project do
    [
      app: :ecto_replay_sandbox,
      version: @version,
      elixir: "~> 1.5",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      source_url: "https://github.com/jumpn/ecto_replay_sandbox",
      docs: [source_ref: "v#{@version}", main: "readme", extras: ["README.md"]],
      deps: deps()
    ]
  end

  defp package do
    [
      description: "Log replay based sandbox for Ecto, compatible with CockroachDB",
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Christian Meunier"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/jumpn/ecto_replay_sandbox"}
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.20", only: :dev},
      {:ecto, "~> 3.1"},
      {:ecto_sql, "~> 3.1"},
      {:db_connection, "~> 2.0"},
      {:postgrex, ">= 0.14.3"}
    ]
  end
end
