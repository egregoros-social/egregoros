defmodule PleromaReduxWeb.ProfilePathsTest do
  use ExUnit.Case, async: true

  alias PleromaReduxWeb.ProfilePaths

  describe "profile_path/1" do
    test "builds a profile path from an ActivityPub actor URL" do
      assert ProfilePaths.profile_path("https://remote.example/users/bob") ==
               "/@bob@remote.example"

      assert ProfilePaths.profile_path("https://remote.example/users/bob/") ==
               "/@bob@remote.example"

      assert ProfilePaths.profile_path("https://remote.example/@bob") == "/@bob@remote.example"

      assert ProfilePaths.profile_path("https://remote.example/users/bob#main-key") ==
               "/@bob@remote.example"
    end

    test "returns nil for actor URLs without a usable nickname" do
      assert ProfilePaths.profile_path("https://remote.example/") == nil
      assert ProfilePaths.profile_path("https://remote.example") == nil
    end
  end
end
