defmodule Egregoros.Users do
  import Ecto.Query

  alias Egregoros.Keys
  alias Egregoros.Password
  alias Egregoros.Relationship
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.VerifiableCredentials.AssertionMethod
  alias EgregorosWeb.Endpoint

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_user(%{ap_id: ap_id} = attrs) when is_binary(ap_id) do
    case get_by_ap_id(ap_id) do
      nil ->
        create_user(attrs)

      %User{} = user ->
        user
        |> User.changeset(attrs)
        |> Repo.update()
    end
  end

  def create_local_user(nickname) when is_binary(nickname) do
    base = Endpoint.url() <> "/users/" <> nickname
    {public_key, private_key} = Keys.generate_rsa_keypair()
    {ed25519_public_key, ed25519_private_key} = Keys.generate_ed25519_keypair()
    assertion_method = assertion_method_from_public_key(base, ed25519_public_key)

    create_user(%{
      nickname: nickname,
      ap_id: base,
      inbox: base <> "/inbox",
      outbox: base <> "/outbox",
      public_key: public_key,
      private_key: private_key,
      ed25519_private_key: ed25519_private_key,
      assertion_method: assertion_method,
      local: true
    })
  end

  def register_local_user(attrs) when is_map(attrs) do
    nickname = attrs |> Map.get(:nickname, "") |> to_string() |> String.trim()

    email =
      attrs
      |> Map.get(:email, nil)
      |> normalize_optional_string()

    password = attrs |> Map.get(:password, "") |> to_string()

    cond do
      nickname == "" ->
        {:error, :invalid_nickname}

      password == "" ->
        {:error, :invalid_password}

      String.length(password) < 8 ->
        {:error, :invalid_password}

      true ->
        base = Endpoint.url() <> "/users/" <> nickname
        {public_key, private_key} = Keys.generate_rsa_keypair()
        {ed25519_public_key, ed25519_private_key} = Keys.generate_ed25519_keypair()
        assertion_method = assertion_method_from_public_key(base, ed25519_public_key)

        create_user(%{
          nickname: nickname,
          ap_id: base,
          inbox: base <> "/inbox",
          outbox: base <> "/outbox",
          public_key: public_key,
          private_key: private_key,
          ed25519_private_key: ed25519_private_key,
          assertion_method: assertion_method,
          local: true,
          email: email,
          password_hash: Password.hash(password),
          name: Map.get(attrs, :name),
          bio: Map.get(attrs, :bio),
          avatar_url: Map.get(attrs, :avatar_url)
        })
    end
  end

  def register_local_user_with_passkey(attrs) when is_map(attrs) do
    nickname = attrs |> Map.get(:nickname, "") |> to_string() |> String.trim()

    email =
      attrs
      |> Map.get(:email, nil)
      |> normalize_optional_string()

    cond do
      nickname == "" ->
        {:error, :invalid_nickname}

      true ->
        base = Endpoint.url() <> "/users/" <> nickname
        {public_key, private_key} = Keys.generate_rsa_keypair()
        {ed25519_public_key, ed25519_private_key} = Keys.generate_ed25519_keypair()
        assertion_method = assertion_method_from_public_key(base, ed25519_public_key)

        create_user(%{
          nickname: nickname,
          ap_id: base,
          inbox: base <> "/inbox",
          outbox: base <> "/outbox",
          public_key: public_key,
          private_key: private_key,
          ed25519_private_key: ed25519_private_key,
          assertion_method: assertion_method,
          local: true,
          email: email,
          password_hash: nil,
          name: Map.get(attrs, :name),
          bio: Map.get(attrs, :bio),
          avatar_url: Map.get(attrs, :avatar_url)
        })
    end
  end

  def get_or_create_local_user(nickname) when is_binary(nickname) do
    nickname = String.trim(nickname)

    case get_by_nickname(nickname) do
      %User{} = user ->
        {:ok, user}

      nil ->
        Repo.transaction(fn ->
          lock_key = :erlang.phash2({__MODULE__, :local_user, nickname})
          _ = Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

          case get_by_nickname(nickname) do
            %User{} = user ->
              user

            nil ->
              case create_local_user(nickname) do
                {:ok, %User{} = user} -> user
                {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
              end
          end
        end)
        |> case do
          {:ok, %User{} = user} -> {:ok, user}
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def get_or_create_instance_actor(nickname, ap_id)
      when is_binary(nickname) and is_binary(ap_id) do
    nickname = String.trim(nickname)
    ap_id = String.trim(ap_id)

    if nickname == "" or ap_id == "" do
      {:error, :invalid_actor}
    else
      result =
        case get_by_ap_id(ap_id) do
          %User{} = user ->
            {:ok, user}

          nil ->
            Repo.transaction(fn ->
              lock_key = :erlang.phash2({__MODULE__, :instance_actor, nickname})
              _ = Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

              case get_by_ap_id(ap_id) do
                %User{} = user ->
                  user

                nil ->
                  case get_by_nickname(nickname) do
                    %User{} = user ->
                      case user
                           |> User.changeset(%{
                             ap_id: ap_id,
                             inbox: ap_id <> "/inbox",
                             outbox: ap_id <> "/outbox"
                           })
                           |> Repo.update() do
                        {:ok, %User{} = user} -> user
                        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
                      end

                    nil ->
                      case create_instance_actor(nickname, ap_id) do
                        {:ok, %User{} = user} -> user
                        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
                      end
                  end
              end
            end)
            |> case do
              {:ok, %User{} = user} -> {:ok, user}
              {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
              {:error, reason} -> {:error, reason}
            end
        end

      case result do
        {:ok, %User{} = user} -> ensure_instance_ed25519_key(user)
        other -> other
      end
    end
  end

  def get_or_create_instance_actor(_nickname, _ap_id), do: {:error, :invalid_actor}

  defp create_instance_actor(nickname, ap_id) when is_binary(nickname) and is_binary(ap_id) do
    {public_key, private_key} = Keys.generate_rsa_keypair()
    {ed25519_public_key, ed25519_private_key} = Keys.generate_ed25519_keypair()
    assertion_method = assertion_method_from_public_key(ap_id, ed25519_public_key)

    create_user(%{
      nickname: nickname,
      ap_id: ap_id,
      inbox: ap_id <> "/inbox",
      outbox: ap_id <> "/outbox",
      public_key: public_key,
      private_key: private_key,
      ed25519_private_key: ed25519_private_key,
      assertion_method: assertion_method,
      local: true
    })
  end

  defp ensure_instance_ed25519_key(%User{} = user) do
    cond do
      is_binary(user.ed25519_private_key) and not is_nil(user.assertion_method) ->
        {:ok, user}

      is_binary(user.ed25519_private_key) ->
        assertion_method = assertion_method_from_private_key(user.ap_id, user.ed25519_private_key)

        user
        |> User.changeset(%{assertion_method: assertion_method})
        |> Repo.update()

      true ->
        {ed25519_public_key, ed25519_private_key} = Keys.generate_ed25519_keypair()
        assertion_method = assertion_method_from_public_key(user.ap_id, ed25519_public_key)

        user
        |> User.changeset(%{
          ed25519_private_key: ed25519_private_key,
          assertion_method: assertion_method
        })
        |> Repo.update()
    end
  end

  defp assertion_method_from_public_key(ap_id, public_key) do
    case AssertionMethod.from_ed25519_public_key(ap_id, public_key) do
      {:ok, assertion_method} -> assertion_method
      _ -> nil
    end
  end

  defp assertion_method_from_private_key(ap_id, private_key) do
    case AssertionMethod.from_ed25519_private_key(ap_id, private_key) do
      {:ok, assertion_method} -> assertion_method
      _ -> nil
    end
  end

  def get_by_ap_id(nil), do: nil
  def get_by_ap_id(ap_id), do: Repo.get_by(User, ap_id: ap_id)

  def list_by_ap_ids(ap_ids) when is_list(ap_ids) do
    ap_ids =
      ap_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if ap_ids == [] do
      []
    else
      from(u in User, where: u.ap_id in ^ap_ids)
      |> Repo.all()
    end
  end

  def get(id) when is_binary(id) do
    id = String.trim(id)

    cond do
      id == "" ->
        nil

      true ->
        if flake_id?(id) do
          Repo.get(User, id)
        else
          nil
        end
    end
  end

  def get(_id), do: nil

  def get_by_nickname(nil), do: nil

  def get_by_nickname(nickname) when is_binary(nickname) do
    nickname = String.trim(nickname)
    Repo.get_by(User, nickname: nickname, local: true)
  end

  def get_by_nickname(_nickname), do: nil

  def get_by_nickname_and_domain(nickname, domain)
      when is_binary(nickname) and is_binary(domain) do
    nickname = String.trim(nickname)
    domain = String.trim(domain)

    Repo.get_by(User, nickname: nickname, domain: domain, local: false)
  end

  def get_by_nickname_and_domain(_nickname, _domain), do: nil

  def get_by_handle(handle) when is_binary(handle) do
    handle =
      handle
      |> String.trim()
      |> String.trim_leading("@")

    case String.split(handle, "@", parts: 2) do
      [nickname] when nickname != "" ->
        get_by_nickname(nickname)

      [nickname, domain] when nickname != "" and domain != "" ->
        get_by_nickname_and_domain(nickname, domain)

      _ ->
        nil
    end
  end

  def get_by_handle(_handle), do: nil

  def get_by_email(nil), do: nil

  def get_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.trim(email))
  end

  def authenticate_local_user(nickname, password)
      when is_binary(nickname) and is_binary(password) do
    nickname = String.trim(nickname)

    with %User{local: true, password_hash: hash} = user when is_binary(hash) <-
           get_by_nickname(nickname),
         true <- Password.verify(password, hash) do
      user =
        if Password.pleroma_hash?(hash) do
          case user
               |> User.changeset(%{password_hash: Password.hash(password)})
               |> Repo.update() do
            {:ok, %User{} = updated} -> updated
            {:error, _changeset} -> user
          end
        else
          user
        end

      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def set_admin(%User{local: true} = user, admin) when is_boolean(admin) do
    user
    |> User.changeset(%{admin: admin})
    |> Repo.update()
  end

  def set_admin(%User{}, _admin), do: {:error, :not_local}
  def set_admin(_user, _admin), do: {:error, :invalid_user}

  def update_profile(%User{} = user, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_optional_email()
      |> drop_privilege_escalation_keys()

    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def update_password(%User{} = user, current_password, new_password)
      when is_binary(current_password) and is_binary(new_password) do
    cond do
      user.password_hash == nil ->
        {:error, :unauthorized}

      not Password.verify(current_password, user.password_hash) ->
        {:error, :unauthorized}

      String.length(new_password) < 8 ->
        {:error, :invalid_password}

      true ->
        user
        |> User.changeset(%{password_hash: Password.hash(new_password)})
        |> Repo.update()
    end
  end

  def bump_last_activity_at(actor_ap_id, at \\ nil)

  def bump_last_activity_at(actor_ap_id, at) when is_binary(actor_ap_id) do
    actor_ap_id = String.trim(actor_ap_id)

    cond do
      actor_ap_id == "" ->
        :ok

      at == nil ->
        bump_last_activity_at(actor_ap_id, DateTime.utc_now())

      match?(%DateTime{}, at) ->
        at = DateTime.truncate(at, :microsecond)

        from(u in User,
          where: u.ap_id == ^actor_ap_id,
          update: [
            set: [
              last_activity_at:
                fragment(
                  "GREATEST(COALESCE(?, ?), ?)",
                  u.last_activity_at,
                  ^at,
                  ^at
                )
            ]
          ]
        )
        |> Repo.update_all([])

        :ok

      true ->
        :ok
    end
  end

  def bump_last_activity_at(_actor_ap_id, _at), do: :ok

  def bump_notifications_last_seen_id(%User{} = user, last_seen_id)
      when is_binary(last_seen_id) do
    last_seen_id = String.trim(last_seen_id)

    if flake_id?(last_seen_id) do
      from(u in User,
        where: u.id == ^user.id,
        update: [
          set: [
            notifications_last_seen_id:
              fragment(
                "GREATEST(COALESCE(?, ?), ?)",
                u.notifications_last_seen_id,
                type(^last_seen_id, FlakeId.Ecto.Type),
                type(^last_seen_id, FlakeId.Ecto.Type)
              )
          ]
        ]
      )
      |> Repo.update_all([])
    end

    :ok
  end

  def bump_notifications_last_seen_id(_user, _last_seen_id), do: :ok

  def search(query, opts \\ []) when is_binary(query) and is_list(opts) do
    query = String.trim(query)
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    current_user_ap_id = extract_current_user_ap_id(opts)

    if query == "" do
      []
    else
      pattern = "%" <> query <> "%"

      follow_query =
        if is_binary(current_user_ap_id) and current_user_ap_id != "" do
          from(r in Relationship,
            where:
              r.actor == ^current_user_ap_id and
                r.type in ["Follow", "FollowRequest"],
            distinct: r.object,
            select: %{object: r.object, followed: true}
          )
        else
          from(r in Relationship,
            where: false,
            select: %{object: r.object, followed: true}
          )
        end

      exact = query
      prefix = query <> "%"
      contains = "%" <> query <> "%"

      from(u in User,
        as: :user,
        where: ilike(u.nickname, ^pattern) or ilike(u.name, ^pattern),
        left_join: f in subquery(follow_query),
        on: f.object == u.ap_id,
        order_by: [
          asc:
            fragment(
              """
              CASE
                WHEN lower(?) = lower(?) THEN 0
                WHEN lower(?) LIKE lower(?) THEN 1
                WHEN lower(coalesce(?, '')) = lower(?) THEN 2
                WHEN lower(coalesce(?, '')) LIKE lower(?) THEN 3
                WHEN lower(?) LIKE lower(?) THEN 4
                WHEN lower(coalesce(?, '')) LIKE lower(?) THEN 5
                ELSE 6
              END
              """,
              u.nickname,
              ^exact,
              u.nickname,
              ^prefix,
              u.name,
              ^exact,
              u.name,
              ^prefix,
              u.nickname,
              ^contains,
              u.name,
              ^contains
            ),
          desc_nulls_last: f.followed,
          desc_nulls_last: u.last_activity_at,
          asc: u.nickname
        ],
        limit: ^limit
      )
      |> Repo.all()
    end
  end

  defp normalize_limit(limit) when is_integer(limit) do
    limit
    |> max(1)
    |> min(40)
  end

  defp normalize_limit(_), do: 20

  defp normalize_optional_email(%{} = attrs) do
    case Map.fetch(attrs, "email") do
      {:ok, value} ->
        Map.put(attrs, "email", normalize_optional_string(value))

      :error ->
        case Map.fetch(attrs, :email) do
          {:ok, value} -> Map.put(attrs, :email, normalize_optional_string(value))
          :error -> attrs
        end
    end
  end

  defp normalize_optional_email(attrs), do: attrs

  defp drop_privilege_escalation_keys(%{} = attrs) do
    attrs
    |> Map.delete("admin")
    |> Map.delete(:admin)
  end

  defp drop_privilege_escalation_keys(attrs), do: attrs

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) do
    value = value |> to_string() |> String.trim()
    if value == "", do: nil, else: value
  end

  defp extract_current_user_ap_id(opts) when is_list(opts) do
    case Keyword.get(opts, :current_user) do
      %User{ap_id: ap_id} when is_binary(ap_id) and ap_id != "" -> ap_id
      _ -> nil
    end
  end

  defp extract_current_user_ap_id(_opts), do: nil

  def search_mentions(query, opts \\ [])

  def search_mentions(query, opts) when is_binary(query) and is_list(opts) do
    query =
      query
      |> String.trim()
      |> String.trim_leading("@")

    limit = opts |> Keyword.get(:limit, 8) |> normalize_limit()
    current_user_ap_id = extract_current_user_ap_id(opts)

    if query == "" do
      []
    else
      if String.contains?(query, "@") do
        search_mentions_with_domain(query, limit, current_user_ap_id)
      else
        search(query, limit: limit, current_user: Keyword.get(opts, :current_user))
      end
    end
  end

  def search_mentions(_query, _opts), do: []

  defp search_mentions_with_domain(query, limit, current_user_ap_id)
       when is_binary(query) and is_integer(limit) do
    [nickname_part, domain_part] = String.split(query, "@", parts: 2)

    nickname_part = String.trim(nickname_part)
    domain_part = String.trim(domain_part)

    nickname_like = nickname_part <> "%"
    domain_like = domain_part <> "%"

    follow_query =
      if is_binary(current_user_ap_id) and current_user_ap_id != "" do
        from(r in Relationship,
          where:
            r.actor == ^current_user_ap_id and
              r.type in ["Follow", "FollowRequest"],
          distinct: r.object,
          select: %{object: r.object, followed: true}
        )
      else
        from(r in Relationship,
          where: false,
          select: %{object: r.object, followed: true}
        )
      end

    remote_matches =
      from(u in User,
        as: :user,
        where:
          u.local == false and ilike(u.nickname, ^nickname_like) and ilike(u.domain, ^domain_like),
        left_join: f in subquery(follow_query),
        on: f.object == u.ap_id,
        order_by: [
          desc_nulls_last: f.followed,
          desc_nulls_last: u.last_activity_at,
          asc: u.nickname
        ],
        limit: ^limit
      )
      |> Repo.all()

    local_matches =
      if nickname_part != "" and local_domain_matches_prefix?(domain_part) do
        from(u in User,
          as: :user,
          where: u.local == true and ilike(u.nickname, ^nickname_like),
          left_join: f in subquery(follow_query),
          on: f.object == u.ap_id,
          order_by: [
            desc_nulls_last: f.followed,
            desc_nulls_last: u.last_activity_at,
            asc: u.nickname
          ],
          limit: ^limit
        )
        |> Repo.all()
      else
        []
      end

    (local_matches ++ remote_matches)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(limit)
  end

  defp search_mentions_with_domain(_query, _limit, _current_user_ap_id), do: []

  defp local_domain_matches_prefix?(domain_part) when is_binary(domain_part) do
    domain_part = domain_part |> String.trim() |> String.downcase()

    if domain_part == "" do
      false
    else
      Enum.any?(local_domains(), &String.starts_with?(&1, domain_part))
    end
  end

  defp local_domain_matches_prefix?(_domain_part), do: false

  defp local_domains do
    case URI.parse(Endpoint.url()) do
      %URI{host: host} when is_binary(host) and host != "" ->
        host = String.downcase(host)

        domains =
          case URI.parse(Endpoint.url()) do
            %URI{port: port} when is_integer(port) and port > 0 ->
              [host, host <> ":" <> Integer.to_string(port)]

            _ ->
              [host]
          end

        Enum.uniq(domains)

      _ ->
        []
    end
  end

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)

    cond do
      id == "" ->
        false

      byte_size(id) < 18 ->
        false

      true ->
        try do
          match?(<<_::128>>, FlakeId.from_string(id))
        rescue
          _ -> false
        end
    end
  end

  defp flake_id?(_id), do: false
end
