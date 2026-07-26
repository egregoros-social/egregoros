# Extending Egregoros with New Activity Types

This document describes how to add support for new ActivityPub activity or object types to Egregoros, covering both ingestion (backend) and display (frontend).

## Overview

The ingestion pipeline follows this flow:

```
ActivityPub JSON → Pipeline.ingest/2 → ActivityRegistry → Activity Module
                                                              ↓
                                                       cast_and_validate/1
                                                              ↓
                                                         ingest/2
                                                              ↓
                                                       side_effects/2
```

For timeline display:

```
Object → Status.decorate/2 → TimelineItem component → Type-specific card
```

## Step 1: Create the Activity Handler Module

Create a new module in `lib/egregoros/activities/`. The module must:

1. Define a `type/0` function returning the ActivityPub type string
2. Implement `cast_and_validate/1` for validation
3. Implement `ingest/2` for persistence
4. Implement `side_effects/2` for post-ingestion actions

### Minimal Example

```elixir
defmodule Egregoros.Activities.MyType do
  @moduledoc """
  Activity handler for ActivityPub MyType objects.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.Objects

  # Required: This registers the module with ActivityRegistry
  def type, do: "MyType"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
    # Add type-specific fields here
  end

  def cast_and_validate(activity) when is_map(activity) do
    activity = normalize(activity)

    changeset =
      %__MODULE__{}
      |> cast(activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor])
      |> validate_inclusion(:type, [type()])

    case apply_action(changeset, :insert) do
      {:ok, validated} -> {:ok, build_result(activity, validated)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def ingest(activity, opts) do
    activity
    |> to_object_attrs(opts)
    |> Objects.upsert_object()
  end

  def side_effects(_object, _opts) do
    # Perform any post-ingestion work here
    :ok
  end

  defp to_object_attrs(activity, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: nil,  # Or the target object's ap_id if applicable
      data: activity,
      published: Helpers.parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
  end

  defp normalize(activity), do: activity
  defp build_result(activity, _validated), do: activity
end
```

### Key Points

- The `type/0` function is auto-discovered by `ActivityRegistry` - no registration needed
- The module path must be under `Egregoros.Activities.*`
- Always return `{:ok, map}` or `{:error, changeset}` from `cast_and_validate/1`
- Always return `:ok` from `side_effects/2` (or `{:error, reason}` on failure)
- Use `Objects.upsert_object/1` for idempotent ingestion

### Common Patterns

**Normalizing `attributedTo` to `actor`:**

```elixir
defp normalize_actor(%{"actor" => _} = activity), do: activity
defp normalize_actor(%{"attributedTo" => actor} = activity) do
  Map.put(activity, "actor", actor)
end
defp normalize_actor(activity), do: activity
```

**Storing private, server-only state (do not leak via federation):**

Use the `objects.internal` column for state that must never be repeated to clients or remote servers
(e.g., poll voter tracking). Never store private state in `data`.

```elixir
updated_internal =
  object
  |> Map.get(:internal)
  |> Kernel.||(%{})
  |> Map.put("my_type", %{"private" => "value"})

object
|> Object.changeset(%{internal: updated_internal})
|> Repo.update()
```

**Inbox targeting validation (for federated objects):**

```elixir
alias Egregoros.InboxTargeting

defp validate_inbox_target(activity, opts) do
  InboxTargeting.validate(opts, fn inbox_user_ap_id ->
    actor_ap_id = Map.get(activity, "actor")

    cond do
      InboxTargeting.addressed_to?(activity, inbox_user_ap_id) -> :ok
      InboxTargeting.follows?(inbox_user_ap_id, actor_ap_id) -> :ok
      true -> {:error, :not_targeted}
    end
  end)
end
```

**Normalize Create-wrapped objects when remote servers embed a different type:**

Some servers send objects inside a `Create` that need type normalization before validation.
For example, poll votes arrive as `Create` with an embedded `Note` containing `name` and `inReplyTo`,
which must be converted into an `Answer` before validation and ingestion.

Add a normalization step in `Egregoros.Activities.Create` to coerce the embedded object type when needed,
and ensure inbox targeting accepts cases where the embedded object is addressed to the inbox user
even if the Create itself has empty `to`/`cc`.

## Step 2: Add to Status Types (if timeline-displayable)

If your type should appear in timelines, add it to `@status_types` in `lib/egregoros/objects.ex`:

```elixir
@status_types ~w(Note Announce Question MyType)
```

This affects which object types are fetched for timeline queries.

## Step 3: Add to Timeline Types Filter

Add your type to `@timeline_types` in `lib/egregoros_web/live/timeline_live.ex`:

```elixir
@timeline_types ["Note", "Announce", "Question", "MyType"]
```

This controls which types pass the `include_post?/4` filter.

## Step 4: Extend the Status View Model

Update `lib/egregoros_web/view_models/status.ex`:

### 4a. Add decorate clause

```elixir
def decorate(%{type: "MyType"} = object, current_user) do
  decorate_one(object, current_user)
end
```

### 4b. Add to content_objects filter

In `decoration_context/2`, update the filter:

```elixir
content_objects =
  objects
  |> Enum.filter(&match?(%{type: type} when type in ["Note", "Question", "MyType"], &1))
```

### 4c. Add decorate_with_context clause

```elixir
defp decorate_with_context(%{type: "MyType"} = object, current_user, ctx) do
  decorate_content_with_context(object, current_user, ctx, feed_id: object.id)
end
```

### 4d. Update decorate_content_with_context guard (if sharing logic)

```elixir
defp decorate_content_with_context(%{type: type} = object, current_user, ctx, opts)
     when type in ["Note", "Question", "MyType"] do
  # ... shared decoration logic
end
```

### 4e. Add type-specific view model data (optional)

If your type needs additional data (like poll options for Question):

```elixir
decorated =
  case type do
    "Question" -> Map.put(decorated, :poll, poll_view_model(object, current_user))
    "MyType" -> Map.put(decorated, :my_data, my_type_view_model(object))
    _ -> decorated
  end
```

## Step 5: Create Timeline Card Component

Create `lib/egregoros_web/components/timeline_items/my_type_card.ex`:

```elixir
defmodule EgregorosWeb.Components.TimelineItems.MyTypeCard do
  @moduledoc """
  Component for rendering MyType objects in timelines.
  """
  use EgregorosWeb, :html

  alias EgregorosWeb.Components.Shared.ActorHeader
  alias EgregorosWeb.Components.Shared.InteractionBar

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil
  attr :back_timeline, :any, default: nil
  attr :reply_mode, :atom, default: :navigate

  def my_type_card(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="status-card"
      data-type="MyType"
      class="border-b border-[color:var(--border-muted)] bg-[color:var(--bg-base)] p-5"
    >
      <ActorHeader.actor_header
        actor={@entry.actor}
        object={@entry.object}
      />

      <%!-- Type-specific content here --%>

      <InteractionBar.interaction_bar
        id={@id}
        entry={@entry}
        current_user={@current_user}
        reply_mode={@reply_mode}
      />
    </article>
    """
  end
end
```

## Step 6: Register in TimelineItem Dispatcher

Update `lib/egregoros_web/components/timeline_items/timeline_item.ex`:

```elixir
alias EgregorosWeb.Components.TimelineItems.MyTypeCard

def timeline_item(assigns) do
  ~H"""
  <%= case object_type(@entry) do %>
    <% "Note" -> %>
      <NoteCard.note_card ... />
    <% "Announce" -> %>
      <AnnounceCard.announce_card ... />
    <% "Question" -> %>
      <PollCard.poll_card ... />
    <% "MyType" -> %>
      <MyTypeCard.my_type_card
        id={@id}
        entry={@entry}
        current_user={@current_user}
        back_timeline={@back_timeline}
        reply_mode={@reply_mode}
      />
    <% _unknown -> %>
      <.fallback_card id={@id} entry={@entry} />
  <% end %>
  """
end
```

## Step 7: Write Tests

### Cast and Validate Tests

Create `test/egregoros/activities/my_type_cast_and_validate_test.exs`:

```elixir
defmodule Egregoros.Activities.MyTypeCastAndValidateTest do
  use ExUnit.Case, async: true

  alias Egregoros.Activities.MyType

  describe "cast_and_validate/1" do
    test "validates a valid object" do
      object = %{
        "id" => "https://example.com/objects/1",
        "type" => "MyType",
        "actor" => "https://example.com/users/alice"
      }

      assert {:ok, validated} = MyType.cast_and_validate(object)
      assert validated["type"] == "MyType"
    end

    test "rejects invalid type" do
      object = %{
        "id" => "https://example.com/objects/1",
        "type" => "WrongType",
        "actor" => "https://example.com/users/alice"
      }

      assert {:error, %Ecto.Changeset{}} = MyType.cast_and_validate(object)
    end
  end
end
```

### Ingest Tests

Create `test/egregoros/activities/my_type_ingest_test.exs`:

```elixir
defmodule Egregoros.Activities.MyTypeIngestTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Pipeline
  alias Egregoros.Users

  describe "MyType ingestion" do
    test "ingests a valid object" do
      {:ok, alice} = Users.create_local_user("alice")

      object = %{
        "id" => "https://example.com/objects/" <> Ecto.UUID.generate(),
        "type" => "MyType",
        "attributedTo" => alice.ap_id,
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }

      assert {:ok, result} = Pipeline.ingest(object, local: true)
      assert result.type == "MyType"
      assert result.actor == alice.ap_id
    end
  end
end
```

## Step 8: Side Effects (Optional)

If your type needs to modify other objects (like Answer updating Question vote counts):

```elixir
def side_effects(object, _opts) do
  with %{data: %{"target" => target_ap_id}} when is_binary(target_ap_id) <- object do
    # Perform side effect
    Objects.update_something(target_ap_id, ...)
  end

  :ok
end
```

Key principles:
- Always return `:ok` even if the side effect doesn't apply
- Use `with` to safely extract required data
- Don't crash on missing data - gracefully skip
- If you update a timeline-visible object, broadcast it so LiveView clients refresh:

```elixir
with {:ok, updated} <- Objects.update_something(...) do
  Timeline.broadcast_post_updated(updated)
end
```

## Step 9: Type-Specific Publish Operations (Optional)

If your type requires specialized publish operations (like voting on polls), create a submodule under `lib/egregoros/publish/`.

### Creating a Publish Submodule

Create `lib/egregoros/publish/my_type.ex`:

```elixir
defmodule Egregoros.Publish.MyType do
  @moduledoc """
  MyType-specific publish operations.

  Handles publishing actions specific to ActivityPub MyType objects.
  """

  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.User

  @doc """
  Example publish operation for MyType.

  ## Parameters
  - `user` - The user performing the action
  - `object` - The MyType object to act on
  - `data` - Additional data for the operation

  ## Returns
  - `{:ok, updated_object}` on success
  - `{:error, reason}` on failure
  """
  def my_action(%User{} = user, %Object{type: "MyType"} = object, data) do
    # Validation and business logic here
    with :ok <- validate_something(user, object),
         {:ok, _activity} <- create_activity(user, object, data) do
      {:ok, Objects.get_by_ap_id(object.ap_id)}
    end
  end

  def my_action(_user, _object, _data), do: {:error, :invalid_object}

  # Private validation and helper functions...
end
```

### Adding Delegations

Add delegations in `lib/egregoros/publish.ex` to maintain the public API:

```elixir
defmodule Egregoros.Publish do
  # ... existing aliases ...
  alias Egregoros.Publish.MyType

  # Delegations to submodules
  defdelegate my_action(user, object, data), to: MyType
end
```

### Key Principles

- **Delegation pattern**: Keep the public API in `Publish` via `defdelegate`
- **Type guards**: Use pattern matching to ensure operations only apply to the correct type
- **Return tuples**: Always return `{:ok, result}` or `{:error, reason}`
- **Validation first**: Validate all preconditions before performing actions

### Existing Submodules

- `Publish.Polls` - Poll (Question) specific operations:
  - `vote_on_poll/3` - Cast votes on a poll
- `Publish.Notes` - Note specific operations:
  - `post_note/2` - Post a note with default options
  - `post_note/3` - Post a note with options (attachments, visibility, etc.)

## Step 10: Type-Specific Object Operations (Optional)

If your type requires specialized object operations (like poll vote counting for Questions), create a submodule under `lib/egregoros/objects/`.

### Creating an Objects Submodule

Create `lib/egregoros/objects/my_type.ex`:

```elixir
defmodule Egregoros.Objects.MyType do
  @moduledoc """
  MyType-specific object operations.

  Handles operations specific to ActivityPub MyType objects.
  """

  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Repo

  @doc """
  Example type-specific operation.
  """
  def my_operation(%Object{type: "MyType"} = object, arg) do
    # Type-specific logic here
    {:ok, object}
  end

  def my_operation(_object, _arg), do: :noop
end
```

### Adding Delegations

Add delegations in `lib/egregoros/objects.ex` to maintain the public API:

```elixir
defmodule Egregoros.Objects do
  # ... existing aliases ...
  alias Egregoros.Objects.MyType

  # Delegations to submodules
  defdelegate my_operation(object, arg), to: MyType
```

### Key Principles

- **Delegation pattern**: Keep the public API in `Objects` via `defdelegate`
- **Type guards**: Use pattern matching to ensure operations only apply to the correct type
- **Return `:noop`**: For operations that don't apply to the given object type
- **Existing example**: See `lib/egregoros/objects/polls.ex` for poll-specific operations

### Existing Submodules

- `Objects.Polls` - Poll (Question) specific operations:
  - `increase_vote_count/3` - Increments vote count for a poll option
  - `multiple?/1` - Returns whether a poll allows multiple choices

## Step 11: Add Mastodon API Routes (Optional)

If your type needs Mastodon API endpoints (for client apps), create a controller following Option B (documented controller modules).

### Creating the Controller

Create `lib/egregoros_web/controllers/mastodon_api/my_types_controller.ex`:

```elixir
defmodule EgregorosWeb.MastodonAPI.MyTypesController do
  @moduledoc """
  Mastodon API controller for MyType operations.

  ## Routes (add to router.ex)

      # In the `pipe_through [:api, :api_optional_auth]` scope:
      get "/my_types/:id", MyTypesController, :show

      # In the `pipe_through [:api, :api_auth, :oauth_write]` scope:
      post "/my_types/:id/action", MyTypesController, :action

  ## Endpoints

  ### GET /api/v1/my_types/:id
  Returns a MyType entity.

  **Authentication:** Public (optional auth for user-specific data)

  **Response:** MyType entity JSON

  ### POST /api/v1/my_types/:id/action
  Performs an action on a MyType.

  **Authentication:** Required (OAuth scope: `write:statuses`)

  **Request body:**
  ```json
  {
    "param": "value"
  }
  ```

  **Response:** Updated MyType entity JSON
  """
  use EgregorosWeb, :controller

  alias Egregoros.Objects
  alias Egregoros.Publish
  alias EgregorosWeb.MastodonAPI.MyTypeRenderer

  def show(conn, %{"id" => id}) do
    with {id, ""} <- Integer.parse(id),
         %{type: "MyType"} = object <- Objects.get(id) do
      current_user = conn.assigns[:current_user]
      json(conn, MyTypeRenderer.render(object, current_user))
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "Record not found"})
    end
  end

  def action(conn, %{"id" => id, "param" => param}) do
    with %{id: user_id} = user <- conn.assigns[:current_user],
         {id, ""} <- Integer.parse(id),
         %{type: "MyType"} = object <- Objects.get(id),
         {:ok, updated} <- Publish.my_type_action(user, object, param) do
      json(conn, MyTypeRenderer.render(updated, user))
    else
      nil -> conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
      {:error, :some_error} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "Error message"})
      _ -> conn |> put_status(:not_found) |> json(%{error: "Record not found"})
    end
  end
end
```

### Creating the Renderer

Create `lib/egregoros_web/mastodon_api/my_type_renderer.ex`:

```elixir
defmodule EgregorosWeb.MastodonAPI.MyTypeRenderer do
  @moduledoc """
  Renders MyType objects for the Mastodon API.
  """

  alias Egregoros.Object
  alias Egregoros.User

  def render(%Object{type: "MyType", data: data} = object, current_user) when is_map(data) do
    %{
      "id" => Integer.to_string(object.id),
      # Add type-specific fields here
    }
  end

  def render(_object, _current_user), do: nil
end
```

### Adding Routes

Update `lib/egregoros_web/router.ex`:

```elixir
# In the scope with `pipe_through [:api, :api_optional_auth]`:
get "/my_types/:id", MyTypesController, :show

# In the scope with `pipe_through [:api, :api_auth, :oauth_write]`:
post "/my_types/:id/action", MyTypesController, :action
```

### Existing API Controllers

- `PollsController` - Poll (Question) operations:
  - `GET /api/v1/polls/:id` - View poll details (optional auth)
  - `POST /api/v1/polls/:id/votes` - Vote on poll (requires `write:statuses` scope)

## Poll-Specific Notes (Question/Answer)

When adding or extending poll support, match these patterns:

- **Question choices** live in `oneOf` (single choice) or `anyOf` (multiple choice), and vote counts are stored in each option’s `replies.totalItems`.
- **Answers as votes**: remote servers often send votes as `Create` with an embedded `Note` that has `name` and `inReplyTo`. Normalize this to an `Answer` before validation/ingest (in `Egregoros.Activities.Create`), and make inbox targeting accept cases where the embedded object is addressed to the inbox user even if the `Create` itself is not.
- **Private vote tracking** belongs in `objects.internal` (e.g., per-voter tracking and per-option voter lists) so it never leaks via federation.
- **Live updates**: when vote side-effects update a `Question`, broadcast the updated object via `Timeline.broadcast_post_updated/1` so connected LiveViews refresh without a full page reload.
- **Tests to include**: Answer ingest + vote count side-effects; Create-with-Note normalization; and a PubSub assertion that a vote triggers `{:post_updated, question}`.

## Summary Checklist

- [ ] Create activity module in `lib/egregoros/activities/`
  - [ ] Define `type/0` function
  - [ ] Implement `cast_and_validate/1`
  - [ ] Implement `ingest/2`
  - [ ] Implement `side_effects/2`
- [ ] Add to `@status_types` in `lib/egregoros/objects.ex` (if timeline-displayable)
- [ ] Add to `@timeline_types` in `lib/egregoros_web/live/timeline_live.ex`
- [ ] Update `lib/egregoros_web/view_models/status.ex`:
  - [ ] Add `decorate/2` clause
  - [ ] Update `content_objects` filter in `decoration_context/2`
  - [ ] Add `decorate_with_context/3` clause
  - [ ] Update `decorate_content_with_context/4` guard
  - [ ] Add type-specific view model helper (optional)
- [ ] Create card component in `lib/egregoros_web/components/timeline_items/`
- [ ] Register in `timeline_item.ex` dispatcher
- [ ] Write tests:
  - [ ] Cast and validate tests
  - [ ] Ingest tests
  - [ ] Side effects tests (if applicable)
- [ ] Create Publish submodule for type-specific publish operations (optional):
  - [ ] Create `lib/egregoros/publish/my_type.ex`
  - [ ] Add delegation in `lib/egregoros/publish.ex`
- [ ] Create Objects submodule for type-specific object operations (optional):
  - [ ] Create `lib/egregoros/objects/my_type.ex`
  - [ ] Add delegation in `lib/egregoros/objects.ex`
- [ ] Add Mastodon API routes (optional):
  - [ ] Create controller in `lib/egregoros_web/controllers/mastodon_api/`
  - [ ] Create renderer in `lib/egregoros_web/mastodon_api/`
  - [ ] Add routes to `lib/egregoros_web/router.ex`
