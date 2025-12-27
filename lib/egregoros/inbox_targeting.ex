defmodule Egregoros.InboxTargeting do
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationships

  @recipient_fields ~w(to cc bto bcc audience)

  def validate(opts, fun) when is_list(opts) and is_function(fun, 1) do
    if Keyword.get(opts, :local, true) do
      :ok
    else
      case Keyword.get(opts, :inbox_user_ap_id) do
        inbox_user_ap_id when is_binary(inbox_user_ap_id) ->
          inbox_user_ap_id = String.trim(inbox_user_ap_id)

          if inbox_user_ap_id == "" do
            :ok
          else
            fun.(inbox_user_ap_id)
          end

        _ ->
          :ok
      end
    end
  end

  def addressed_to?(%{} = activity, inbox_user_ap_id) when is_binary(inbox_user_ap_id) do
    inbox_user_ap_id = String.trim(inbox_user_ap_id)

    if inbox_user_ap_id == "" do
      false
    else
      Enum.any?(@recipient_fields, fn field ->
        activity
        |> Map.get(field)
        |> List.wrap()
        |> Enum.any?(fn recipient ->
          recipient_id =
            recipient
            |> extract_recipient_id()
            |> normalize_id()

          recipient_id == inbox_user_ap_id
        end)
      end)
    end
  end

  def addressed_to?(_activity, _inbox_user_ap_id), do: false

  def follows?(inbox_user_ap_id, actor_ap_id)
      when is_binary(inbox_user_ap_id) and is_binary(actor_ap_id) do
    inbox_user_ap_id = String.trim(inbox_user_ap_id)
    actor_ap_id = String.trim(actor_ap_id)

    if inbox_user_ap_id == "" or actor_ap_id == "" do
      false
    else
      Relationships.get_by_type_actor_object("Follow", inbox_user_ap_id, actor_ap_id) != nil
    end
  end

  def follows?(_inbox_user_ap_id, _actor_ap_id), do: false

  def object_owned_by?(object_ap_id, inbox_user_ap_id)
      when is_binary(object_ap_id) and is_binary(inbox_user_ap_id) do
    object_ap_id = String.trim(object_ap_id)
    inbox_user_ap_id = String.trim(inbox_user_ap_id)

    if object_ap_id == "" or inbox_user_ap_id == "" do
      false
    else
      case Objects.get_by_ap_id(object_ap_id) do
        %Object{actor: ^inbox_user_ap_id} -> true
        _ -> false
      end
    end
  end

  def object_owned_by?(_object_ap_id, _inbox_user_ap_id), do: false

  defp extract_recipient_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_recipient_id(%{id: id}) when is_binary(id), do: id
  defp extract_recipient_id(id) when is_binary(id), do: id
  defp extract_recipient_id(_), do: nil

  defp normalize_id(nil), do: ""

  defp normalize_id(id) when is_binary(id) do
    id
    |> String.trim()
  end
end

