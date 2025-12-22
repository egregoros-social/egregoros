defmodule PleromaReduxWeb.MastodonAPI.StreamingStreams do
  @known_streams ["public", "public:local", "user", "user:notification"]
  @timeline_streams ["public", "public:local", "user"]
  @notification_streams ["user", "user:notification"]
  @user_streams @notification_streams

  def known_streams, do: @known_streams
  def timeline_streams, do: @timeline_streams
  def notification_streams, do: @notification_streams
  def user_streams, do: @user_streams
end
