defmodule PleromaRedux.TestSupport.PleromaOldFixtures do
  @base Path.expand("../../pleroma-old/test/fixtures", __DIR__)

  def json!(name) when is_binary(name) do
    name
    |> fixture_path()
    |> File.read!()
    |> Jason.decode!()
  end

  defp fixture_path(name) when is_binary(name) do
    Path.join(@base, name)
  end
end
