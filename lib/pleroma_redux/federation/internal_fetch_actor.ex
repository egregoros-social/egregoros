defmodule PleromaRedux.Federation.InternalFetchActor do
  alias PleromaRedux.Users

  @nickname "internal.fetch"

  def get_actor do
    Users.get_or_create_local_user(@nickname)
  end
end
