defmodule EctoReplaySandbox do
  @moduledoc ~S"""
  A pool for concurrent transactional tests.

  The sandbox pool is implemented on top of an ownership mechanism.
  When started, the pool is in automatic mode, which means the
  repository will automatically check connections out as with any
  other pool.

  The `mode/2` function can be used to change the pool mode to
  manual or shared. In both modes, the connection must be explicitly
  checked out before use. When explicit checkouts are made, the
  sandbox will wrap the connection in a transaction by default and
  control who has access to it. This means developers have a safe
  mechanism for running concurrent tests against the database.

  ## Database support

  While this sandbox has been developped with CockroachDB in mind, it should work with other Postgresql variants.

  ## Example

  The first step is to configure your database to use the
  `EctoReplaySandbox` pool in your tests. You set this in your
  `config/test.exs` if you haven't yet:

      config :my_app, MyApp.Repo,
        pool: EctoReplaySandbox

  Now with the test database properly configured, you can write
  transactional tests:

      # At the end of your test_helper.exs
      # Set the pool mode to manual for explicit checkouts
      sandbox = Application.get_env(:my_app, Repo)[:pool]
      sandbox.mode(Repo, :manual)

      defmodule PostTest do
        # Once the mode is manual, tests can also be async
        use ExUnit.Case, async: true

        setup do
          # Explicitly get a connection before each test
          sandbox = Application.get_env(:my_app, Repo)[:pool]
          :ok = sandbox.checkout(Repo)
        end

        test "create post" do
          # Use the repository as usual
          assert %Post{} = Repo.insert!(%Post{})
        end
      end

  ## Collaborating processes

  The example above is straight-forward because we have only
  a single process using the database connection. However,
  sometimes a test may need to interact with multiple processes,
  all using the same connection so they all belong to the same
  transaction.

  Before we discuss solutions, let's see what happens if we try
  to use a connection from a new process without explicitly
  checking it out first:

      setup do
        # Explicitly get a connection before each test
        sandbox = Application.get_env(:my_app, Repo)[:pool]
        :ok = sandbox.checkout(Repo)
      end

      test "create two posts, one sync, another async" do
        task = Task.async(fn ->
          Repo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = Repo.insert!(%Post{title: "sync"})
        assert %Post{} = Task.await(task)
      end

  The test above will fail with an error similar to:

      ** (RuntimeError) cannot find ownership process for #PID<0.35.0>

  That's because the `setup` block is checking out the connection only
  for the test process. Once we spawn a Task, there is no connection
  assigned to it and it will fail.

  The sandbox module provides two ways of doing so, via allowances or
  by running in shared mode.

  ### Allowances

  The idea behind allowances is that you can explicitly tell a process
  which checked out connection it should use, allowing multiple processes
  to collaborate over the same connection. Let's give it a try:

      test "create two posts, one sync, another async" do
        parent = self()
        task = Task.async(fn ->
          sandbox = Application.get_env(:my_app, Repo)[:pool]
          sandbox.allow(Repo, parent, self())
          Repo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = Repo.insert!(%Post{title: "sync"})
        assert %Post{} = Task.await(task)
      end

  And that's it, by calling `allow/3`, we are explicitly assigning
  the parent's connection (i.e. the test process' connection) to
  the task.

  Because allowances use an explicit mechanism, their advantage
  is that you can still run your tests in async mode. The downside
  is that you need to explicitly control and allow every single
  process. This is not always possible. In such cases, you will
  want to use shared mode.

  ### Shared mode

  Shared mode allows a process to share its connection with any other
  process automatically, without relying on explicit allowances.
  Let's change the example above to use shared mode:

      setup do
        # Explicitly get a connection before each test
        sandbox = Application.get_env(:my_app, Repo)[:pool]
        :ok = sandbox.checkout(Repo)
        # Setting the shared mode must be done only after checkout
        sandbox.mode(Repo, {:shared, self()})
      end

      test "create two posts, one sync, another async" do
        task = Task.async(fn ->
          Repo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = Repo.insert!(%Post{title: "sync"})
        assert %Post{} = Task.await(task)
      end

  By calling `mode({:shared, self()})`, any process that needs
  to talk to the database will now use the same connection as the
  one checked out by the test process during the `setup` block.

  Make sure to always check a connection out before setting the mode
  to `{:shared, self()}`.

  The advantage of shared mode is that by calling a single function,
  you will ensure all upcoming processes and operations will use that
  shared connection, without a need to explicitly allow them. The
  downside is that tests can no longer run concurrently in shared mode.

  ### Summing up

  There are two mechanisms for explicit ownerships:

    * Using allowances - requires explicit allowances via `allow/3`.
      Tests may run concurrently.

    * Using shared mode - does not require explicit allowances.
      Tests cannot run concurrently.

  ## FAQ

  When running the sandbox mode concurrently, developers may run into
  issues we explore in the upcoming sections.

  ### "owner exited while client is still running"

  In some situations, you may see error reports similar to the one below:

      21:57:43.910 [error] Postgrex.Protocol (#PID<0.284.0>) disconnected:
          ** (DBConnection.Error) owner #PID<> exited while client #PID<> is still running

  Such errors are usually followed by another error report from another
  process that failed while executing a database query.

  To understand the failure, we need to answer the question: who are the
  owner and client processes? The owner process is the one that checks
  out the connection, which, in the majority of cases, is the test process,
  the one running your tests. In other words, the error happens because
  the test process has finished, either because the test succeeded or
  because it failed, while the client process was trying to get information
  from the database. Since the owner process, the one that owns the
  connection, no longer exists, Ecto will check the connection back in
  and notify the client process using the connection that the connection
  owner is no longer available.

  This can happen in different situations. For example, imagine you query
  a GenServer in your test that is using a database connection:

      test "gets results from GenServer" do
        {:ok, pid} = MyAppServer.start_link()
        sandbox = Application.get_env(:my_app, Repo)[:pool]
        sandbox.allow(Repo, self(), pid)
        assert MyAppServer.get_my_data_fast(timeout: 1000) == [...]
      end

  In the test above, we spawn the server and allow it to perform database
  queries using the connection owned by the test process. Since we gave
  a timeout of 1 second, in case the database takes longer than one second
  to reply, the test process will fail, due to the timeout, making the
  "owner down" message to be printed because the server process is still
  waiting on a connection reply.

  In some situations, such failures may be intermittent. Imagine that you
  allow a process that queries the database every half second:

      test "queries periodically" do
        {:ok, pid} = PeriodicServer.start_link()
        sandbox = Application.get_env(:my_app, Repo)[:pool]
        sandbox.allow(Repo, self(), pid)
        # more tests
      end

  Because the server is querying the database from time to time, there is
  a chance that, when the test exists, the periodic process may be querying
  the database, regardless of test success or failure.

  ### "owner timed out because it owned the connection for longer than Nms"

  In some situations, you may see error reports similar to the one below:

      09:56:43.081 [error] Postgrex.Protocol (#PID<>) disconnected:
          ** (DBConnection.ConnectionError) owner #PID<> timed out
          because it owned the connection for longer than 15000ms

  If you have a long running test (or you're debugging with IEx.pry), the timeout for the connection ownership may
  be too short.  You can increase the timeout by setting the
  `:ownership_timeout` options for your repo config in `config/config.exs` (or preferably in `config/test.exs`):

      config :my_app, MyApp.Repo,
        ownership_timeout: NEW_TIMEOUT_IN_MILLISECONDS

  The `:ownership_timeout` option is part of
  [`DBConnection.Ownership`](https://hexdocs.pm/db_connection/DBConnection.Ownership.html)
  and defaults to 15000ms. Timeouts are given as integers in milliseconds.

  Alternately, if this is an issue for only a handful of long-running tests,
  you can pass an `:ownership_timeout` option when calling
  `EctoReplaySandbox.checkout/2` instead of setting a longer timeout
  globally in your config.

  ### Database locks and deadlocks

  Since the sandbox relies on concurrent transactional tests, there is
  a chance your tests may trigger deadlocks in your database. This is
  specially true with MySQL, where the solutions presented here are not
  enough to avoid deadlocks and therefore making the use of concurrent tests
  with MySQL prohibited.

  However, even on databases like PostgreSQL, performance degradations or
  deadlocks may still occur. For example, imagine multiple tests are
  trying to insert the same user to the database. They will attempt to
  retrieve the same database lock, causing only one test to succeed and
  run while all other tests wait for the lock.

  In other situations, two different tests may proceed in a way that
  each test retrieves locks desired by the other, leading to a situation
  that cannot be resolved, a deadlock. For instance:

      Transaction 1:                Transaction 2:
      begin
                                    begin
      update posts where id = 1
                                    update posts where id = 2
                                    update posts where id = 1
      update posts where id = 2
                            **deadlock**

  There are different ways to avoid such problems. One of them is
  to make sure your tests work on distinct data. Regardless of
  your choice between using fixtures or factories for test data,
  make sure you get a new set of data per test. This is specially
  important for data that is meant to be unique like user emails.

  For example, instead of:

      def insert_user do
        Repo.insert! %User{email: "sample@example.com"}
      end

  prefer:

      def insert_user do
        Repo.insert! %User{email: "sample-#{counter()}@example.com"}
      end

      defp counter do
        System.unique_integer [:positive]
      end

  Deadlocks may happen in other circumstances. If you believe you
  are hitting a scenario that has not been described here, please
  report an issue so we can improve our examples. As a last resort,
  you can always disable the test triggering the deadlock from
  running asynchronously by setting  "async: false".
  """

  defmodule Connection do
    @begin_result %Postgrex.Result{
      columns: nil,
      command: :begin,
      connection_id: nil,
      num_rows: nil,
      rows: nil
    }
    @commit_result %Postgrex.Result{
      columns: nil,
      command: :commit,
      connection_id: nil,
      num_rows: nil,
      rows: nil
    }
    @rollback_result %Postgrex.Result{
      columns: nil,
      command: :rollback,
      connection_id: nil,
      num_rows: nil,
      rows: nil
    }

    @moduledoc false
    if Code.ensure_loaded?(DBConnection) do
      @behaviour DBConnection
    end

    def connect(_opts) do
      raise "should never be invoked"
    end

    def disconnect(err, {conn_mod, state, _in_transaction?}) do
      conn_mod.disconnect(err, state)
    end

    def checkout(state), do: proxy(:checkout, state, [])
    def checkin(state), do: proxy(:checkin, state, [])
    def ping(state), do: proxy(:ping, state, [])

    def handle_begin(_opts, {conn_mod, state, false, {sandbox_log, _tx_log}}) do
      {:ok, @begin_result, {conn_mod, state, true, {sandbox_log, []}}}
    end

    def handle_commit(_opts, {conn_mod, state, true, {sandbox_log, tx_log}}) do
      {state, sandbox_log} =
        case sandbox_log do
          [:error_detected | tail] ->
            restart_result = restart_sandbox_tx(conn_mod, state)
            {elem(restart_result, 2), [:replay_needed | tail]}

          _ ->
            {state, sandbox_log ++ tx_log}
        end

      {:ok, @commit_result, {conn_mod, state, false, {sandbox_log, []}}}
    end

    def handle_rollback(opts, {conn_mod, state, true, {sandbox_log, _}}) do
      sandbox_log =
        case sandbox_log do
          [:error_detected | tail] -> tail
          _ -> sandbox_log
        end

      case restart_sandbox_tx(conn_mod, state, opts) do
        {:ok, _, conn_state} ->
          {:ok, @rollback_result,
           {conn_mod, conn_state, false, {[:replay_needed | sandbox_log], []}}}

        error ->
          pos = :erlang.tuple_size(error)

          :erlang.setelement(
            pos,
            error,
            {conn_mod, :erlang.element(pos, error), false, {sandbox_log, []}}
          )
      end
    end

    def handle_status(opts, state),
      do: proxy(:handle_status, state, [opts])

    def handle_prepare(query, opts, state),
      do: proxy(:handle_prepare, state, [query, opts])

    def handle_execute(query, params, opts, state),
      do: proxy(:handle_execute, state, [query, params, opts])

    def handle_close(query, opts, state),
      do: proxy(:handle_close, state, [query, opts])

    def handle_declare(query, params, opts, state),
      do: proxy(:handle_declare, state, [query, params, opts])

    def handle_fetch(query, cursor, opts, state),
      do: proxy(:handle_fetch, state, [query, cursor, opts])

    def handle_deallocate(query, cursor, opts, state),
      do: proxy(:handle_deallocate, state, [query, cursor, opts])

    defp proxy(fun, {conn_mod, state, in_transaction?, {sandbox_log, _tx_log} = log_state}, args) do
      # Handle replay
      {state, log_state} =
        case sandbox_log do
          [:replay_needed | tail] ->
            state =
              tail
              |> Enum.reduce(state, fn {replay_fun, replay_args}, state ->
                {:ok, _, state} =
                  apply(conn_mod, replay_fun, replay_args ++ [state]) |> normalize_result

                state
              end)

            {state, {tail, []}}

          _ ->
            {state, log_state}
        end

      # Execute command
      {status, result, state} = apply(conn_mod, fun, args ++ [state]) |> normalize_result

      # Handle error
      {state, log_state} =
        case status do
          ok_val when ok_val in [:ok, :cont, :halt] ->
            {state, log_command(fun, args, in_transaction?, log_state)}

          error_val when error_val in [:error, :disconnect] ->
            if(in_transaction?) do
              log_state =
                case sandbox_log do
                  [:error_detected | _tail] -> {elem(log_state, 0), []}
                  _ -> {[:error_detected | elem(log_state, 0)], []}
                end

              {state, log_state}
            else
              {_status, _result, state} = restart_sandbox_tx(conn_mod, state)
              {state, {[:replay_needed | elem(log_state, 0)], []}}
            end
        end

      put_elem(result, tuple_size(result) - 1, {conn_mod, state, in_transaction?, log_state})
    end

    defp normalize_result(result) do
      status = elem(result, 0)
      state = elem(result, tuple_size(result) - 1)
      {status, result, state}
    end

    defp log_command(fun, args, in_transactions?, {sandbox_log, tx_log}) do
      case fun do
        command
        when command in [
               :handle_execute,
               :handle_close,
               :handle_declare,
               :handle_fetch,
               :handle_deallocate
             ] ->
          if in_transactions? do
            {sandbox_log, tx_log ++ [{fun, args}]}
          else
            {sandbox_log ++ [{fun, args}], []}
          end

        _ ->
          {sandbox_log, tx_log}
      end
    end

    defp restart_sandbox_tx(conn_mod, conn_state, opts \\ []) do
      with {:ok, _, conn_state} <-
             conn_mod.handle_rollback([mode: :transaction] ++ opts, conn_state),
           {:ok, _, _} = begin_result <- conn_mod.handle_begin([mode: :transaction], conn_state) do
        begin_result
      end
    end
  end

  @doc """
  Sets the mode for the `repo` pool.

  The mode can be `:auto`, `:manual` or `{:shared, <pid>}`.

  Warning: you should only call this function in the setup block for a test and
  not within a test, because if the mode is changed during the test it will cause
  other database connections to be checked in (causing errors).
  """
  def mode(repo, mode)
      when is_atom(repo) and mode in [:auto, :manual]
      when is_atom(repo) and elem(mode, 0) == :shared and is_pid(elem(mode, 1)) do
    %{pid: pool, opts: opts} = lookup_meta!(repo)
    DBConnection.Ownership.ownership_mode(pool, mode, opts)
  end

  @doc """
  Checks a connection out for the given `repo`.

  The process calling `checkout/2` will own the connection
  until it calls `checkin/2` or until it crashes when then
  the connection will be automatically reclaimed by the pool.

  ## Options

    * `:sandbox` - when true the connection is wrapped in
      a transaction. Defaults to true.

    * `:isolation` - set the query to the given isolation level.

    * `:ownership_timeout` - limits how long the connection can be
      owned. Defaults to the value in your repo config in
      `config/config.exs` (or preferably in `config/test.exs`), or
      60000 ms if not set. The timeout exists for sanity checking
      purposes, to ensure there is no connection leakage, and can
      be bumped whenever necessary.

  """
  def checkout(repo, opts \\ []) when is_atom(repo) do
    %{pid: pool, opts: pool_opts} = lookup_meta!(repo)

    pool_opts =
      if Keyword.get(opts, :sandbox, true) do
        [
          post_checkout: &post_checkout(&1, &2, opts),
          pre_checkin: &pre_checkin(&1, &2, &3, opts)
        ] ++ pool_opts
      else
        pool_opts
      end

    pool_opts_overrides = Keyword.take(opts, [:ownership_timeout])
    pool_opts = Keyword.merge(pool_opts, pool_opts_overrides)

    case DBConnection.Ownership.ownership_checkout(pool, pool_opts) do
      :ok ->
        if isolation = opts[:isolation] do
          set_transaction_isolation_level(repo, isolation)
        end

        :ok

      other ->
        other
    end
  end

  defp set_transaction_isolation_level(repo, isolation) do
    query = "SET TRANSACTION ISOLATION LEVEL #{isolation}"

    case Ecto.Adapters.SQL.query(repo, query, [], sandbox_subtransaction: false) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        checkin(repo, [])
        raise error
    end
  end

  @doc """
  Checks in the connection back into the sandbox pool.
  """
  def checkin(repo, _opts \\ []) when is_atom(repo) do
    %{pid: pool, opts: opts} = lookup_meta!(repo)
    DBConnection.Ownership.ownership_checkin(pool, opts)
  end

  @doc """
  Allows the `allow` process to use the same connection as `parent`.
  """
  def allow(repo, parent, allow, _opts \\ []) when is_atom(repo) do
    %{pid: pool, opts: opts} = lookup_meta!(repo)
    DBConnection.Ownership.ownership_allow(pool, parent, allow, opts)
  end

  @doc """
  Runs a function outside of the sandbox.
  """
  def unboxed_run(repo, fun) when is_atom(repo) do
    checkin(repo)
    checkout(repo, sandbox: false)

    try do
      fun.()
    after
      checkin(repo)
    end
  end

  defp lookup_meta!(repo) do
    %{opts: opts} = meta = Ecto.Adapter.lookup_meta(repo)

    if opts[:pool] != DBConnection.Ownership do
      raise """
      cannot invoke sandbox operation with pool #{inspect(opts[:pool])}.
      To use the SQL Sandbox, configure your repository pool as:

          pool: #{inspect(__MODULE__)}
      """
    end

    meta
  end

  defp post_checkout(conn_mod, conn_state, opts) do
    case conn_mod.handle_begin([mode: :transaction] ++ opts, conn_state) do
      {:ok, _, conn_state} ->
        {:ok, Connection, {conn_mod, conn_state, false, {[], []}}}

      {_error_or_disconnect, err, conn_state} ->
        {:disconnect, err, conn_mod, conn_state}
    end
  end

  defp pre_checkin(
         :checkin,
         Connection,
         {conn_mod, conn_state, _in_transaction?, _log_state},
         opts
       ) do
    case conn_mod.handle_rollback([mode: :transaction] ++ opts, conn_state) do
      {:ok, _, conn_state} ->
        {:ok, conn_mod, conn_state}

      {:idle, _conn_state} ->
        raise """
        Ecto SQL sandbox transaction was already committed/rolled back.

        The sandbox works by running each test in a transaction and closing the\
        transaction afterwards. However, the transaction has already terminated.\
        Your test code is likely committing or rolling back transactions manually,\
        either by invoking procedures or running custom SQL commands.

        One option is to manually checkout a connection without a sandbox:

            Ecto.Adapters.SQL.Sandbox.checkout(repo, sandbox: false)

        But remember you will have to undo any database changes performed by such tests.
        """

      {_error_or_disconnect, err, conn_state} ->
        {:disconnect, err, conn_mod, conn_state}
    end
  end

  defp pre_checkin(_, Connection, {conn_mod, conn_state, _in_transaction?, _log_state}, _opts) do
    {:ok, conn_mod, conn_state}
  end
end
