defmodule PleromaRedux.DNS.Stub do
  @behaviour PleromaRedux.DNS

  @impl true
  def lookup_ips(_host) do
    {:ok, [{1, 1, 1, 1}]}
  end
end

