defmodule EctoReplaySandbox.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      config = Application.get_env(:ecto_replay_sandbox, __MODULE__)
      config = Keyword.put(config, :loggers, [Ecto.LogEntry,
                                              {EctoReplaySandbox.Integration.Repo, :log, [:on_log]}])
      Application.put_env(:ecto_replay_sandbox, __MODULE__, config)
      use Ecto.Repo, unquote(opts)
    end
  end

  def log(entry, key) do
    on_log = Process.delete(key) || fn _ -> :ok end
    on_log.(entry)
    entry
  end
end