defmodule PleromaRedux.Bench.SeedTest do
  use PleromaRedux.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Bench.Seed
  alias PleromaRedux.Object
  alias PleromaRedux.Relationship
  alias PleromaRedux.Repo
  alias PleromaRedux.User

  test "seed!/1 inserts a realistic dataset and returns counts" do
    summary =
      Seed.seed!(
        local_users: 2,
        remote_users: 3,
        days: 2,
        posts_per_day: 5,
        follows_per_user: 2,
        seed: 123,
        reset?: false
      )

    assert %{
             users: %{local: 2, remote: 3},
             objects: %{notes: 10},
             relationships: %{follows: 4}
           } = summary

    assert Repo.aggregate(User, :count, :id) == 5

    assert Repo.aggregate(from(o in Object, where: o.type == "Note"), :count, :id) == 10

    assert Repo.aggregate(from(r in Relationship, where: r.type == "Follow"), :count, :id) == 4
  end
end
