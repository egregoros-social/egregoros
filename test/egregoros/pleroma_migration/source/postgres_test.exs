defmodule Egregoros.PleromaMigration.Source.PostgresTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.PleromaMigration.PostgresClient
  alias Egregoros.PleromaMigration.Source.Postgres

  setup do
    previous_impl = Application.get_env(:egregoros, PostgresClient)

    Application.put_env(:egregoros, PostgresClient, PostgresClient.Mock)

    on_exit(fn ->
      if is_nil(previous_impl) do
        Application.delete_env(:egregoros, PostgresClient)
      else
        Application.put_env(:egregoros, PostgresClient, previous_impl)
      end
    end)

    :ok
  end

  test "list_users/1 parses url options and maps remote users" do
    url = "postgres://user:pass@host:5432/pleroma_db"
    conn = {:conn, System.unique_integer([:positive])}

    user_id = FlakeId.get()
    inserted_at = ~N[2026-01-01 00:00:00]
    updated_at = ~N[2026-01-01 00:00:01]

    PostgresClient.Mock
    |> expect(:start_link, fn opts ->
      assert opts[:hostname] == "host"
      assert opts[:port] == 5432
      assert opts[:username] == "user"
      assert opts[:password] == "pass"
      assert opts[:database] == "pleroma_db"
      {:ok, conn}
    end)
    |> expect(:query!, fn ^conn, sql, [], opts ->
      assert opts[:timeout] == :infinity
      assert String.contains?(sql, "FROM users")

      %{
        rows: [
          [
            user_id,
            "bob@remote.example",
            "https://remote.example/users/bob",
            "https://remote.example/users/bob/inbox",
            "PUB",
            "PRIV",
            false,
            true,
            false,
            "bob@remote.example",
            "$pbkdf2-v2$stub",
            "Bob",
            "Bio",
            inserted_at,
            updated_at
          ]
        ]
      }
    end)
    |> expect(:stop, fn ^conn -> :ok end)

    assert {:ok, [user]} = Postgres.list_users(url: url)
    assert user.id == user_id
    assert user.nickname == "bob"
    assert user.domain == "remote.example"
    assert user.ap_id == "https://remote.example/users/bob"
    assert user.outbox == "https://remote.example/users/bob/outbox"
    assert user.private_key == "PRIV"
    assert user.admin == true
    assert user.locked == false
    assert %DateTime{} = user.inserted_at
    assert %DateTime{} = user.updated_at
    assert user.inserted_at.microsecond == {0, 6}
    assert user.updated_at.microsecond == {0, 6}
  end

  test "list_users/1 derives inbox/public_key for local users and normalizes microseconds" do
    url = "postgres://user:pass@host:5432/pleroma_db"
    conn = {:conn, System.unique_integer([:positive])}

    user_id = FlakeId.get()
    inserted_at = ~N[2026-01-01 00:00:00]
    updated_at = ~N[2026-01-01 00:00:01]

    private_key_pem = rsa_private_key_pem()

    PostgresClient.Mock
    |> expect(:start_link, fn _opts -> {:ok, conn} end)
    |> expect(:query!, fn ^conn, _sql, [], opts ->
      assert opts[:timeout] == :infinity

      %{
        rows: [
          [
            user_id,
            "bob",
            "https://pleroma.test/users/bob",
            nil,
            nil,
            private_key_pem,
            true,
            false,
            false,
            "bob@pleroma.test",
            "$pbkdf2-v2$stub",
            "Bob",
            "Bio",
            inserted_at,
            updated_at
          ]
        ]
      }
    end)
    |> expect(:stop, fn ^conn -> :ok end)

    assert {:ok, [user]} = Postgres.list_users(url: url)
    assert user.id == user_id
    assert user.nickname == "bob"
    assert user.domain == nil
    assert user.ap_id == "https://pleroma.test/users/bob"
    assert user.inbox == "https://pleroma.test/users/bob/inbox"
    assert user.outbox == "https://pleroma.test/users/bob/outbox"
    assert String.starts_with?(user.public_key, "-----BEGIN PUBLIC KEY-----")
    assert user.private_key == private_key_pem
    assert user.local == true
    assert user.admin == false
    assert user.locked == false
    assert user.inserted_at.microsecond == {0, 6}
    assert user.updated_at.microsecond == {0, 6}
  end

  test "list_statuses/1 maps Create and Announce activities" do
    url = "postgres://user:pass@host:5432/pleroma_db"
    conn = {:conn, System.unique_integer([:positive])}

    create_id = FlakeId.get()
    announce_id = FlakeId.get()
    inserted_at = ~N[2026-01-01 00:00:00]
    updated_at = ~N[2026-01-01 00:00:01]

    create = %{
      "id" => "https://example.com/activities/#{Ecto.UUID.generate()}",
      "type" => "Create",
      "actor" => "https://example.com/users/alice",
      "object" => "https://example.com/objects/#{Ecto.UUID.generate()}"
    }

    note = %{
      "id" => create["object"],
      "type" => "Note",
      "actor" => create["actor"],
      "content" => "hi"
    }

    announce = %{
      "id" => "https://example.com/activities/#{Ecto.UUID.generate()}",
      "type" => "Announce",
      "actor" => create["actor"],
      "object" => create["object"]
    }

    PostgresClient.Mock
    |> expect(:start_link, fn _opts -> {:ok, conn} end)
    |> expect(:query!, fn ^conn, sql, [], opts ->
      assert opts[:timeout] == :infinity
      assert String.contains?(sql, "JOIN objects")

      %{
        rows: [
          [
            create_id,
            create,
            true,
            inserted_at,
            updated_at,
            note
          ]
        ]
      }
    end)
    |> expect(:query!, fn ^conn, sql, [], opts ->
      assert opts[:timeout] == :infinity
      assert String.contains?(sql, "WHERE data->>'type' = 'Announce'")

      %{
        rows: [
          [
            announce_id,
            announce,
            false,
            inserted_at,
            updated_at
          ]
        ]
      }
    end)
    |> expect(:stop, fn ^conn -> :ok end)

    assert {:ok, statuses} = Postgres.list_statuses(url: url)

    assert Enum.any?(statuses, fn status ->
             status.activity_id == create_id and status.activity == create and
               status.object == note and
               status.local == true
           end)

    assert Enum.any?(statuses, fn status ->
             status.activity_id == announce_id and status.activity == announce and
               status.local == false
           end)

    assert Enum.all?(statuses, fn status ->
             match?(%DateTime{}, status.inserted_at) and match?(%DateTime{}, status.updated_at)
           end)

    assert Enum.all?(statuses, fn status ->
             status.inserted_at.microsecond == {0, 6} and status.updated_at.microsecond == {0, 6}
           end)
  end

  test "list_users/1 maps remote users when nickname has no domain part" do
    conn = {:conn, System.unique_integer([:positive])}
    user_id = FlakeId.get()

    inserted_at = DateTime.from_naive!(~N[2026-01-01 00:00:00.123], "Etc/UTC")
    updated_at = DateTime.from_naive!(~N[2026-01-01 00:00:01.456], "Etc/UTC")

    PostgresClient.Mock
    |> expect(:start_link, fn opts ->
      assert opts[:hostname] == "host"
      assert opts[:username] == "user"
      assert opts[:password] == "pass"
      assert opts[:database] == "pleroma_db"
      assert opts[:timeout] == 60_000
      assert opts[:pool_size] == 1
      {:ok, conn}
    end)
    |> expect(:query!, fn ^conn, _sql, [], _opts ->
      %{
        rows: [
          [
            user_id,
            "alice",
            "https://remote.example/users/alice",
            " ",
            " ",
            "not-pem",
            false,
            false,
            true,
            "alice@remote.example",
            "$pbkdf2-v2$stub",
            "Alice",
            "Bio",
            inserted_at,
            updated_at
          ]
        ]
      }
    end)
    |> expect(:stop, fn ^conn -> :ok end)

    assert {:ok, [user]} =
             Postgres.list_users(
               hostname: "host",
               username: "user",
               password: "pass",
               database: "pleroma_db"
             )

    assert user.nickname == "alice"
    assert user.domain == "remote.example"
    assert user.inbox == "https://remote.example/users/alice/inbox"
    assert user.outbox == "https://remote.example/users/alice/outbox"
    assert user.locked == true
    assert is_nil(user.public_key)
    assert user.inserted_at.microsecond == {123_000, 6}
    assert user.updated_at.microsecond == {456_000, 6}
  end

  test "list_users/1 handles non-binary nicknames for remote users" do
    url = "postgres://user:pass@host:5432/pleroma_db"
    conn = {:conn, System.unique_integer([:positive])}

    user_id = FlakeId.get()

    PostgresClient.Mock
    |> expect(:start_link, fn _opts -> {:ok, conn} end)
    |> expect(:query!, fn ^conn, _sql, [], _opts ->
      %{
        rows: [
          [
            user_id,
            nil,
            "https://remote.example/users/alice",
            nil,
            nil,
            nil,
            false,
            false,
            false,
            "alice@remote.example",
            "$pbkdf2-v2$stub",
            "Alice",
            "Bio",
            nil,
            nil
          ]
        ]
      }
    end)
    |> expect(:stop, fn ^conn -> :ok end)

    assert {:ok, [user]} = Postgres.list_users(url: url)
    assert user.nickname == ""
    assert user.domain == "remote.example"
    assert user.inbox == "https://remote.example/users/alice/inbox"
    assert user.outbox == "https://remote.example/users/alice/outbox"
  end

  test "list_users/1 returns an error when PostgresClient.start_link/1 fails" do
    PostgresClient.Mock
    |> expect(:start_link, fn _opts -> {:error, :boom} end)

    assert {:error, %MatchError{}} = Postgres.list_users(hostname: "host", database: "pleroma_db")
  end

  test "list_statuses/1 returns an error when PostgresClient.query!/4 raises and still stops conn" do
    conn = {:conn, System.unique_integer([:positive])}

    PostgresClient.Mock
    |> expect(:start_link, fn _opts -> {:ok, conn} end)
    |> expect(:query!, fn ^conn, _sql, [], _opts -> raise "boom" end)
    |> expect(:stop, fn ^conn -> :ok end)

    assert {:error, %RuntimeError{message: "boom"}} =
             Postgres.list_statuses(hostname: "host", database: "pleroma_db")
  end

  defp rsa_private_key_pem do
    key = :public_key.generate_key({:rsa, 1024, 65_537})

    :public_key.pem_entry_encode(:RSAPrivateKey, key)
    |> List.wrap()
    |> :public_key.pem_encode()
    |> IO.iodata_to_binary()
  end
end
