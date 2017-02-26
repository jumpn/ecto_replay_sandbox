# CockroachDBSandbox

This is an override of Ecto.Adapters.SQL.Sandbox designed to work for CockroachDB by not leveraging savepoints.
Each test runs inside a transaction managed by the Sandbox, just like with regular Ecto Sandbox.

Inside your test, when your code opens a transaction block, given that CockroachDB does not support nested transactions or savepoints, no actual database transaction is created.
Instead the Sandbox is using a log approach described below and such transaction are called pseudo transaction.

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
by adding `cockroachdb_sandbox` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:cockroachdb_sandbox, "~> 0.1.0", only: :test}]
end
```

> You need to declare this dependency after Ecto in order to make sure that we override the default Ecto Sandbox.
