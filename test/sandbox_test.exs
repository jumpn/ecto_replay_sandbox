defmodule EctoReplaySandboxTest do
  use ExUnit.Case

  alias EctoReplaySandbox, as: Sandbox
  alias EctoReplaySandbox.Integration.{PoolRepo, TestRepo}
  alias EctoReplaySandbox.Integration.Post

  import ExUnit.CaptureLog

  describe "errors" do
    test "raises if repo is not started or not exist" do
      assert_raise RuntimeError,
                   ~r"could not lookup Ecto repo UnknownRepo because it was not started",
                   fn ->
                     Sandbox.mode(UnknownRepo, :manual)
                   end
    end

    test "raises if repo is not using sandbox" do
      assert_raise RuntimeError, ~r"cannot invoke sandbox operation with pool DBConnection", fn ->
        Sandbox.mode(PoolRepo, :manual)
      end

      assert_raise RuntimeError, ~r"cannot invoke sandbox operation with pool DBConnection", fn ->
        Sandbox.checkout(PoolRepo)
      end
    end

    test "include link to SQL sandbox on ownership errors" do
      assert_raise DBConnection.OwnershipError,
                   ~r"See Ecto.Adapters.SQL.Sandbox docs for more information.",
                   fn ->
                     TestRepo.all(Post)
                   end
    end
  end

  describe "mode" do
    test "uses the repository when checked out" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      Sandbox.checkout(TestRepo)
      assert TestRepo.all(Post) == []
      Sandbox.checkin(TestRepo)

      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end
    end

    test "uses the repository when allowed from another process" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      parent = self()

      Task.start_link(fn ->
        Sandbox.checkout(TestRepo)
        Sandbox.allow(TestRepo, self(), parent)
        send(parent, :allowed)
        Process.sleep(:infinity)
      end)

      assert_receive :allowed
      assert TestRepo.all(Post) == []
    end

    test "uses the repository when shared from another process" do
      Sandbox.checkout(TestRepo)
      Sandbox.mode(TestRepo, {:shared, self()})
      assert Task.async(fn -> TestRepo.all(Post) end) |> Task.await() == []
    after
      Sandbox.mode(TestRepo, :manual)
    end
  end

  test "runs inside a sandbox that is rolled back on checkin" do
    Sandbox.checkout(TestRepo)
    assert TestRepo.insert(%Post{})
    assert TestRepo.all(Post) != []
    Sandbox.checkin(TestRepo)
    Sandbox.checkout(TestRepo)
    assert TestRepo.all(Post) == []
    Sandbox.checkin(TestRepo)
  end

  test "runs inside a sandbox that may be disabled" do
    Sandbox.checkout(TestRepo, sandbox: false)
    assert TestRepo.insert(%Post{})
    assert TestRepo.all(Post) != []
    Sandbox.checkin(TestRepo)

    Sandbox.checkout(TestRepo)
    assert {1, _} = TestRepo.delete_all(Post)
    Sandbox.checkin(TestRepo)

    Sandbox.checkout(TestRepo, sandbox: false)
    assert {1, _} = TestRepo.delete_all(Post)
    Sandbox.checkin(TestRepo)
  end

  test "transaction works inside the sandbox" do
    Sandbox.checkout(TestRepo)

    TestRepo.transaction(fn ->
      TestRepo.all(Post)
    end)

    Sandbox.checkin(TestRepo)
  end

  test "works even with failed queries" do
    Sandbox.checkout(TestRepo)

    {:ok, _} = TestRepo.insert(%Post{}, skip_transaction: true)
    # This is a failed query but it should not taint the sandbox transaction
    {:error, _} = TestRepo.query("INVALID")
    {:ok, _} = TestRepo.insert(%Post{}, skip_transaction: true)
    assert TestRepo.all(Post) |> Enum.count() == 2

    Sandbox.checkin(TestRepo)
  end

  test "the failed transaction is properly rollbacked" do
    Sandbox.checkout(TestRepo)

    TestRepo.transaction(fn ->
      TestRepo.insert(%Post{})
      # This is a failed query to trigger a rollback
      {:error, _} = TestRepo.query("INVALID")
    end)

    assert TestRepo.all(Post) == []

    Sandbox.checkin(TestRepo)
  end

  test "work executed before failed transaction is still availaible" do
    Sandbox.checkout(TestRepo)

    {:ok, _} = TestRepo.insert(%Post{}, skip_transaction: true)

    TestRepo.transaction(fn ->
      # This is a failed query to trigger a rollback
      {:error, _} = TestRepo.query("INVALID")
    end)

    assert TestRepo.all(Post) != []

    Sandbox.checkin(TestRepo)
  end

  test "sanbox still works once a transaction with a failed changeset is rollbacked" do
    Sandbox.checkout(TestRepo)

    {:ok, _} = TestRepo.insert(%Post{id: 1}, skip_transaction: true)

    TestRepo.transaction(fn ->
      %Post{}
      |> Post.changeset(%{id: 1})
      |> TestRepo.insert()
    end)

    TestRepo.all(Post)

    Sandbox.checkin(TestRepo)
  end

  test "sanbox replays log in correct order" do
    Sandbox.checkout(TestRepo)

    {:ok, _post} = TestRepo.insert(%Post{}, skip_transaction: true)
    TestRepo.update_all(Post, set: [title: "New title"])
    TestRepo.update_all(Post, set: [title: "New title2"])

    # This is a failed query but it should not taint the sandbox transaction
    {:error, _} = TestRepo.query("INVALID")

    assert [post] = TestRepo.all(Post)
    assert post.title == "New title2"

    Sandbox.checkin(TestRepo)
  end

  test "works when preloading associations from another process" do
    Sandbox.checkout(TestRepo)
    assert TestRepo.insert(%Post{})
    parent = self()

    Task.start_link(fn ->
      Sandbox.allow(TestRepo, parent, self())
      assert [_] = TestRepo.all(Post) |> TestRepo.preload([:author, :comments])
      send(parent, :success)
    end)

    assert_receive :success
  end

  test "allows an ownership timeout to be passed for an individual `checkout` call" do
    log =
      capture_log(fn ->
        :ok = Sandbox.checkout(TestRepo, ownership_timeout: 20)

        Process.sleep(1000)

        assert_raise DBConnection.OwnershipError, fn ->
          TestRepo.all(Post)
        end
      end)

    assert log =~ ~r/timed out.*20ms/
  end
end
