defmodule Egregoros.OAuth.TokenSchemaTest do
  use ExUnit.Case, async: true

  test "oauth token digests are stored in digest fields (not raw token columns)" do
    fields = Egregoros.OAuth.Token.__schema__(:fields)
    virtual_fields = Egregoros.OAuth.Token.__schema__(:virtual_fields)

    assert :token_digest in fields
    assert :refresh_token_digest in fields
    refute :token in fields
    refute :refresh_token in fields

    assert :token in virtual_fields
    assert :refresh_token in virtual_fields
  end
end

