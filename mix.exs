defmodule CockroachDBSandbox.Mixfile do
  use Mix.Project

  def project do
    [app: :cockroachdb_sandbox,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [
      extra_applications: [:logger],
    ]
  end

  defp deps do
    [
      {:ecto, "~> 2.1"},
      {:db_connection, "~> 1.1"},
      {:postgrex, git: "git@github.com:jumpn/postgrex.git", override: true},
    ]
  end
end
