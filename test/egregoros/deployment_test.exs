defmodule Egregoros.DeploymentTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.BadgeDefinition
  alias Egregoros.Deployment
  alias Egregoros.Repo
  alias Egregoros.Users

  test "bootstrap_admin/1 promotes an existing local user" do
    {:ok, user} = Users.create_local_user("alice")
    assert user.admin == false

    assert :ok = Deployment.bootstrap_admin("alice")

    assert Users.get(user.id).admin == true
  end

  test "bootstrap_admin/1 returns an error when the user doesn't exist" do
    assert {:error, :user_not_found} = Deployment.bootstrap_admin("missing")
  end

  test "bootstrap_admin/1 is a no-op when nickname is blank" do
    assert :ok = Deployment.bootstrap_admin("")
    assert :ok = Deployment.bootstrap_admin("   ")
  end

  test "bootstrap/0 seeds fedbox admin and badge definition when env vars are present" do
    System.put_env("EGREGOROS_FEDBOX_ADMIN_NICKNAME", "fedbox_admin")
    System.put_env("EGREGOROS_FEDBOX_ADMIN_PASSWORD", "password1234")
    System.put_env("EGREGOROS_FEDBOX_BADGE_TYPE", "fedbox_badge")
    System.put_env("EGREGOROS_FEDBOX_BADGE_NAME", "Fedbox Badge")
    System.put_env("EGREGOROS_FEDBOX_BADGE_DESCRIPTION", "Issued for fedbox test suites")
    System.put_env("EGREGOROS_FEDBOX_BADGE_NARRATIVE", "Issued inside a test federation box")

    on_exit(fn ->
      System.delete_env("EGREGOROS_FEDBOX_ADMIN_NICKNAME")
      System.delete_env("EGREGOROS_FEDBOX_ADMIN_PASSWORD")
      System.delete_env("EGREGOROS_FEDBOX_ADMIN_EMAIL")
      System.delete_env("EGREGOROS_FEDBOX_BADGE_TYPE")
      System.delete_env("EGREGOROS_FEDBOX_BADGE_NAME")
      System.delete_env("EGREGOROS_FEDBOX_BADGE_DESCRIPTION")
      System.delete_env("EGREGOROS_FEDBOX_BADGE_NARRATIVE")
    end)

    assert :ok = Deployment.bootstrap()

    assert %{admin: true} =
             Users.get_by_nickname("fedbox_admin")

    assert %BadgeDefinition{name: "Fedbox Badge"} =
             Repo.get_by(BadgeDefinition, badge_type: "fedbox_badge")
  end
end
