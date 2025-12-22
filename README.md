# PleromaRedux

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Troubleshooting

### `:emfile` / "too many open files" crash under load

If you see errors like `Unexpected error in accept: :emfile` (Bandit/ThousandIsland) or
`File operation error: emfile`, your OS file descriptor limit is too low (often `ulimit -n 256`).

Increase it before starting the server:

```sh
ulimit -n 8192
mix phx.server
```

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
