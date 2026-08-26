# EctoNPlusOne Phoenix demo

This Phoenix application deliberately creates an Ecto N+1 query and proves the
parent project detects it automatically. It uses SQLite, so no external database
is required.

## Run it

From this directory:

```shell
mix setup
mix phx.server
```

Visit [http://localhost:7070](http://localhost:7070). The seeded request loads
five authors and then issues one posts query per author. The page shows the SQL,
execution count, distinct parameter count, and application callsite delivered
to the example handler.

`mix setup` is safe to repeat. The seed script replaces the demo rows with a
known dataset.

## What to inspect

The application depends on the parent directory directly:

```elixir
{:ecto_n_plus_one, path: ".."}
```

The consuming application attaches the detector before starting its Repo in
`lib/ecto_n_plus_one_demo/application.ex`:

```elixir
EctoNPlusOne.attach(EctoNPlusOneDemo.Repo,
  application_modules: [EctoNPlusOneDemo, EctoNPlusOneDemoWeb],
  on_detect: &EctoNPlusOneDemo.DetectionHandler.handle/1
)
```

The intentionally inefficient catalog function contains no detector call:

```elixir
Author
|> Repo.all()
|> Enum.map(fn author ->
  Repo.all(from post in Post, where: post.author_id == ^author.id)
end)
```

That call attaches directly to `EctoNPlusOneDemo.Repo`'s query Telemetry event.
When the fifth posts query uses a fifth author ID, the group crosses the
default threshold and the configured handler is invoked.

The handler logs the detection at warning level and sends it back to the
Phoenix request process so the page can render it. After visiting `/`, the same
detection is visible both in the `mix phx.server` terminal and on the page. A
real application could instead report to its error tracker, developer toolbar,
structured logger, or another alerting system.

The same catalog context contains `list_authors_with_posts_preloaded/0`, which
uses an Ecto preload and does not trigger a detection.

## Run the focused proof

```shell
mix test \
  test/ecto_n_plus_one_demo/scenario_test.exs \
  test/ecto_n_plus_one_demo_web/controllers/page_controller_test.exs
```

The tests prove that:

- The unwrapped per-author loop calls the globally configured handler.
- The detection contains five executions and five parameter variants when the
  threshold is crossed.
- The callsite points to the application loader rather than Ecto internals.
- The Phoenix page renders the warning.
- The preloaded implementation produces no warning.

## Query stacktraces

The demo Repo configurations enable query stacktraces:

```elixir
stacktrace: true,
log_stacktrace_mfa: {Ecto.Adapters.SQL, :first_non_ecto_stacktrace, [5]}
```

`stacktrace: true` supplies the complete available stacktrace in Ecto's
Telemetry metadata. EctoNPlusOne filters that stack to the configured
application modules and uses every matching frame for grouping. The
`log_stacktrace_mfa` setting only makes Ecto's own development query logs more
useful; it does not affect detector grouping.
