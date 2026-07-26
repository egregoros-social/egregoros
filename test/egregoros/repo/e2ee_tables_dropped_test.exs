defmodule Egregoros.Repo.E2EETablesDroppedTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Repo

  @e2ee_tables ~w(e2ee_keys e2ee_key_wrappers e2ee_actor_keys)

  test "the e2ee tables no longer exist" do
    {:ok, %{rows: rows}} =
      Repo.query(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)",
        [@e2ee_tables]
      )

    assert rows == []
  end
end
