Logger.configure(level: :info)
ExUnit.configure(exclude: [:pending, :without_conflict_target])

# Configure Ecto for support and tests
Application.put_env(:ecto, :primary_key_type, :id)
Application.put_env(:ecto, :async_integration_tests, true)
Application.put_env(:ecto_replay_sandbox, :lock_for_update, nil)

# Configure CockroachDB connection
Application.put_env(
  :ecto_replay_sandbox,
  :cdb_test_url,
  "ecto://" <> (System.get_env("CDB_URL") || "root@localhost:26257")
)

# Load support files
Code.require_file("./repo.exs", __DIR__)

# Pool repo for async, safe tests
alias EctoReplaySandbox.Integration.TestRepo

Application.put_env(:ecto_replay_sandbox, TestRepo,
  url: Application.get_env(:ecto_replay_sandbox, :cdb_test_url) <> "/ecto_replay_sandbox_test",
  pool: EctoReplaySandbox
)

defmodule EctoReplaySandbox.Integration.TestRepo do
  use EctoReplaySandbox.Integration.Repo,
    otp_app: :ecto_replay_sandbox,
    adapter: Ecto.Adapters.CockroachDB
end

# Pool repo for non-async tests
alias EctoReplaySandbox.Integration.PoolRepo

Application.put_env(:ecto_replay_sandbox, PoolRepo,
  url: Application.get_env(:ecto_replay_sandbox, :cdb_test_url) <> "/ecto_replay_sandbox_test",
  pool_size: 10,
  max_restarts: 20,
  max_seconds: 10
)

defmodule EctoReplaySandbox.Integration.PoolRepo do
  use EctoReplaySandbox.Integration.Repo,
    otp_app: :ecto_replay_sandbox,
    adapter: Ecto.Adapters.CockroachDB
end

# Load support files
Code.require_file("./schema.exs", __DIR__)
Code.require_file("./migration.exs", __DIR__)

{:ok, _} = Ecto.Adapters.CockroachDB.ensure_all_started(TestRepo.config(), :temporary)

# Load up the repository, start it, and run migrations
_ = Ecto.Adapters.CockroachDB.storage_down(TestRepo.config())
:ok = Ecto.Adapters.CockroachDB.storage_up(TestRepo.config())

{:ok, _pid} = TestRepo.start_link()
{:ok, _pid} = PoolRepo.start_link()

:ok = Ecto.Migrator.up(TestRepo, 0, EctoReplaySandbox.Integration.Migration, log: false)
EctoReplaySandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)

ExUnit.start()
