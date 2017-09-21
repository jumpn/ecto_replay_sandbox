# EctoReplaySandbox

This is a custom implementation of Ecto.Adapters.SQL.Sandbox designed to work with CockroachDB by not leveraging savepoints.
Each test runs inside a transaction managed by the Sandbox, just like with default Ecto Sandbox.

Inside your test, when your code opens a transaction block, given that CockroachDB does not support nested transactions or savepoints, no actual database transaction is created.
Instead the sandbox is using a log approach described below and such transaction are called pseudo transaction.

The sandbox maintains 2 logs for a given managed transaction:
- Sandbox log
- Transaction log

The Sandbox log contains the statements that have been commited to the database by your test, either outside of a pseudo transaction or once a pseudo transaction is commited.
The Transaction log keeps track of statements that are running inside a pseudo transaction and it is eventually appended to the Sandbox log once the pseudo transaction is successfully committed.

When an error occurs or when a pseudo transaction is being explicitely rollbacked, the managed transaction is being rollbacked and a new transaction is being created.
Then the Sandbox log is being replayed to restore the state to how it was before the error or the rollbacked pseudo transaction started.

Once the test finishes, the managed transaction is being rollbacked to restore the state of the database to how it was before the test began.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ecto_replay_sandbox` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:ecto_replay_sandbox, "~> 1.0.0", only: :test}]
end
```

## Usage

In your `config/test.ex`
```elixir
config :my_app, MyApp.Repo,
  pool: EctoReplaySandbox
```

Then in your `test/test_helper.ex`

Replace the following line:
```elixir
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)
```

with:
```elixir
sandbox = Application.get_env(:my_app, MyApp.Repo)[:pool]
sandbox.mode(MyApp.Repo, :manual)
```

It effectively removes the hardcoded usage of `Ecto.Adapters.SQL.Sandbox` with a dynamic lookup of the configured pool.

## Credits

I'd like to give special thanks to James Fish (@fishcakez) for his help getting this working and always taking the time to offer guidance or otherwise feedback the CockroachDB team so that we can use Ecto with CockroachDB with little to no friction.