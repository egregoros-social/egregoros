defmodule PleromaRedux.Bench.Seed do
  alias PleromaRedux.Keys
  alias PleromaRedux.Password
  alias PleromaRedux.Relationship
  alias PleromaRedux.Repo
  alias PleromaRedux.User
  alias PleromaRedux.Object
  alias PleromaReduxWeb.Endpoint

  @default_password "bench-password-1234"

  def seed!(opts \\ []) when is_list(opts) do
    opts = normalize_opts(opts)
    seed_rand(opts.seed)

    Repo.transaction(fn ->
      if opts.reset? do
        reset!()
      end

      now_usec = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      now_sec = DateTime.truncate(now_usec, :second)

      {local_users, remote_users} = insert_users(now_usec, opts)
      follows = insert_follow_relationships(now_sec, local_users, remote_users, opts)
      notes = insert_notes(now_usec, local_users, remote_users, opts)

      %{
        users: %{local: length(local_users), remote: length(remote_users)},
        objects: %{notes: notes},
        relationships: %{follows: follows}
      }
    end)
    |> case do
      {:ok, summary} -> summary
      {:error, reason} -> raise "bench seed failed: #{inspect(reason)}"
    end
  end

  defp reset! do
    Repo.delete_all(Relationship)
    Repo.delete_all(Object)
    Repo.delete_all(User)
  end

  defp insert_users(now, opts) do
    base = Endpoint.url()

    local_rows =
      for i <- 1..opts.local_users do
        nickname = "local#{i}"
        actor_ap_id = base <> "/users/" <> nickname
        {public_key, private_key} = Keys.generate_rsa_keypair()

        %{
          nickname: nickname,
          domain: nil,
          ap_id: actor_ap_id,
          inbox: actor_ap_id <> "/inbox",
          outbox: actor_ap_id <> "/outbox",
          public_key: public_key,
          private_key: private_key,
          local: true,
          email: "#{nickname}@example.com",
          password_hash: Password.hash(@default_password),
          inserted_at: now,
          updated_at: now
        }
      end

    {_count, local_users} =
      Repo.insert_all(User, local_rows, returning: [:ap_id, :local, :nickname])

    {shared_remote_public_key, _private} = Keys.generate_rsa_keypair()

    remote_rows =
      for i <- 1..opts.remote_users do
        nickname = "remote#{i}"
        domain = remote_domain(i)
        actor_ap_id = "https://#{domain}/users/#{nickname}"

        %{
          nickname: nickname,
          domain: domain,
          ap_id: actor_ap_id,
          inbox: actor_ap_id <> "/inbox",
          outbox: actor_ap_id <> "/outbox",
          public_key: shared_remote_public_key,
          private_key: nil,
          local: false,
          inserted_at: now,
          updated_at: now
        }
      end

    {_count, remote_users} =
      Repo.insert_all(User, remote_rows, returning: [:ap_id, :local, :nickname, :domain])

    {local_users, remote_users}
  end

  defp insert_follow_relationships(now, local_users, remote_users, opts) do
    remote_actor_ids = Enum.map(remote_users, & &1.ap_id)

    rows =
      local_users
      |> Enum.flat_map(fn local_user ->
        follow_targets = sample(remote_actor_ids, opts.follows_per_user)

        Enum.map(follow_targets, fn target ->
          %{
            type: "Follow",
            actor: local_user.ap_id,
            object: target,
            activity_ap_id: local_user.ap_id <> "/follow/" <> Ecto.UUID.generate(),
            inserted_at: now,
            updated_at: now
          }
        end)
      end)

    case rows do
      [] ->
        0

      rows ->
        {count, _} = Repo.insert_all(Relationship, rows, on_conflict: :nothing)
        count
    end
  end

  defp insert_notes(now, local_users, remote_users, opts) do
    actors = Enum.map(local_users ++ remote_users, & &1.ap_id)
    local_actor_ids = local_users |> Enum.map(& &1.ap_id) |> MapSet.new()

    start_dt =
      now
      |> DateTime.add(-opts.days * 86_400, :second)
      |> DateTime.truncate(:microsecond)

    {rows, notes_count} =
      0..(opts.days * opts.posts_per_day - 1)
      |> Enum.reduce({[], 0}, fn i, {rows, count} ->
        actor = Enum.at(actors, :rand.uniform(length(actors)) - 1)
        local? = MapSet.member?(local_actor_ids, actor)

        published =
          start_dt
          |> DateTime.add(div(i, opts.posts_per_day) * 86_400, :second)
          |> DateTime.add(:rand.uniform(86_400) - 1, :second)
          |> DateTime.truncate(:microsecond)

        ap_id = object_ap_id_for_actor(actor, local?)

        content = note_content(i)

        data = %{
          "id" => ap_id,
          "type" => "Note",
          "actor" => actor,
          "attributedTo" => actor,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => [actor <> "/followers"],
          "content" => content,
          "published" => DateTime.to_iso8601(published)
        }

        row = %{
          ap_id: ap_id,
          type: "Note",
          actor: actor,
          object: nil,
          data: data,
          published: published,
          local: local?,
          inserted_at: published,
          updated_at: published
        }

        {[row | rows], count + 1}
      end)

    if rows == [] do
      0
    else
      {_count, _} = Repo.insert_all(Object, rows)
      notes_count
    end
  end

  defp note_content(i) when is_integer(i) do
    words = [
      "hello",
      "world",
      "pleroma",
      "redux",
      "federation",
      "activitypub",
      "phoenix",
      "elixir"
    ]

    word1 = Enum.at(words, rem(i, length(words)))
    word2 = Enum.at(words, rem(i * 7 + 3, length(words)))

    "bench post #{i}: #{word1} #{word2} #bench"
  end

  defp object_ap_id_for_actor(_actor_ap_id, true) do
    Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()
  end

  defp object_ap_id_for_actor(actor_ap_id, false) do
    base =
      case URI.parse(actor_ap_id) do
        %URI{scheme: scheme, host: host} when is_binary(host) and host != "" ->
          scheme = if is_binary(scheme) and scheme != "", do: scheme, else: "https"
          scheme <> "://" <> host

        _ ->
          "https://remote.example"
      end

    base <> "/objects/" <> Ecto.UUID.generate()
  end

  defp remote_domain(i) when is_integer(i) and i > 0 do
    shard = rem(i - 1, 10) + 1
    "remote#{shard}.example"
  end

  defp sample(items, count) when is_list(items) and is_integer(count) and count > 0 do
    items
    |> Enum.shuffle()
    |> Enum.take(count)
  end

  defp sample(_items, _count), do: []

  defp normalize_opts(opts) do
    %{
      local_users: opts |> Keyword.get(:local_users, 10) |> normalize_int(0, 10_000),
      remote_users: opts |> Keyword.get(:remote_users, 200) |> normalize_int(0, 1_000_000),
      days: opts |> Keyword.get(:days, 365) |> normalize_int(0, 10_000),
      posts_per_day: opts |> Keyword.get(:posts_per_day, 200) |> normalize_int(0, 1_000_000),
      follows_per_user: opts |> Keyword.get(:follows_per_user, 50) |> normalize_int(0, 1_000_000),
      seed: opts |> Keyword.get(:seed),
      reset?: opts |> Keyword.get(:reset?, true)
    }
  end

  defp normalize_int(value, min, max) when is_integer(value) do
    value
    |> max(min)
    |> min(max)
  end

  defp normalize_int(_value, min, _max), do: min

  defp seed_rand(nil), do: :ok

  defp seed_rand(seed) when is_integer(seed) do
    :rand.seed(:exsss, {seed, seed, seed})
  end

  defp seed_rand(seed) when is_binary(seed) do
    case Integer.parse(seed) do
      {int, ""} -> seed_rand(int)
      _ -> :ok
    end
  end

  defp seed_rand(_), do: :ok
end
