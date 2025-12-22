defmodule PleromaRedux.UsersRaceTest do
  use PleromaRedux.DataCase, async: false

  alias PleromaRedux.User
  alias PleromaRedux.Users

  test "get_or_create_local_user is race-safe" do
    nickname = "race-user"
    parent = self()

    tasks =
      for _ <- 1..6 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> :ok
          end

          Users.get_or_create_local_user(nickname)
        end)
      end

    for _ <- tasks do
      assert_receive {:ready, _pid}, 5_000
    end

    Enum.each(tasks, fn task -> send(task.pid, :go) end)

    results = Enum.map(tasks, &Task.await(&1, 60_000))

    assert Enum.all?(results, &match?({:ok, %User{}}, &1))

    ids =
      results
      |> Enum.map(fn {:ok, user} -> user.id end)
      |> Enum.uniq()

    assert length(ids) == 1
    assert Repo.aggregate(User, :count, :id) == 1
  end
end
