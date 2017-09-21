defmodule EctoReplaySandbox.Mixfile do
  use Mix.Project

  @version "1.0.0"

  def project do
    [app: :ecto_replay_sandbox,
     version: @version,
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     package: package(),
     source_url: "https://github.com/jumpn/ecto_replay_sandbox",
     docs: [source_ref: "v#{@version}", main: "EctoReplaySandbox"],
     deps: deps()]
  end

  defp package do
    [description: "Log replay based sandbox for Ecto to run your tests, compatible with CockroachDB",
     files: ["lib", "mix.exs", "README*"],
     maintainers: ["Christian Meunier"],
     licenses: ["MIT"],
     links: %{github: "https://github.com/jumpn/ecto_replay_sandbox"}]
  end

  def application do
    [
      extra_applications: [:logger],
    ]
  end

  defp deps do
    [
      {:ecto, "~> 2.2"},
      {:db_connection, "~> 1.1"},
      {:postgrex, git: "git@github.com:jumpn/postgrex.git", tag: "v1.0.0", override: true},
    ]
  end
end
