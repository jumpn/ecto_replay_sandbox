defmodule CockroachDBSandbox.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      config = Application.get_env(:cockroachdb_sandbox, __MODULE__)
      config = Keyword.put(config, :loggers, [Ecto.LogEntry,
                                              {CockroachDBSandbox.Integration.Repo, :log, [:on_log]}])
      Application.put_env(:cockroachdb_sandbox, __MODULE__, config)
      use Ecto.Repo, unquote(opts)
    end
  end

  def log(entry, key) do
    on_log = Process.delete(key) || fn _ -> :ok end
    on_log.(entry)
    entry
  end
end