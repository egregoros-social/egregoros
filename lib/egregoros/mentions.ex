defmodule Egregoros.Mentions do
  @moduledoc false

  @mention_trailing ".,!?;:)]},"

  def parse(handle) when is_binary(handle) do
    handle =
      handle
      |> String.trim()
      |> String.trim_leading("@")

    case String.split(handle, "@", parts: 2) do
      [nickname] ->
        if valid_nickname?(nickname), do: {:ok, nickname, nil}, else: :error

      [nickname, host] ->
        if valid_nickname?(nickname) and valid_host?(host),
          do: {:ok, nickname, host},
          else: :error

      _ ->
        :error
    end
  end

  def parse(_handle), do: :error

  def extract(content) when is_binary(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce(MapSet.new(), fn token, acc ->
      token = to_string(token)

      if String.starts_with?(token, "@") do
        {core, _trailing} = split_trailing_punctuation(token, @mention_trailing)

        case parse(core) do
          {:ok, nickname, host} -> MapSet.put(acc, {nickname, host})
          :error -> acc
        end
      else
        acc
      end
    end)
    |> MapSet.to_list()
  end

  def extract(_content), do: []

  defp split_trailing_punctuation(token, chars) when is_binary(token) and is_binary(chars) do
    {trailing_chars, core_chars} =
      token
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.split_while(&String.contains?(chars, &1))

    trailing = trailing_chars |> Enum.reverse() |> Enum.join()
    core = core_chars |> Enum.reverse() |> Enum.join()
    {core, trailing}
  end

  defp valid_nickname?(nickname) when is_binary(nickname) do
    Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/, nickname)
  end

  defp valid_nickname?(_), do: false

  defp valid_host?(host) when is_binary(host) do
    Regex.match?(~r/^[A-Za-z0-9.-]+(?::\d{1,5})?$/, host)
  end

  defp valid_host?(_), do: false
end
