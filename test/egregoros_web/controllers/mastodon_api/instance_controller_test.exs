defmodule EgregorosWeb.MastodonAPI.InstanceControllerTest do
  use EgregorosWeb.ConnCase, async: true

  test "GET /api/v1/instance returns instance information", %{conn: conn} do
    conn = get(conn, "/api/v1/instance")
    response = json_response(conn, 200)

    assert is_binary(response["uri"])
    assert is_binary(response["title"])
    assert is_binary(response["version"])
    assert is_binary(get_in(response, ["urls", "streaming_api"]))
    assert is_map(response["stats"])
  end

  test "GET /api/v2/instance returns instance information", %{conn: conn} do
    conn = get(conn, "/api/v2/instance")
    response = json_response(conn, 200)

    assert is_binary(response["domain"])
    assert is_binary(response["title"])
    assert is_binary(response["version"])
    assert is_map(response["usage"])
    assert is_binary(get_in(response, ["configuration", "urls", "streaming"]))
  end

  test "GET /api/v1/instance/peers returns empty list", %{conn: conn} do
    conn = get(conn, "/api/v1/instance/peers")
    assert json_response(conn, 200) == []
  end

  test "GET /api/v1/instance/activity returns weekly activity stats", %{conn: conn} do
    conn = get(conn, "/api/v1/instance/activity")
    response = json_response(conn, 200)

    assert is_list(response)
    assert length(response) == 12

    Enum.each(response, fn item ->
      assert is_map(item)
      assert is_binary(item["week"])
      assert is_binary(item["statuses"])
      assert is_binary(item["logins"])
      assert is_binary(item["registrations"])
    end)
  end

  test "GET /api/v1/instance/rules returns a list", %{conn: conn} do
    conn = get(conn, "/api/v1/instance/rules")
    response = json_response(conn, 200)
    assert is_list(response)
  end

  test "GET /api/v1/instance/extended_description returns an extended description", %{conn: conn} do
    conn = get(conn, "/api/v1/instance/extended_description")
    response = json_response(conn, 200)
    assert is_map(response)
    assert Map.has_key?(response, "content")
  end

  test "GET /api/v1/instance/privacy_policy returns a privacy policy", %{conn: conn} do
    conn = get(conn, "/api/v1/instance/privacy_policy")
    response = json_response(conn, 200)
    assert is_map(response)
    assert Map.has_key?(response, "content")
  end

  test "GET /api/v1/instance/terms_of_service returns terms of service", %{conn: conn} do
    conn = get(conn, "/api/v1/instance/terms_of_service")
    response = json_response(conn, 200)
    assert is_map(response)
    assert Map.has_key?(response, "content")
  end

  test "GET /api/v1/instance/languages returns a list of languages", %{conn: conn} do
    conn = get(conn, "/api/v1/instance/languages")
    response = json_response(conn, 200)
    assert is_list(response)
  end

  test "GET /api/v1/instance/translation_languages returns a language matrix", %{conn: conn} do
    conn = get(conn, "/api/v1/instance/translation_languages")
    response = json_response(conn, 200)
    assert is_map(response)
  end
end
