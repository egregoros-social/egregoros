defmodule PleromaRedux.Bench.Suite do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.Repo
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  def default_cases do
    current_user = pick_local_user()

    [
      %{
        name: "timeline.public.list_notes(limit=20)",
        fun: fn -> Objects.list_notes(limit: 20) end
      },
      %{
        name: "timeline.home.list_home_notes(limit=20)",
        fun: fn ->
          case current_user do
            %User{} = user -> Objects.list_home_notes(user.ap_id, limit: 20)
            _ -> []
          end
        end
      },
      %{
        name: "render.status_vm.decorate_many(20)",
        fun: fn ->
          objects = Objects.list_notes(limit: 20)
          StatusVM.decorate_many(objects, current_user)
        end
      },
      %{
        name: "render.mastodon.statuses.render(20)",
        fun: fn ->
          objects = Objects.list_notes(limit: 20)
          StatusRenderer.render_statuses(objects, current_user)
        end
      },
      %{
        name: "search.users(query='local')",
        fun: fn -> Users.search("local", limit: 20) end
      },
      %{
        name: "search.notes(query='bench')",
        fun: fn -> Objects.search_notes("bench", limit: 20) end
      },
      %{
        name: "notifications.list_for_user(limit=20)",
        fun: fn ->
          case current_user do
            %User{} = user -> Notifications.list_for_user(user, limit: 20)
            _ -> []
          end
        end
      }
    ]
  end

  defp pick_local_user do
    from(u in User, where: u.local == true, order_by: [asc: u.id], limit: 1)
    |> Repo.one()
  end
end
