defmodule Egregoros.Bench.SeedTest do
  use Egregoros.DataCase, async: false

  alias Egregoros.Bench.Seed

  test "seed!/1 works with remote_users=0" do
    summary =
      Seed.seed!(
        local_users: 2,
        remote_users: 0,
        days: 1,
        posts_per_day: 5,
        follows_per_user: 0,
        reset?: true,
        seed: 123
      )

    assert summary.users.local == 2
    assert summary.users.remote == 0
    assert summary.objects.notes == 5
    assert summary.relationships.follows == 0
  end

  test "seed!/1 chunks insert_all to stay under Postgres parameter limits" do
    # With 9 columns per row, inserting > 7_281 rows in one query would exceed Postgres' 65_535
    # parameter limit. This ensures we keep chunking logic in place.
    notes = 7_400

    summary =
      Seed.seed!(
        local_users: 1,
        remote_users: 0,
        days: 1,
        posts_per_day: notes,
        follows_per_user: 0,
        reset?: true,
        seed: 123
      )

    assert summary.objects.notes == notes
  end
end

