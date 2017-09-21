Code.compiler_options(ignore_module_conflict: true)

Logger.configure(level: :info)
ExUnit.configure(exclude: [:pending, :without_conflict_target])
ExUnit.start()

# Configure Ecto for support and tests
Application.put_env(:ecto, :lock_for_update, "FOR UPDATE")
Application.put_env(:ecto, :primary_key_type, :id)

# Configure CockroachDB connection
Application.put_env(:ecto_replay_sandbox, :cdb_test_url,
  "ecto://" <> (System.get_env("CDB_URL") || "root@localhost:26257")
)

# Load support files
Code.require_file "./repo.exs", __DIR__
Code.require_file "./schema.exs", __DIR__
Code.require_file "./migration.exs", __DIR__

pool =
  case System.get_env("ECTO_POOL") || "poolboy" do
    "poolboy" -> DBConnection.Poolboy
    "sbroker" -> DBConnection.Sojourn
  end

# Pool repo for async, safe tests
alias EctoReplaySandbox.Integration.TestRepo

Application.put_env(:ecto_replay_sandbox, TestRepo,
  adapter: Ecto.Adapters.Postgres,
  url: Application.get_env(:ecto_replay_sandbox, :cdb_test_url) <> "/ecto_replay_sandbox_test",
  pool: EctoReplaySandbox,
  ownership_pool: pool)

defmodule EctoReplaySandbox.Integration.TestRepo do
  use EctoReplaySandbox.Integration.Repo, otp_app: :ecto_replay_sandbox
end

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(TestRepo, :temporary)

# Load up the repository, start it, and run migrations
_   = Ecto.Adapters.Postgres.storage_down(TestRepo.config)
:ok = Ecto.Adapters.Postgres.storage_up(TestRepo.config)

{:ok, _pid} = TestRepo.start_link

:ok = Ecto.Migrator.up(TestRepo, 0, EctoReplaySandbox.Integration.Migration, log: false)
EctoReplaySandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
