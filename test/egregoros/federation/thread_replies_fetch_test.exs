defmodule Egregoros.Federation.ThreadRepliesFetchTest do
  use Egregoros.DataCase, async: true

  import Mox

  alias Egregoros.Objects
  alias Egregoros.Workers.FetchThreadReplies

  test "thread replies worker fetches and ingests replies from an OrderedCollectionPage" do
    root_id = "https://remote.example/objects/root"
    replies_url = root_id <> "/replies"
    reply_id = "https://remote.example/objects/reply-1"

    {:ok, root} =
      Objects.create_object(%{
        ap_id: root_id,
        type: "Note",
        actor: "https://remote.example/users/alice",
        local: false,
        data: %{
          "id" => root_id,
          "type" => "Note",
          "attributedTo" => "https://remote.example/users/alice",
          "content" => "<p>Root</p>",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => [],
          "replies" => %{
            "id" => replies_url,
            "type" => "OrderedCollection"
          }
        }
      })

    expect(Egregoros.HTTP.Mock, :get, fn url, headers ->
      assert url == replies_url
      assert List.keyfind(headers, "signature", 0)
      assert List.keyfind(headers, "authorization", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => replies_url,
           "type" => "OrderedCollectionPage",
           "orderedItems" => [
             %{
               "id" => reply_id,
               "type" => "Note",
               "attributedTo" => "https://remote.example/users/bob",
               "content" => "<p>Reply</p>",
               "inReplyTo" => root_id,
               "to" => ["https://www.w3.org/ns/activitystreams#Public"],
               "cc" => []
             }
           ]
         },
         headers: []
       }}
    end)

    job =
      %Oban.Job{
        args: %{
          "root_ap_id" => root_id,
          "max_pages" => 1,
          "max_items" => 50
        }
      }

    assert :ok = FetchThreadReplies.perform(job)

    assert Objects.get_by_ap_id(reply_id)
    assert Enum.any?(Objects.thread_descendants(root), &(&1.ap_id == reply_id))
  end

  test "thread replies worker follows a collection's `first` page when needed" do
    root_id = "https://remote.example/objects/root-2"
    replies_url = root_id <> "/replies"
    first_page = replies_url <> "?page=true"
    reply_id = "https://remote.example/objects/reply-2"

    {:ok, root} =
      Objects.create_object(%{
        ap_id: root_id,
        type: "Note",
        actor: "https://remote.example/users/alice",
        local: false,
        data: %{
          "id" => root_id,
          "type" => "Note",
          "attributedTo" => "https://remote.example/users/alice",
          "content" => "<p>Root</p>",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => [],
          "replies" => replies_url
        }
      })

    expect(Egregoros.HTTP.Mock, :get, fn url, headers ->
      assert url == replies_url
      assert List.keyfind(headers, "signature", 0)
      assert List.keyfind(headers, "authorization", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => replies_url,
           "type" => "OrderedCollection",
           "first" => first_page
         },
         headers: []
       }}
    end)

    expect(Egregoros.HTTP.Mock, :get, fn url, headers ->
      assert url == first_page
      assert List.keyfind(headers, "signature", 0)
      assert List.keyfind(headers, "authorization", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => first_page,
           "type" => "OrderedCollectionPage",
           "orderedItems" => [
             %{
               "id" => reply_id,
               "type" => "Note",
               "attributedTo" => "https://remote.example/users/bob",
               "content" => "<p>Reply</p>",
               "inReplyTo" => root_id,
               "to" => ["https://www.w3.org/ns/activitystreams#Public"],
               "cc" => []
             }
           ]
         },
         headers: []
       }}
    end)

    job = %Oban.Job{args: %{"root_ap_id" => root_id, "max_pages" => 2, "max_items" => 50}}
    assert :ok = FetchThreadReplies.perform(job)

    assert Objects.get_by_ap_id(reply_id)
    assert Enum.any?(Objects.thread_descendants(root), &(&1.ap_id == reply_id))
  end
end

