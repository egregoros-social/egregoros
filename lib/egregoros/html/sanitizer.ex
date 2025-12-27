defmodule Egregoros.HTML.Sanitizer do
  @moduledoc false

  @callback scrub(binary(), module()) :: {:ok, iodata()} | {:error, term()}
end

