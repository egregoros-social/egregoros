defmodule FederationBoxTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 240_000

  @poll_interval_ms 1_000
  @as_public "https://www.w3.org/ns/activitystreams#Public"

  setup_all do
    scheme = fedtest_scheme()

    egregoros_domain = System.get_env("FEDTEST_EGREGOROS_DOMAIN", "egregoros.test")

    egregoros_base_url =
      System.get_env("FEDTEST_EGREGOROS_BASE_URL", "#{scheme}://#{egregoros_domain}")

    issuer_domain = System.get_env("FEDTEST_EGREGOROS_ISSUER_DOMAIN", "egregoros2.test")

    issuer_base_url =
      System.get_env("FEDTEST_EGREGOROS_ISSUER_BASE_URL", "#{scheme}://#{issuer_domain}")

    password = System.get_env("FEDTEST_PASSWORD", "password")

    alice_nickname = System.get_env("FEDTEST_ALICE_NICKNAME", "alice")
    issuer_nickname = System.get_env("FEDTEST_EGREGOROS_ISSUER_NICKNAME", "issuer")
    issuer_password = System.get_env("FEDTEST_EGREGOROS_ISSUER_PASSWORD", password)
    badge_type = System.get_env("FEDTEST_BADGE_TYPE", "fedbox-badge")

    bob_handle = System.get_env("FEDTEST_PLEROMA_HANDLE", "@bob@pleroma.test")
    dave_handle = System.get_env("FEDTEST_PLEROMA_SECOND_HANDLE", "@dave@pleroma.test")
    carol_handle = System.get_env("FEDTEST_MASTODON_HANDLE", "@carol@mastodon.test")

    %{username: bob_username, domain: bob_domain} = parse_handle!(bob_handle)
    %{username: dave_username, domain: dave_domain} = parse_handle!(dave_handle)
    %{username: carol_username, domain: carol_domain} = parse_handle!(carol_handle)

    pleroma_base_url = "#{scheme}://#{bob_domain}"
    mastodon_base_url = "#{scheme}://#{carol_domain}"

    _ = register_user!(egregoros_base_url, egregoros_domain, alice_nickname, password)
    session = login_user!(egregoros_base_url, alice_nickname, password)

    redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
    scopes = "read write follow"

    %{client_id: client_id, client_secret: client_secret} =
      create_oauth_app!(egregoros_base_url, scopes)

    auth_code =
      authorize_oauth_app!(egregoros_base_url, session, client_id, redirect_uri, scopes)

    access_token =
      exchange_auth_code!(egregoros_base_url, client_id, client_secret, redirect_uri, auth_code)

    issuer_session = login_user!(issuer_base_url, issuer_nickname, issuer_password)

    %{client_id: issuer_client_id, client_secret: issuer_client_secret} =
      create_oauth_app!(issuer_base_url, scopes)

    issuer_auth_code =
      authorize_oauth_app!(
        issuer_base_url,
        issuer_session,
        issuer_client_id,
        redirect_uri,
        scopes
      )

    issuer_access_token =
      exchange_auth_code!(
        issuer_base_url,
        issuer_client_id,
        issuer_client_secret,
        redirect_uri,
        issuer_auth_code
      )

    alice_actor_id =
      wait_until!(
        fn -> webfinger_self_href(alice_nickname, egregoros_domain) end,
        "webfinger ready #{alice_nickname}@#{egregoros_domain}"
      )

    alice_actor_id_variants = actor_id_variants(alice_actor_id)
    alice_handle = "@#{alice_nickname}@#{egregoros_domain}"

    issuer_actor_id =
      wait_until!(
        fn -> webfinger_self_href(issuer_nickname, issuer_domain) end,
        "webfinger ready #{issuer_nickname}@#{issuer_domain}"
      )

    issuer_actor_id_variants = actor_id_variants(issuer_actor_id)
    issuer_handle = "@#{issuer_nickname}@#{issuer_domain}"

    bob_actor_id =
      wait_until!(
        fn -> webfinger_self_href(bob_username, bob_domain) end,
        "webfinger ready #{bob_handle}"
      )

    dave_actor_id =
      wait_until!(
        fn -> webfinger_self_href(dave_username, dave_domain) end,
        "webfinger ready #{dave_handle}"
      )

    carol_actor_id =
      wait_until!(
        fn -> webfinger_self_href(carol_username, carol_domain) end,
        "webfinger ready #{carol_handle}"
      )

    bob_actor_id_variants = actor_id_variants(bob_actor_id)
    dave_actor_id_variants = actor_id_variants(dave_actor_id)
    carol_actor_id_variants = actor_id_variants(carol_actor_id)

    %{client_id: bob_client_id, client_secret: bob_client_secret} =
      create_oauth_app!(pleroma_base_url, scopes)

    bob_access_token =
      password_grant_token!(
        pleroma_base_url,
        bob_client_id,
        bob_client_secret,
        [bob_username, "#{bob_username}@#{bob_domain}"],
        password,
        scopes
      )

    dave_access_token =
      password_grant_token!(
        pleroma_base_url,
        bob_client_id,
        bob_client_secret,
        [dave_username, "#{dave_username}@#{dave_domain}"],
        password,
        scopes
      )

    %{client_id: carol_client_id, client_secret: carol_client_secret} =
      create_oauth_app!(mastodon_base_url, scopes)

    carol_session =
      mastodon_sign_in!(mastodon_base_url, "#{carol_username}@#{carol_domain}", password)

    carol_auth_code =
      authorize_rails_oauth_app!(
        mastodon_base_url,
        carol_session,
        carol_client_id,
        redirect_uri,
        scopes
      )

    carol_access_token =
      exchange_auth_code!(
        mastodon_base_url,
        carol_client_id,
        carol_client_secret,
        redirect_uri,
        carol_auth_code
      )

    {:ok,
     %{
       egregoros_base_url: egregoros_base_url,
       access_token: access_token,
       issuer_base_url: issuer_base_url,
       issuer_access_token: issuer_access_token,
       alice_handle: alice_handle,
       alice_actor_id: alice_actor_id,
       alice_actor_id_variants: alice_actor_id_variants,
       issuer_handle: issuer_handle,
       issuer_actor_id: issuer_actor_id,
       issuer_actor_id_variants: issuer_actor_id_variants,
       badge_type: badge_type,
       bob_handle: bob_handle,
       bob_access_token: bob_access_token,
       bob_actor_id: bob_actor_id,
       bob_actor_id_variants: bob_actor_id_variants,
       dave_handle: dave_handle,
       dave_access_token: dave_access_token,
       dave_actor_id: dave_actor_id,
       dave_actor_id_variants: dave_actor_id_variants,
       pleroma_base_url: pleroma_base_url,
       carol_handle: carol_handle,
       carol_access_token: carol_access_token,
       carol_actor_id_variants: carol_actor_id_variants,
       mastodon_base_url: mastodon_base_url
     }}
  end

  test "outgoing follow is accepted by pleroma", ctx do
    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )
  end

  test "outgoing follow is accepted by mastodon", ctx do
    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )
  end

  test "receives posts from followed accounts", ctx do
    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    unique = unique_token()
    bob_text = "fedbox: hello from bob #{unique}"
    carol_text = "fedbox: hello from carol #{unique}"

    _ = create_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_text)
    _ = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)

    wait_until!(
      fn -> home_timeline_contains?(ctx.egregoros_base_url, ctx.access_token, bob_text) end,
      "egregoros received pleroma post"
    )

    wait_until!(
      fn -> home_timeline_contains?(ctx.egregoros_base_url, ctx.access_token, carol_text) end,
      "egregoros received mastodon post"
    )
  end

  @tag :vc
  test "badge issuance across egregoros instances can be accepted", ctx do
    %{"offer_id" => offer_id, "credential_id" => credential_id} =
      issue_badge!(
        ctx.issuer_base_url,
        ctx.issuer_access_token,
        ctx.badge_type,
        ctx.alice_actor_id
      )

    wait_until!(
      fn -> accept_offer?(ctx.egregoros_base_url, ctx.access_token, offer_id) end,
      "egregoros accepted badge offer"
    )

    wait_until!(
      fn -> credential_public_with_proof?(ctx.issuer_base_url, credential_id) end,
      "issuer credential proof attached"
    )
  end

  @tag :vc
  test "badge issuance across egregoros instances can be rejected", ctx do
    %{"offer_id" => offer_id, "credential_id" => credential_id} =
      issue_badge!(
        ctx.issuer_base_url,
        ctx.issuer_access_token,
        ctx.badge_type,
        ctx.alice_actor_id
      )

    wait_until!(
      fn -> reject_offer?(ctx.egregoros_base_url, ctx.access_token, offer_id) end,
      "egregoros rejected badge offer"
    )

    wait_until!(
      fn -> credential_not_public?(ctx.issuer_base_url, credential_id) end,
      "issuer credential remains private"
    )
  end

  test "migration: imported Pleroma statuses preserve their ids", ctx do
    seed_text = System.get_env("FEDTEST_MIGRATION_SEED_TEXT", "fedbox: pleroma migration seed")

    pleroma_status =
      wait_until!(
        fn -> find_status_by_content(ctx.pleroma_base_url, ctx.bob_access_token, seed_text) end,
        "pleroma seed status exists"
      )

    pleroma_status_id = pleroma_status["id"]

    resp =
      req_get!(
        ctx.egregoros_base_url <> "/api/v1/statuses/" <> pleroma_status_id,
        headers: [{"authorization", "Bearer " <> ctx.access_token}]
      )

    assert resp.status in 200..299

    egregoros_status = ensure_json!(resp.body)

    assert egregoros_status["id"] == pleroma_status_id

    assert is_binary(egregoros_status["content"]) and
             String.contains?(egregoros_status["content"], seed_text)
  end

  test "polls: receives polls from followed accounts", ctx do
    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    unique = unique_token()
    bob_text = "fedbox: poll from bob #{unique}"
    carol_text = "fedbox: poll from carol #{unique}"

    _ = create_poll_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_text, ["yes", "no"])

    _ =
      create_poll_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text, [
        "cats",
        "dogs"
      ])

    bob_status =
      wait_until!(
        fn -> find_status_by_content(ctx.egregoros_base_url, ctx.access_token, bob_text) end,
        "egregoros received pleroma poll"
      )

    carol_status =
      wait_until!(
        fn -> find_status_by_content(ctx.egregoros_base_url, ctx.access_token, carol_text) end,
        "egregoros received mastodon poll"
      )

    assert_poll_options!(bob_status, ["yes", "no"])
    assert_poll_options!(carol_status, ["cats", "dogs"])
  end

  test "polls: remote receives our polls (pleroma + mastodon)", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.pleroma_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: poll from alice #{unique}"

    alice_status =
      create_poll_status!(ctx.egregoros_base_url, ctx.access_token, alice_text, ["tea", "coffee"])

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    pleroma_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.pleroma_base_url,
            ctx.bob_access_token,
            alice_uri_variants
          )
        end,
        "pleroma received alice poll"
      )

    mastodon_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice poll"
      )

    assert_poll_options!(pleroma_status, ["tea", "coffee"])
    assert_poll_options!(mastodon_status, ["tea", "coffee"])
  end

  test "polls: remote receives our poll with media attachments", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.pleroma_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    media_id = upload_test_png!(ctx.egregoros_base_url, ctx.access_token)

    alice_text = "fedbox: poll with media #{unique}"

    alice_status =
      create_poll_status!(
        ctx.egregoros_base_url,
        ctx.access_token,
        alice_text,
        ["on", "off"],
        media_ids: [media_id]
      )

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    pleroma_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.pleroma_base_url,
            ctx.bob_access_token,
            alice_uri_variants
          )
        end,
        "pleroma received alice poll with media"
      )

    mastodon_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice poll with media"
      )

    assert_poll_options!(pleroma_status, ["on", "off"])
    assert_poll_options!(mastodon_status, ["on", "off"])

    assert length(Map.get(pleroma_status, "media_attachments", [])) > 0
    assert length(Map.get(mastodon_status, "media_attachments", [])) > 0
  end

  test "polls: remote receives our scheduled poll", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.pleroma_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    scheduled_at =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    alice_text = "fedbox: scheduled poll #{unique}"

    _scheduled_status =
      create_poll_status!(
        ctx.egregoros_base_url,
        ctx.access_token,
        alice_text,
        ["one", "two"],
        scheduled_at: scheduled_at
      )

    alice_status =
      wait_until!(
        fn -> find_status_by_content(ctx.egregoros_base_url, ctx.access_token, alice_text) end,
        "egregoros published scheduled poll",
        180_000
      )

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    pleroma_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.pleroma_base_url,
            ctx.bob_access_token,
            alice_uri_variants
          )
        end,
        "pleroma received alice scheduled poll"
      )

    mastodon_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice scheduled poll"
      )

    assert_poll_options!(pleroma_status, ["one", "two"])
    assert_poll_options!(mastodon_status, ["one", "two"])
  end

  test "polls: receives votes from pleroma and mastodon", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.pleroma_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: poll vote me #{unique}"

    alice_status =
      create_poll_status!(ctx.egregoros_base_url, ctx.access_token, alice_text, ["left", "right"])

    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    bob_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma_base_url, ctx.bob_access_token, alice_uri_variants)
        end,
        "pleroma received alice poll vote-me post"
      )

    carol_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice poll vote-me post"
      )

    bob_poll_id = bob_status |> Map.fetch!("poll") |> Map.fetch!("id")
    carol_poll_id = carol_status |> Map.fetch!("poll") |> Map.fetch!("id")

    _ = vote_on_poll!(ctx.pleroma_base_url, ctx.bob_access_token, bob_poll_id, [0])
    _ = vote_on_poll!(ctx.mastodon_base_url, ctx.carol_access_token, carol_poll_id, [1])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)
        poll_votes = poll_option_votes(status)

        if poll_votes == [1, 1] do
          true
        else
          false
        end
      end,
      "egregoros received votes from pleroma + mastodon"
    )
  end

  test "polls: remote receives our votes (pleroma + mastodon)", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    bob_text = "fedbox: poll from bob vote #{unique}"
    carol_text = "fedbox: poll from carol vote #{unique}"

    bob_status =
      create_poll_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_text, ["yes", "no"])

    carol_status =
      create_poll_status!(
        ctx.mastodon_base_url,
        ctx.carol_access_token,
        carol_text,
        ["tea", "coffee"]
      )

    bob_status_id = bob_status["id"]
    carol_status_id = carol_status["id"]

    egregoros_bob_status =
      wait_until!(
        fn -> find_status_by_content(ctx.egregoros_base_url, ctx.access_token, bob_text) end,
        "egregoros received bob poll"
      )

    egregoros_carol_status =
      wait_until!(
        fn -> find_status_by_content(ctx.egregoros_base_url, ctx.access_token, carol_text) end,
        "egregoros received carol poll"
      )

    egregoros_bob_poll_id = egregoros_bob_status |> Map.fetch!("poll") |> Map.fetch!("id")
    egregoros_carol_poll_id = egregoros_carol_status |> Map.fetch!("poll") |> Map.fetch!("id")

    _ = vote_on_poll!(ctx.egregoros_base_url, ctx.access_token, egregoros_bob_poll_id, [0])
    _ = vote_on_poll!(ctx.egregoros_base_url, ctx.access_token, egregoros_carol_poll_id, [1])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_status_id)
        poll_votes = poll_option_votes(status)

        if poll_votes == [1, 0] do
          true
        else
          false
        end
      end,
      "pleroma received alice vote"
    )

    wait_until!(
      fn ->
        status = fetch_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_status_id)
        poll_votes = poll_option_votes(status)

        if poll_votes == [0, 1] do
          true
        else
          false
        end
      end,
      "mastodon received alice vote"
    )
  end

  test "receives likes from mastodon on our posts", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: like me #{unique}"
    alice_status = create_status!(ctx.egregoros_base_url, ctx.access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    mastodon_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice post"
      )

    favourite_status!(ctx.mastodon_base_url, ctx.carol_access_token, mastodon_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)
        favourites_count = Map.get(status, "favourites_count", 0)
        is_integer(favourites_count) and favourites_count > 0
      end,
      "egregoros received mastodon like"
    )
  end

  test "receives likes from pleroma on our posts", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.pleroma_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    alice_text = "fedbox: like me (pleroma) #{unique}"
    alice_status = create_status!(ctx.egregoros_base_url, ctx.access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    pleroma_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma_base_url, ctx.bob_access_token, alice_uri_variants)
        end,
        "pleroma received alice post"
      )

    favourite_status!(ctx.pleroma_base_url, ctx.bob_access_token, pleroma_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)
        favourites_count = Map.get(status, "favourites_count", 0)
        is_integer(favourites_count) and favourites_count > 0
      end,
      "egregoros received pleroma like"
    )
  end

  test "remote receives our likes (pleroma)", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    bob_text = "fedbox: like this (pleroma) #{unique}"
    bob_status = create_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_text)
    bob_status_id = bob_status["id"]

    bob_uri_variants =
      bob_status
      |> status_uri()
      |> actor_id_variants()

    egregoros_bob_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.egregoros_base_url, ctx.access_token, bob_uri_variants)
        end,
        "egregoros received bob post"
      )

    favourite_status!(ctx.egregoros_base_url, ctx.access_token, egregoros_bob_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_status_id)
        favourites_count = Map.get(status, "favourites_count", 0)
        is_integer(favourites_count) and favourites_count > 0
      end,
      "pleroma received alice like"
    )
  end

  test "remote receives our likes (mastodon)", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    carol_text = "fedbox: like this (mastodon) #{unique}"
    carol_status = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)
    carol_status_id = carol_status["id"]

    carol_uri_variants =
      carol_status
      |> status_uri()
      |> actor_id_variants()

    egregoros_carol_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.egregoros_base_url, ctx.access_token, carol_uri_variants)
        end,
        "egregoros received carol post"
      )

    favourite_status!(ctx.egregoros_base_url, ctx.access_token, egregoros_carol_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_status_id)
        favourites_count = Map.get(status, "favourites_count", 0)
        is_integer(favourites_count) and favourites_count > 0
      end,
      "mastodon received alice like"
    )
  end

  test "receives boosts from mastodon on our posts", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: boost me #{unique}"
    alice_status = create_status!(ctx.egregoros_base_url, ctx.access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    mastodon_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice post"
      )

    reblog_status!(ctx.mastodon_base_url, ctx.carol_access_token, mastodon_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)
        reblogs_count = Map.get(status, "reblogs_count", 0)
        is_integer(reblogs_count) and reblogs_count > 0
      end,
      "egregoros received mastodon boost"
    )
  end

  test "receives boosts from pleroma on our posts", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.pleroma_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    alice_text = "fedbox: boost me (pleroma) #{unique}"
    alice_status = create_status!(ctx.egregoros_base_url, ctx.access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    pleroma_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma_base_url, ctx.bob_access_token, alice_uri_variants)
        end,
        "pleroma received alice post"
      )

    reblog_status!(ctx.pleroma_base_url, ctx.bob_access_token, pleroma_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)
        reblogs_count = Map.get(status, "reblogs_count", 0)
        is_integer(reblogs_count) and reblogs_count > 0
      end,
      "egregoros received pleroma boost"
    )
  end

  test "remote receives our boosts", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    bob_text = "fedbox: boost this #{unique}"
    bob_status = create_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_text)
    bob_status_id = bob_status["id"]

    bob_uri_variants =
      bob_status
      |> status_uri()
      |> actor_id_variants()

    egregoros_bob_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.egregoros_base_url, ctx.access_token, bob_uri_variants)
        end,
        "egregoros received bob post"
      )

    _reblog = reblog_status!(ctx.egregoros_base_url, ctx.access_token, egregoros_bob_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_status_id)
        reblogs_count = Map.get(status, "reblogs_count", 0)
        is_integer(reblogs_count) and reblogs_count > 0
      end,
      "pleroma received alice boost"
    )
  end

  test "remote receives our boosts (mastodon)", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    carol_text = "fedbox: boost this (mastodon) #{unique}"
    carol_status = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)
    carol_status_id = carol_status["id"]

    carol_uri_variants =
      carol_status
      |> status_uri()
      |> actor_id_variants()

    egregoros_carol_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.egregoros_base_url, ctx.access_token, carol_uri_variants)
        end,
        "egregoros received carol post"
      )

    _reblog = reblog_status!(ctx.egregoros_base_url, ctx.access_token, egregoros_carol_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_status_id)
        reblogs_count = Map.get(status, "reblogs_count", 0)
        is_integer(reblogs_count) and reblogs_count > 0
      end,
      "mastodon received alice boost"
    )
  end

  test "deletes: receives deletes from mastodon", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    carol_text = "fedbox: delete me (mastodon) #{unique}"
    carol_status = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)
    carol_status_id = carol_status["id"]

    carol_uri_variants =
      carol_status
      |> status_uri()
      |> actor_id_variants()

    egregoros_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.egregoros_base_url, ctx.access_token, carol_uri_variants)
        end,
        "egregoros received mastodon post"
      )

    _ = delete_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_status_id)

    wait_until!(
      fn -> status_gone?(ctx.egregoros_base_url, ctx.access_token, egregoros_status["id"]) end,
      "egregoros removed deleted mastodon post"
    )
  end

  test "deletes: receives deletes from pleroma", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    bob_text = "fedbox: delete me (pleroma) #{unique}"
    bob_status = create_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_text)
    bob_status_id = bob_status["id"]

    bob_uri_variants =
      bob_status
      |> status_uri()
      |> actor_id_variants()

    egregoros_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.egregoros_base_url, ctx.access_token, bob_uri_variants)
        end,
        "egregoros received pleroma post"
      )

    _ = delete_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_status_id)

    wait_until!(
      fn -> status_gone?(ctx.egregoros_base_url, ctx.access_token, egregoros_status["id"]) end,
      "egregoros removed deleted pleroma post"
    )
  end

  test "deletes: remote receives our deletes (mastodon)", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: delete me (to mastodon) #{unique}"
    alice_status = create_status!(ctx.egregoros_base_url, ctx.access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    mastodon_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice post"
      )

    _ = delete_status!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)

    wait_until!(
      fn ->
        status_gone?(ctx.mastodon_base_url, ctx.carol_access_token, mastodon_status["id"])
      end,
      "mastodon removed deleted alice post"
    )
  end

  test "deletes: remote receives our deletes (pleroma)", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.pleroma_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    alice_text = "fedbox: delete me (to pleroma) #{unique}"
    alice_status = create_status!(ctx.egregoros_base_url, ctx.access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    pleroma_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.pleroma_base_url,
            ctx.bob_access_token,
            alice_uri_variants
          )
        end,
        "pleroma received alice post"
      )

    _ = delete_status!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)

    wait_until!(
      fn -> status_gone?(ctx.pleroma_base_url, ctx.bob_access_token, pleroma_status["id"]) end,
      "pleroma removed deleted alice post"
    )
  end

  test "threads: partial threads stay together when intermediate replies are missing", ctx do
    unique = unique_token()

    _ = follow_remote!(ctx.pleroma_base_url, ctx.dave_access_token, ctx.bob_handle)

    wait_until!(
      fn ->
        followers = fetch_follower_ids(ctx.bob_actor_id)
        Enum.any?(followers, &(&1 in ctx.dave_actor_id_variants))
      end,
      "pleroma accepted follow dave -> bob"
    )

    _ = follow_remote!(ctx.pleroma_base_url, ctx.bob_access_token, ctx.dave_handle)

    wait_until!(
      fn ->
        followers = fetch_follower_ids(ctx.dave_actor_id)
        Enum.any?(followers, &(&1 in ctx.bob_actor_id_variants))
      end,
      "pleroma accepted follow bob -> dave"
    )

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    root_text = "fedbox: private thread root #{unique}"
    bob_root = create_status!(ctx.pleroma_base_url, ctx.bob_access_token, root_text, "private")

    bob_root_uri_variants =
      bob_root
      |> status_uri()
      |> actor_id_variants()

    egregoros_root =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.egregoros_base_url,
            ctx.access_token,
            bob_root_uri_variants
          )
        end,
        "egregoros received private pleroma root"
      )

    hidden_reply_text = "fedbox: private hidden reply #{unique}"

    hidden_reply =
      create_reply!(
        ctx.pleroma_base_url,
        ctx.dave_access_token,
        hidden_reply_text,
        bob_root["id"],
        "private"
      )

    visible_reply_text = "fedbox: private visible reply #{unique}"

    visible_reply =
      create_reply!(
        ctx.pleroma_base_url,
        ctx.bob_access_token,
        visible_reply_text,
        Map.fetch!(hidden_reply, "id"),
        "private"
      )

    visible_reply_uri_variants =
      visible_reply
      |> status_uri()
      |> actor_id_variants()

    wait_until!(
      fn ->
        home_timeline_contains?(ctx.egregoros_base_url, ctx.access_token, visible_reply_text)
      end,
      "egregoros received bob private reply"
    )

    refute home_timeline_contains?(ctx.egregoros_base_url, ctx.access_token, hidden_reply_text)

    wait_until!(
      fn ->
        context = fetch_context!(ctx.egregoros_base_url, ctx.access_token, egregoros_root["id"])
        descendants = Map.get(context, "descendants", [])

        Enum.any?(descendants, fn status ->
          status
          |> status_uri()
          |> case do
            uri when is_binary(uri) -> uri in visible_reply_uri_variants
            _ -> false
          end
        end)
      end,
      "egregoros groups partial thread by conversation context"
    )
  end

  test "threads: receives replies from mastodon on our posts", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: thread root #{unique}"
    alice_status = create_status!(ctx.egregoros_base_url, ctx.access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    mastodon_root =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice root"
      )

    reply_text = "#{ctx.alice_handle} fedbox: reply from carol #{unique}"

    reply_status =
      create_reply!(
        ctx.mastodon_base_url,
        ctx.carol_access_token,
        reply_text,
        mastodon_root["id"]
      )

    reply_uri_variants =
      reply_status
      |> status_uri()
      |> actor_id_variants()

    wait_until!(
      fn ->
        context = fetch_context!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)
        descendants = Map.get(context, "descendants", [])

        Enum.any?(descendants, fn status ->
          status
          |> status_uri()
          |> case do
            uri when is_binary(uri) -> uri in reply_uri_variants
            _ -> false
          end
        end)
      end,
      "egregoros received mastodon reply in context"
    )
  end

  test "threads: receives replies from pleroma on our posts", ctx do
    unique = unique_token()

    follow_and_assert_local_accept!(
      ctx.pleroma_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    alice_text = "fedbox: thread root (pleroma) #{unique}"
    alice_status = create_status!(ctx.egregoros_base_url, ctx.access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    pleroma_root =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.pleroma_base_url,
            ctx.bob_access_token,
            alice_uri_variants
          )
        end,
        "pleroma received alice root"
      )

    reply_text = "#{ctx.alice_handle} fedbox: reply from bob #{unique}"

    reply_status =
      create_reply!(
        ctx.pleroma_base_url,
        ctx.bob_access_token,
        reply_text,
        pleroma_root["id"]
      )

    reply_uri_variants =
      reply_status
      |> status_uri()
      |> actor_id_variants()

    wait_until!(
      fn ->
        context = fetch_context!(ctx.egregoros_base_url, ctx.access_token, alice_status_id)
        descendants = Map.get(context, "descendants", [])

        Enum.any?(descendants, fn status ->
          status
          |> status_uri()
          |> case do
            uri when is_binary(uri) -> uri in reply_uri_variants
            _ -> false
          end
        end)
      end,
      "egregoros received pleroma reply in context"
    )
  end

  test "threads: remote receives our replies", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    bob_text = "fedbox: bob thread root #{unique}"
    bob_status = create_status!(ctx.pleroma_base_url, ctx.bob_access_token, bob_text)
    bob_status_id = bob_status["id"]

    bob_uri_variants =
      bob_status
      |> status_uri()
      |> actor_id_variants()

    egregoros_bob_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.egregoros_base_url, ctx.access_token, bob_uri_variants)
        end,
        "egregoros received bob root"
      )

    reply_text = "fedbox: reply from alice #{unique}"

    reply_status =
      create_reply!(
        ctx.egregoros_base_url,
        ctx.access_token,
        reply_text,
        egregoros_bob_status["id"]
      )

    reply_uri_variants =
      reply_status
      |> status_uri()
      |> actor_id_variants()

    wait_until!(
      fn ->
        context = fetch_context!(ctx.pleroma_base_url, ctx.bob_access_token, bob_status_id)
        descendants = Map.get(context, "descendants", [])

        Enum.any?(descendants, fn status ->
          status
          |> status_uri()
          |> case do
            uri when is_binary(uri) -> uri in reply_uri_variants
            _ -> false
          end
        end)
      end,
      "pleroma received alice reply in context"
    )
  end

  test "threads: remote receives our replies (mastodon)", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.egregoros_base_url,
      ctx.access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    carol_text = "fedbox: carol thread root #{unique}"
    carol_status = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)
    carol_status_id = carol_status["id"]

    carol_uri_variants =
      carol_status
      |> status_uri()
      |> actor_id_variants()

    egregoros_carol_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.egregoros_base_url, ctx.access_token, carol_uri_variants)
        end,
        "egregoros received carol root"
      )

    reply_text = "fedbox: reply from alice #{unique}"

    reply_status =
      create_reply!(
        ctx.egregoros_base_url,
        ctx.access_token,
        reply_text,
        egregoros_carol_status["id"]
      )

    reply_uri_variants =
      reply_status
      |> status_uri()
      |> actor_id_variants()

    wait_until!(
      fn ->
        context = fetch_context!(ctx.mastodon_base_url, ctx.carol_access_token, carol_status_id)
        descendants = Map.get(context, "descendants", [])

        Enum.any?(descendants, fn status ->
          status
          |> status_uri()
          |> case do
            uri when is_binary(uri) -> uri in reply_uri_variants
            _ -> false
          end
        end)
      end,
      "mastodon received alice reply in context"
    )
  end

  defp follow_and_assert_remote_accept!(base_url, access_token, handle, alice_actor_id_variants)
       when is_binary(base_url) and is_binary(access_token) and is_binary(handle) and
              is_list(alice_actor_id_variants) do
    _ = follow_remote!(base_url, access_token, handle)

    %{username: username, domain: domain} = parse_handle!(handle)

    remote_actor_id =
      wait_until!(fn -> webfinger_self_href(username, domain) end, "actor #{handle}")

    wait_until!(
      fn ->
        followers = fetch_follower_ids(remote_actor_id)
        Enum.any?(followers, &(&1 in alice_actor_id_variants))
      end,
      "follow accepted alice -> #{handle}"
    )

    :ok
  end

  defp follow_and_assert_local_accept!(
         remote_base_url,
         remote_access_token,
         local_handle,
         local_actor_id,
         remote_actor_id_variants
       )
       when is_binary(remote_base_url) and is_binary(remote_access_token) and
              is_binary(local_handle) and
              is_binary(local_actor_id) and is_list(remote_actor_id_variants) do
    _ = follow_remote!(remote_base_url, remote_access_token, local_handle)

    wait_until!(
      fn ->
        followers = fetch_follower_ids(local_actor_id)
        Enum.any?(followers, &(&1 in remote_actor_id_variants))
      end,
      "follow accepted remote -> #{local_handle}"
    )

    :ok
  end

  defp unique_token do
    System.unique_integer([:positive])
    |> Integer.to_string()
  end

  defp create_status!(base_url, access_token, text)
       when is_binary(base_url) and is_binary(access_token) and is_binary(text) do
    create_status!(base_url, access_token, text, "public")
  end

  defp create_status!(base_url, access_token, text, visibility)
       when is_binary(base_url) and is_binary(access_token) and is_binary(text) and
              is_binary(visibility) do
    resp =
      req_post!(
        base_url <> "/api/v1/statuses",
        headers: [{"authorization", "Bearer " <> access_token}],
        form: [{"status", text}, {"visibility", visibility}]
      )

    ensure_json!(resp.body)
  end

  defp issue_badge!(base_url, access_token, badge_type, recipient_ap_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(badge_type) and
              is_binary(recipient_ap_id) do
    resp =
      req_post!(
        base_url <> "/api/v1/pleroma/badges/issue",
        headers: [{"authorization", "Bearer " <> access_token}],
        form: [{"badge_type", badge_type}, {"recipient_ap_id", recipient_ap_id}]
      )

    if resp.status not in 200..299 do
      raise("unexpected status when issuing badge: #{resp.status} body=#{inspect(resp.body)}")
    end

    ensure_json!(resp.body)
  end

  defp accept_offer?(base_url, access_token, offer_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(offer_id) do
    encoded_id = URI.encode_www_form(offer_id)

    resp =
      req_post!(
        base_url <> "/api/v1/pleroma/offers/" <> encoded_id <> "/accept",
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    cond do
      resp.status in 200..299 -> true
      resp.status in [404, 422] -> false
      true -> raise("unexpected status when accepting offer: #{resp.status}")
    end
  end

  defp reject_offer?(base_url, access_token, offer_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(offer_id) do
    encoded_id = URI.encode_www_form(offer_id)

    resp =
      req_post!(
        base_url <> "/api/v1/pleroma/offers/" <> encoded_id <> "/reject",
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    cond do
      resp.status in 200..299 -> true
      resp.status in [404, 422] -> false
      true -> raise("unexpected status when rejecting offer: #{resp.status}")
    end
  end

  defp credential_public_with_proof?(base_url, credential_id)
       when is_binary(base_url) and is_binary(credential_id) do
    case fetch_object_by_ap_id(base_url, credential_id) do
      {:ok, %{"proof" => %{} = proof} = object} ->
        proof["cryptosuite"] == "eddsa-jcs-2022" and
          @as_public in List.wrap(Map.get(object, "to", []))

      _ ->
        false
    end
  end

  defp credential_not_public?(base_url, credential_id)
       when is_binary(base_url) and is_binary(credential_id) do
    case fetch_object_by_ap_id(base_url, credential_id) do
      {:error, status} when status in [404, 410] -> true
      _ -> false
    end
  end

  defp create_poll_status!(base_url, access_token, text, poll_options, opts \\ [])
       when is_binary(base_url) and is_binary(access_token) and is_binary(text) and
              is_list(poll_options) and is_list(opts) do
    expires_in = Keyword.get(opts, :expires_in, 600)
    visibility = Keyword.get(opts, :visibility, "public")
    multiple? = Keyword.get(opts, :multiple, false)
    scheduled_at = Keyword.get(opts, :scheduled_at)
    media_ids = Keyword.get(opts, :media_ids, [])

    form =
      [
        {"status", text},
        {"visibility", visibility},
        {"poll[expires_in]", Integer.to_string(expires_in)},
        {"poll[multiple]", to_string(multiple?)}
      ] ++
        Enum.map(poll_options, &{"poll[options][]", &1}) ++
        Enum.map(media_ids, &{"media_ids[]", &1}) ++
        if(is_binary(scheduled_at) and scheduled_at != "",
          do: [{"scheduled_at", scheduled_at}],
          else: []
        )

    resp =
      req_post!(
        base_url <> "/api/v1/statuses",
        headers: [{"authorization", "Bearer " <> access_token}],
        form: form
      )

    if resp.status not in 200..299 do
      raise(
        "unexpected status when creating poll status: #{resp.status} body=#{inspect(resp.body)}"
      )
    end

    ensure_json!(resp.body)
  end

  defp upload_test_png!(base_url, access_token)
       when is_binary(base_url) and is_binary(access_token) do
    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6X3cQAAAABJRU5ErkJggg=="
      )

    path = Path.join(System.tmp_dir!(), "fedbox-#{unique_token()}.png")
    File.write!(path, png)

    resp =
      req_post!(
        base_url <> "/api/v2/media",
        headers: [{"authorization", "Bearer " <> access_token}],
        form_multipart: [
          {"file", {png, filename: "fedbox.png", content_type: "image/png", size: byte_size(png)}}
        ]
      )

    if resp.status not in 200..299 do
      raise("unexpected status when uploading media: #{resp.status} body=#{inspect(resp.body)}")
    end

    body = ensure_json!(resp.body)
    Map.fetch!(body, "id")
  end

  defp create_reply!(base_url, access_token, text, in_reply_to_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(text) and
              is_binary(in_reply_to_id) do
    create_reply!(base_url, access_token, text, in_reply_to_id, "public")
  end

  defp create_reply!(base_url, access_token, text, in_reply_to_id, visibility)
       when is_binary(base_url) and is_binary(access_token) and is_binary(text) and
              is_binary(in_reply_to_id) and is_binary(visibility) do
    resp =
      req_post!(
        base_url <> "/api/v1/statuses",
        headers: [{"authorization", "Bearer " <> access_token}],
        form: [
          {"status", text},
          {"in_reply_to_id", in_reply_to_id},
          {"visibility", visibility}
        ]
      )

    ensure_json!(resp.body)
  end

  defp vote_on_poll!(base_url, access_token, poll_id, choices)
       when is_binary(base_url) and is_binary(access_token) and is_binary(poll_id) and
              is_list(choices) do
    resp =
      req_post!(
        base_url <> "/api/v1/polls/" <> poll_id <> "/votes",
        headers: [{"authorization", "Bearer " <> access_token}],
        json: %{"choices" => choices}
      )

    ensure_json!(resp.body)
  end

  defp fetch_status!(base_url, access_token, status_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(status_id) do
    resp =
      req_get!(
        base_url <> "/api/v1/statuses/" <> status_id,
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    ensure_json!(resp.body)
  end

  defp fetch_object_by_ap_id(base_url, ap_id)
       when is_binary(base_url) and is_binary(ap_id) do
    case object_uuid_from_ap_id(ap_id) do
      uuid when is_binary(uuid) and uuid != "" ->
        resp =
          req_get!(
            base_url <> "/objects/" <> uuid,
            headers: [{"accept", "application/activity+json"}]
          )

        if resp.status in 200..299 do
          {:ok, ensure_json!(resp.body)}
        else
          {:error, resp.status}
        end

      _ ->
        {:error, :invalid_ap_id}
    end
  end

  defp object_uuid_from_ap_id(ap_id) when is_binary(ap_id) do
    case URI.parse(ap_id) do
      %URI{path: path} when is_binary(path) ->
        path
        |> String.split("/", trim: true)
        |> List.last()

      _ ->
        nil
    end
  end

  defp poll_option_votes(status) when is_map(status) do
    poll =
      status
      |> Map.get("poll")
      |> case do
        %{} = poll -> poll
        _ -> %{}
      end

    poll
    |> Map.get("options", [])
    |> List.wrap()
    |> Enum.map(fn
      %{} = option -> Map.get(option, "votes_count", 0)
      _ -> 0
    end)
  end

  defp fetch_context!(base_url, access_token, status_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(status_id) do
    resp =
      req_get!(
        base_url <> "/api/v1/statuses/" <> status_id <> "/context",
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    ensure_json!(resp.body)
  end

  defp favourite_status!(base_url, access_token, status_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(status_id) do
    _resp =
      req_post!(
        base_url <> "/api/v1/statuses/" <> status_id <> "/favourite",
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    :ok
  end

  defp reblog_status!(base_url, access_token, status_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(status_id) do
    resp =
      req_post!(
        base_url <> "/api/v1/statuses/" <> status_id <> "/reblog",
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    ensure_json!(resp.body)
  end

  defp delete_status!(base_url, access_token, status_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(status_id) do
    resp =
      req_delete!(
        base_url <> "/api/v1/statuses/" <> status_id,
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    if resp.status in 200..299 do
      :ok
    else
      raise("unexpected status when deleting #{status_id}: #{resp.status}")
    end
  end

  defp status_gone?(base_url, access_token, status_id)
       when is_binary(base_url) and is_binary(access_token) and is_binary(status_id) do
    resp =
      req_get!(
        base_url <> "/api/v1/statuses/" <> status_id,
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    resp.status in [404, 410]
  end

  defp home_timeline_contains?(base_url, access_token, needle)
       when is_binary(base_url) and is_binary(access_token) and is_binary(needle) do
    statuses = fetch_home_timeline!(base_url, access_token, limit: 40)

    Enum.any?(statuses, fn status ->
      content = Map.get(status, "content", "")
      is_binary(content) and String.contains?(content, needle)
    end)
  end

  defp find_status_by_uri_variant(base_url, access_token, uri_variants)
       when is_binary(base_url) and is_binary(access_token) and is_list(uri_variants) do
    statuses = fetch_home_timeline!(base_url, access_token, limit: 40)

    status =
      Enum.find(statuses, fn status ->
        status
        |> status_uri()
        |> case do
          uri when is_binary(uri) -> uri in uri_variants
          _ -> false
        end
      end)

    cond do
      is_map(status) ->
        {:ok, status}

      true ->
        find_status_by_uri_variant_via_search(base_url, access_token, uri_variants)
    end
  end

  defp find_status_by_uri_variant_via_search(base_url, access_token, uri_variants)
       when is_binary(base_url) and is_binary(access_token) and is_list(uri_variants) do
    find_status_by_uri_variant_via_search_endpoint(base_url, access_token, uri_variants, :v2) ||
      find_status_by_uri_variant_via_search_endpoint(base_url, access_token, uri_variants, :v1)
  end

  defp find_status_by_uri_variant_via_search_endpoint(
         base_url,
         access_token,
         uri_variants,
         version
       )
       when is_binary(base_url) and is_binary(access_token) and is_list(uri_variants) and
              version in [:v1, :v2] do
    endpoint =
      case version do
        :v2 -> "/api/v2/search"
        :v1 -> "/api/v1/search"
      end

    Enum.find_value(uri_variants, fn query ->
      params =
        case version do
          :v2 ->
            [{"q", query}, {"type", "statuses"}, {"resolve", "true"}, {"limit", 10}]

          :v1 ->
            [{"q", query}, {"resolve", "true"}, {"limit", 10}]
        end

      resp =
        req_get!(
          base_url <> endpoint,
          headers: [{"authorization", "Bearer " <> access_token}],
          params: params
        )

      cond do
        resp.status in 200..299 ->
          body = ensure_json!(resp.body)
          statuses = Map.get(body, "statuses", [])

          Enum.find_value(statuses, fn status ->
            case status_uri(status) do
              uri when is_binary(uri) ->
                if Enum.member?(uri_variants, uri) do
                  {:ok, status}
                else
                  nil
                end

              _ ->
                nil
            end
          end)

        true ->
          nil
      end
    end)
  end

  defp find_status_by_content(base_url, access_token, needle)
       when is_binary(base_url) and is_binary(access_token) and is_binary(needle) do
    statuses = fetch_home_timeline!(base_url, access_token, limit: 40)

    Enum.find_value(statuses, fn status ->
      content = Map.get(status, "content", "")

      if is_binary(content) and String.contains?(content, needle) do
        {:ok, status}
      else
        nil
      end
    end)
  end

  defp assert_poll_options!(status, expected_titles)
       when is_map(status) and is_list(expected_titles) do
    poll =
      status
      |> Map.get("poll")
      |> case do
        %{} = poll -> poll
        _ -> flunk("expected status to include poll")
      end

    options = Map.get(poll, "options", [])
    assert is_list(options)

    titles = Enum.map(options, &Map.get(&1, "title"))

    assert titles == expected_titles
  end

  defp fetch_home_timeline!(base_url, access_token, opts)
       when is_binary(base_url) and is_binary(access_token) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 20)

    resp =
      req_get!(
        base_url <> "/api/v1/timelines/home",
        headers: [{"authorization", "Bearer " <> access_token}],
        params: [{"limit", limit}]
      )

    ensure_json!(resp.body)
  end

  defp status_uri(%{} = status) do
    Map.get(status, "uri") || Map.get(status, "url")
  end

  defp register_user!(base_url, domain, nickname, password)
       when is_binary(base_url) and is_binary(domain) and is_binary(nickname) and
              is_binary(password) do
    wait_until!(
      fn ->
        case register_user_once(base_url, domain, nickname, password) do
          {:ok, _jar} -> {:ok, :ok}
          :already_registered -> {:ok, :ok}
          _ -> false
        end
      end,
      "register ready #{nickname}@#{base_url}"
    )
  end

  defp register_user_once(base_url, domain, nickname, password)
       when is_binary(base_url) and is_binary(domain) and is_binary(nickname) and
              is_binary(password) do
    {html, jar} = get_html!(base_url, "/register", %{})

    with {:ok, csrf_token} <- extract_csrf_token(html),
         {resp, jar} <-
           post_form_response!(base_url, "/register", jar, csrf_token, [
             {"registration[nickname]", nickname},
             {"registration[email]", "#{nickname}@#{domain}"},
             {"registration[password]", password},
             {"registration[return_to]", "/"}
           ]) do
      cond do
        resp.status in 200..399 -> {:ok, jar}
        resp.status == 422 -> :already_registered
        true -> {:error, :registration_failed}
      end
    else
      _ -> {:error, :registration_failed}
    end
  rescue
    _ -> {:error, :registration_failed}
  end

  defp login_user!(base_url, nickname, password)
       when is_binary(base_url) and is_binary(nickname) and is_binary(password) do
    wait_until!(
      fn ->
        case login_user_once(base_url, nickname, password) do
          {:ok, session} -> {:ok, session}
          _ -> false
        end
      end,
      "login ready #{nickname}@#{base_url}"
    )
  end

  defp login_user_once(base_url, nickname, password)
       when is_binary(base_url) and is_binary(nickname) and is_binary(password) do
    {html, jar} = get_html!(base_url, "/login", %{})

    with {:ok, csrf_token} <- extract_csrf_token(html),
         {resp, jar} <-
           post_form_response!(base_url, "/login", jar, csrf_token, [
             {"session[nickname]", nickname},
             {"session[password]", password},
             {"session[return_to]", "/"}
           ]),
         true <- resp.status in 300..399 do
      {:ok, %{cookie_jar: jar}}
    else
      _ -> {:error, :login_failed}
    end
  rescue
    _ -> {:error, :login_failed}
  end

  defp create_oauth_app!(base_url, scopes) when is_binary(base_url) and is_binary(scopes) do
    resp =
      req_post!(
        base_url <> "/api/v1/apps",
        form: [
          {"client_name", "fedbox"},
          {"redirect_uris", "urn:ietf:wg:oauth:2.0:oob"},
          {"scopes", scopes},
          {"website", ""}
        ]
      )

    body = ensure_json!(resp.body)

    %{
      client_id: Map.fetch!(body, "client_id"),
      client_secret: Map.fetch!(body, "client_secret")
    }
  end

  defp authorize_oauth_app!(base_url, %{cookie_jar: jar}, client_id, redirect_uri, scopes)
       when is_binary(base_url) and is_binary(client_id) and is_binary(redirect_uri) and
              is_binary(scopes) do
    wait_until!(
      fn ->
        case authorize_oauth_app_once(base_url, jar, client_id, redirect_uri, scopes) do
          {:ok, code} -> {:ok, code}
          _ -> false
        end
      end,
      "oauth authorize ready #{base_url}"
    )
  end

  defp authorize_oauth_app_once(base_url, jar, client_id, redirect_uri, scopes)
       when is_binary(base_url) and is_map(jar) and is_binary(client_id) and
              is_binary(redirect_uri) and is_binary(scopes) do
    query =
      URI.encode_query(%{
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => scopes,
        "state" => ""
      })

    {html, jar} = get_html!(base_url, "/oauth/authorize?" <> query, jar)

    with {:ok, csrf_token} <- extract_csrf_token(html),
         {authorized_html, _jar} <-
           post_form!(base_url, "/oauth/authorize", jar, csrf_token, [
             {"oauth[client_id]", client_id},
             {"oauth[redirect_uri]", redirect_uri},
             {"oauth[response_type]", "code"},
             {"oauth[scope]", scopes},
             {"oauth[state]", ""}
           ]) do
      {:ok, extract_oauth_code!(authorized_html)}
    else
      _ -> {:error, :oauth_failed}
    end
  rescue
    _ -> {:error, :oauth_failed}
  end

  defp authorize_rails_oauth_app!(base_url, %{cookie_jar: jar}, client_id, redirect_uri, scopes)
       when is_binary(base_url) and is_binary(client_id) and is_binary(redirect_uri) and
              is_binary(scopes) do
    query =
      URI.encode_query(%{
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => scopes,
        "state" => ""
      })

    {html, jar} = get_html!(base_url, "/oauth/authorize?" <> query, jar)
    csrf_token = extract_csrf_token!(html)

    resp =
      req_post!(
        base_url <> "/oauth/authorize",
        headers: cookie_headers(jar),
        form: [
          {"authenticity_token", csrf_token},
          {"client_id", client_id},
          {"redirect_uri", redirect_uri},
          {"code_challenge", ""},
          {"code_challenge_method", ""},
          {"response_type", "code"},
          {"scope", scopes},
          {"state", ""}
        ]
      )

    _jar = update_cookie_jar(jar, resp)

    cond do
      resp.status in 300..399 ->
        resp
        |> Req.Response.get_header("location")
        |> List.first()
        |> case do
          location when is_binary(location) and location != "" ->
            location
            |> URI.parse()
            |> Map.get(:query, "")
            |> URI.decode_query()
            |> Map.get("code")

          _ ->
            raise("oauth code not found")
        end

      resp.status in 200..299 ->
        extract_oauth_code!(to_string(resp.body))

      true ->
        raise("unexpected oauth authorize response: #{resp.status}")
    end
  end

  defp exchange_auth_code!(base_url, client_id, client_secret, redirect_uri, code)
       when is_binary(base_url) and is_binary(client_id) and is_binary(client_secret) and
              is_binary(redirect_uri) and is_binary(code) do
    resp =
      req_post!(
        base_url <> "/oauth/token",
        form: [
          {"grant_type", "authorization_code"},
          {"code", code},
          {"client_id", client_id},
          {"client_secret", client_secret},
          {"redirect_uri", redirect_uri}
        ]
      )

    body = ensure_json!(resp.body)
    Map.fetch!(body, "access_token")
  end

  defp follow_remote!(base_url, access_token, handle)
       when is_binary(base_url) and is_binary(access_token) and is_binary(handle) do
    # Mastodon v4.5+ no longer exposes POST /api/v1/follows.
    # Prefer it when available (Pleroma, Egregoros), then fall back to
    # resolving the remote account and POST /api/v1/accounts/:id/follow.
    resp =
      req_post!(
        base_url <> "/api/v1/follows",
        headers: [{"authorization", "Bearer " <> access_token}],
        form: [{"uri", handle}]
      )

    cond do
      resp.status in 200..299 ->
        :ok

      resp.status in [404, 405] ->
        follow_remote_via_lookup!(base_url, access_token, handle)

      true ->
        raise("follow failed (POST /api/v1/follows): #{resp.status}")
    end
  end

  defp follow_remote_via_lookup!(base_url, access_token, handle)
       when is_binary(base_url) and is_binary(access_token) and is_binary(handle) do
    account_id = resolve_account_id!(base_url, access_token, handle)

    resp =
      req_post!(
        base_url <> "/api/v1/accounts/" <> account_id <> "/follow",
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    if resp.status in 200..299 do
      :ok
    else
      raise("follow failed (POST /api/v1/accounts/:id/follow): #{resp.status}")
    end
  end

  defp resolve_account_id!(base_url, access_token, handle)
       when is_binary(base_url) and is_binary(access_token) and is_binary(handle) do
    acct = String.trim_leading(handle, "@")

    resp =
      req_get!(
        base_url <> "/api/v1/accounts/lookup",
        headers: [{"authorization", "Bearer " <> access_token}],
        params: [{"acct", acct}]
      )

    cond do
      resp.status in 200..299 ->
        resp.body
        |> ensure_json!()
        |> Map.fetch!("id")

      true ->
        resolve_account_id_via_search!(base_url, access_token, handle)
    end
  end

  defp resolve_account_id_via_search!(base_url, access_token, handle)
       when is_binary(base_url) and is_binary(access_token) and is_binary(handle) do
    acct = String.trim_leading(handle, "@")

    resolve =
      fn accounts ->
        accounts
        |> Enum.find(fn
          %{"acct" => ^acct} -> true
          _ -> false
        end)
        |> case do
          %{"id" => id} when is_binary(id) and id != "" ->
            {:ok, id}

          _ ->
            accounts
            |> List.first()
            |> case do
              %{"id" => id} when is_binary(id) and id != "" -> {:ok, id}
              _ -> :error
            end
        end
      end

    resp =
      req_get!(
        base_url <> "/api/v2/search",
        headers: [{"authorization", "Bearer " <> access_token}],
        params: [{"q", handle}, {"type", "accounts"}, {"resolve", "true"}, {"limit", 5}]
      )

    with status when status in 200..299 <- resp.status,
         %{} = body <- ensure_json!(resp.body),
         accounts when is_list(accounts) <- Map.get(body, "accounts"),
         {:ok, account_id} <- resolve.(accounts) do
      account_id
    else
      _ ->
        resp =
          req_get!(
            base_url <> "/api/v1/accounts/search",
            headers: [{"authorization", "Bearer " <> access_token}],
            params: [{"q", handle}, {"resolve", "true"}, {"limit", 5}]
          )

        with status when status in 200..299 <- resp.status,
             accounts when is_list(accounts) <- ensure_json!(resp.body),
             {:ok, account_id} <- resolve.(accounts) do
          account_id
        else
          _ ->
            raise("failed to resolve remote account id for #{handle}")
        end
    end
  end

  defp password_grant_token!(
         base_url,
         client_id,
         client_secret,
         usernames,
         password,
         scopes
       )
       when is_binary(base_url) and is_binary(client_id) and is_binary(client_secret) and
              is_list(usernames) and is_binary(password) and is_binary(scopes) do
    usernames
    |> Enum.find_value(fn username ->
      resp =
        req_post!(
          base_url <> "/oauth/token",
          form: [
            {"grant_type", "password"},
            {"username", username},
            {"password", password},
            {"client_id", client_id},
            {"client_secret", client_secret},
            {"scope", scopes}
          ]
        )

      if resp.status in 200..299 do
        body = ensure_json!(resp.body)
        Map.fetch!(body, "access_token")
      else
        nil
      end
    end)
    |> case do
      token when is_binary(token) and token != "" ->
        token

      _ ->
        raise("failed to get password-grant token from #{base_url}")
    end
  end

  defp mastodon_sign_in!(base_url, email, password)
       when is_binary(base_url) and is_binary(email) and is_binary(password) do
    {html, jar} = get_html!(base_url, "/auth/sign_in", %{})
    csrf_token = extract_csrf_token!(html)

    {_, jar} =
      post_rails_form!(base_url, "/auth/sign_in", jar, csrf_token, [
        {"user[email]", email},
        {"user[password]", password}
      ])

    %{cookie_jar: jar}
  end

  defp webfinger_self_href(username, domain) when is_binary(username) and is_binary(domain) do
    base_url = "#{fedtest_scheme()}://#{domain}"

    resp =
      req_get!(
        base_url <> "/.well-known/webfinger",
        headers: [{"accept", "application/jrd+json"}],
        params: [{"resource", "acct:#{username}@#{domain}"}]
      )

    cond do
      resp.status in 200..299 ->
        with {:ok, body} <- decode_json(resp.body),
             links when is_list(links) <- Map.get(body, "links"),
             %{} = link <- Enum.find(links, &(&1["rel"] == "self")),
             href when is_binary(href) and href != "" <- link["href"] do
          {:ok, href}
        else
          _ -> nil
        end

      resp.status in 300..399 ->
        case Req.Response.get_header(resp, "location") do
          [location | _] ->
            resp =
              req_get!(
                location,
                headers: [{"accept", "application/jrd+json"}]
              )

            with status when status in 200..299 <- resp.status,
                 {:ok, body} <- decode_json(resp.body),
                 links when is_list(links) <- Map.get(body, "links"),
                 %{} = link <- Enum.find(links, &(&1["rel"] == "self")),
                 href when is_binary(href) and href != "" <- link["href"] do
              {:ok, href}
            else
              _ -> nil
            end

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  defp fetch_follower_ids(remote_actor_id) when is_binary(remote_actor_id) do
    remote_actor_id
    |> fetch_ap_json!()
    |> Map.get("followers")
    |> case do
      followers_url when is_binary(followers_url) and followers_url != "" ->
        followers_url
        |> fetch_collection_page_items!()
        |> Enum.flat_map(&extract_id/1)

      _ ->
        []
    end
  end

  defp fetch_collection_page_items!(collection_url) when is_binary(collection_url) do
    collection = fetch_ap_json!(collection_url)

    cond do
      is_list(collection["orderedItems"]) ->
        collection["orderedItems"]

      is_list(collection["items"]) ->
        collection["items"]

      is_map(collection["first"]) ->
        first = collection["first"]
        Map.get(first, "orderedItems") || Map.get(first, "items") || []

      is_binary(collection["first"]) ->
        fetch_collection_page_items!(collection["first"])

      true ->
        []
    end
  end

  defp fetch_ap_json!(url) when is_binary(url) do
    resp =
      req_get!(
        url,
        headers: [{"accept", "application/activity+json"}]
      )

    ensure_json!(resp.body)
  end

  defp extract_id(id) when is_binary(id), do: [id]

  defp extract_id(%{"id" => id}) when is_binary(id), do: [id]
  defp extract_id(_), do: []

  defp parse_handle!(handle) when is_binary(handle) do
    handle
    |> String.trim_leading("@")
    |> String.split("@", parts: 2)
    |> case do
      [username, domain] when username != "" and domain != "" ->
        %{username: username, domain: domain}

      _ ->
        raise("invalid handle: #{inspect(handle)}")
    end
  end

  defp actor_id_variants(actor_id) when is_binary(actor_id) do
    actor_id = String.trim(actor_id)

    https_variant =
      actor_id
      |> URI.parse()
      |> then(fn uri ->
        case uri do
          %URI{scheme: "http"} = uri -> URI.to_string(%URI{uri | scheme: "https", port: nil})
          _ -> actor_id
        end
      end)

    http_variant =
      actor_id
      |> URI.parse()
      |> then(fn uri ->
        case uri do
          %URI{scheme: "https"} = uri -> URI.to_string(%URI{uri | scheme: "http", port: nil})
          _ -> actor_id
        end
      end)

    [actor_id, https_variant, http_variant]
    |> Enum.uniq()
    |> Enum.reject(&(&1 == ""))
  end

  defp get_html!(base_url, path, jar)
       when is_binary(base_url) and is_binary(path) and is_map(jar) do
    resp =
      req_get!(
        base_url <> path,
        headers: cookie_headers(jar) ++ [{"accept", "text/html"}]
      )

    jar = update_cookie_jar(jar, resp)
    {to_string(resp.body), jar}
  end

  defp post_form!(base_url, path, jar, csrf_token, fields)
       when is_binary(base_url) and is_binary(path) and is_map(jar) and is_binary(csrf_token) and
              is_list(fields) do
    resp =
      req_post!(
        base_url <> path,
        headers: cookie_headers(jar),
        form: [{"_csrf_token", csrf_token} | fields]
      )

    jar = update_cookie_jar(jar, resp)
    {to_string(resp.body), jar}
  end

  defp post_form_response!(base_url, path, jar, csrf_token, fields)
       when is_binary(base_url) and is_binary(path) and is_map(jar) and is_binary(csrf_token) and
              is_list(fields) do
    resp =
      req_post!(
        base_url <> path,
        headers: cookie_headers(jar),
        form: [{"_csrf_token", csrf_token} | fields]
      )

    jar = update_cookie_jar(jar, resp)
    {resp, jar}
  end

  defp post_rails_form!(base_url, path, jar, csrf_token, fields)
       when is_binary(base_url) and is_binary(path) and is_map(jar) and is_binary(csrf_token) and
              is_list(fields) do
    resp =
      req_post!(
        base_url <> path,
        headers: cookie_headers(jar),
        form: [{"authenticity_token", csrf_token} | fields]
      )

    jar = update_cookie_jar(jar, resp)
    {to_string(resp.body), jar}
  end

  defp cookie_headers(jar) when is_map(jar) do
    case jar do
      jar when map_size(jar) == 0 ->
        []

      jar ->
        cookie =
          jar
          |> Enum.map_join("; ", fn {name, value} -> "#{name}=#{value}" end)

        [{"cookie", cookie}]
    end
  end

  defp update_cookie_jar(jar, %Req.Response{} = resp) when is_map(jar) do
    resp
    |> Req.Response.get_header("set-cookie")
    |> Enum.reduce(jar, fn set_cookie, jar ->
      set_cookie
      |> String.split(";", parts: 2)
      |> List.first()
      |> String.split("=", parts: 2)
      |> case do
        [name, value] when name != "" -> Map.put(jar, name, value)
        _ -> jar
      end
    end)
  end

  defp extract_csrf_token!(html) when is_binary(html) do
    case Regex.run(~r/<meta\s+name=\"csrf-token\"\s+content=\"([^\"]+)\"/i, html) do
      [_, token] -> token
      _ -> raise("csrf token not found")
    end
  end

  defp extract_csrf_token(html) when is_binary(html) do
    case Regex.run(~r/<meta\s+name=\"csrf-token\"\s+content=\"([^\"]+)\"/i, html) do
      [_, token] -> {:ok, token}
      _ -> :error
    end
  end

  defp extract_oauth_code!(html) when is_binary(html) do
    with [_, code] <-
           Regex.run(
             ~r/<input[^>]*class=[\"'][^\"']*oauth-code[^\"']*[\"'][^>]*value=[\"']([^\"']+)[\"']/i,
             html
           ) ||
             Regex.run(
               ~r/<input[^>]*value=[\"']([^\"']+)[\"'][^>]*class=[\"'][^\"']*oauth-code[^\"']*[\"']/i,
               html
             ) do
      String.trim(code)
    else
      _ ->
        case Regex.run(~r/Copy this code back into the client:.*?<div[^>]*>([^<]+)<\/div>/s, html) do
          [_, code] -> String.trim(code)
          _ -> raise("oauth code not found")
        end
    end
  end

  defp ensure_json!(%{} = body), do: body

  defp ensure_json!(body) when is_list(body), do: body

  defp ensure_json!(body) when is_binary(body) do
    Jason.decode!(body)
  end

  defp ensure_json!(body) do
    body
    |> to_string()
    |> Jason.decode!()
  end

  defp decode_json(%{} = body), do: {:ok, body}

  defp decode_json(body) when is_binary(body), do: Jason.decode(body)

  defp decode_json(body) do
    body
    |> to_string()
    |> Jason.decode()
  end

  defp req_connect_options do
    case System.get_env("FEDTEST_CACERTFILE", "") |> String.trim() do
      "" ->
        []

      cacertfile ->
        [
          connect_options: [
            transport_opts: [
              verify: :verify_peer,
              cacertfile: cacertfile,
              depth: 20,
              reuse_sessions: false,
              log_level: :warning,
              customize_hostname_check: [
                match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
              ]
            ]
          ]
        ]
    end
  end

  defp fedtest_scheme do
    System.get_env("FEDTEST_SCHEME", "https")
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "http" -> "http"
      "https" -> "https"
      _ -> "https"
    end
  end

  defp req_default_opts(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https"} -> req_connect_options() ++ [redirect: false]
      _ -> [redirect: false]
    end
  end

  defp req_get!(url, opts) when is_binary(url) and is_list(opts) do
    Req.get!(url, req_default_opts(url) ++ opts)
  end

  defp req_post!(url, opts) when is_binary(url) and is_list(opts) do
    Req.post!(url, req_default_opts(url) ++ opts)
  end

  defp req_delete!(url, opts) when is_binary(url) and is_list(opts) do
    Req.delete!(url, req_default_opts(url) ++ opts)
  end

  defp wait_until!(check_fun, label, timeout_ms \\ 120_000)
       when is_function(check_fun, 0) and is_binary(label) and is_integer(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(check_fun, label, deadline)
  end

  defp do_wait_until(check_fun, label, deadline_ms)
       when is_function(check_fun, 0) and is_binary(label) and is_integer(deadline_ms) do
    case check_fun.() do
      true ->
        :ok

      {:ok, value} ->
        value

      _ ->
        if System.monotonic_time(:millisecond) > deadline_ms do
          raise("timeout waiting for #{label}")
        else
          Process.sleep(@poll_interval_ms)
          do_wait_until(check_fun, label, deadline_ms)
        end
    end
  end
end
