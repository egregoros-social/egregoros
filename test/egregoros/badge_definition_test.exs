defmodule Egregoros.BadgeDefinitionTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.BadgeDefinition
  alias Egregoros.Repo

  test "changeset requires required fields" do
    changeset = BadgeDefinition.changeset(%BadgeDefinition{}, %{})

    refute changeset.valid?

    assert %{badge_type: [_ | _], name: [_ | _], description: [_ | _], narrative: [_ | _]} =
             errors_on(changeset)
  end

  test "changeset accepts valid badge definitions" do
    changeset =
      BadgeDefinition.changeset(%BadgeDefinition{}, %{
        badge_type: "donator",
        name: "Donator",
        description: "Awarded for supporting the instance.",
        narrative: "Make any monetary donation to support the instance.",
        image_url: "https://example.com/badges/donator.png",
        disabled: false
      })

    assert changeset.valid?
  end

  test "badge_type must be unique" do
    {:ok, _} =
      %BadgeDefinition{}
      |> BadgeDefinition.changeset(%{
        badge_type: "founder",
        name: "Founder",
        description: "Early supporter.",
        narrative: "Joined during the launch window.",
        disabled: false
      })
      |> Repo.insert()

    {:error, changeset} =
      %BadgeDefinition{}
      |> BadgeDefinition.changeset(%{
        badge_type: "founder",
        name: "Founder",
        description: "Duplicate definition.",
        narrative: "Duplicate definition.",
        disabled: false
      })
      |> Repo.insert()

    assert %{badge_type: [_ | _]} = errors_on(changeset)
  end
end
