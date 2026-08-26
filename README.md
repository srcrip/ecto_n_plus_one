# EctoNPlusOne

quick explanation

## Installation

Add the hex package to your `mix.exs`:

```elixir
{:ecto_n_plus_one, "~> 0.1.0"}
```

## Setup / Usage

Then you'll need to attach the Telemetry handler in your `application.ex`:

```elixir
require Logger

def start(_type, _args) do
 # whatever else is in your application tree
 children = []

  :ok =
    # specify your Repo module
    EctoNPlusOne.attach(MyApp.Repo,
      # specify your main application modules, which EctoNPlusOne will use to
      # filter your stacktrace frames by to help determine problematic queries
      application_modules: [MyApp, MyAppWeb],
      # on_detect/1 will be called when we detect a potential N+1 query
      on_detect: fn detection ->
        Logger.warning("potential N+1 query detected: #{inspect(detection)}")
        # you can then do whatever you want in here: simply log it out, send a slack message, etc
      end
    )

  # starting the application tree as normal
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

If you want to keep it simple, you can have your `on_detect/1` function just be an anonymous function like the above.
But you may instead want to specify a module specifically for the library:

```elixir
# defining a module somewhere
defmodule MyApp.NPlusOneHandler do
  require Logger

  def handle(detection) do
    Logger.warning("N+1 query detected", count: detection.count, query: detection.query)
  end
end

# ... then in your application.ex
def start(_type, _args) do
  children = []

  :ok =
    EctoNPlusOne.attach(MyApp.Repo,
      application_modules: [MyApp, MyAppWeb],
      on_detect: fn detection ->
        MyApp.NPlusOneHandler.handle(detection)
      end
    )

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

This may be useful to you, because it also makes it a little simpler to define ignore patterns, which are another
feature of this library. You could do something like this:

```elixir
defmodule MyApp.EctoNPlusOne do
  require Logger

  alias MyApp.DataFoundation.BroadwaySettings

  def attach do
    EctoNPlusOne.attach(MyApp.Repo,
      application_modules: [MyApp, MyAppWeb],
      ignore: &ignore?/1,
      on_detect: &handle/1
    )
  end

  defp ignore?(%{
         source: "pipeline_settings",
         callsite: {BroadwaySettings, :effective_config, _, _}
       }),
       do: true

  defp ignore?(%{
         source: "schema_migrations",
         operation: :select
       }),
       do: true

  defp ignore?(_query), do: false

  defp handle(detection) do
    Logger.warning("N+1 query detected",
      count: detection.count,
      source: detection.source,
      callsite: inspect(detection.callsite),
      query: detection.query
    )
  end
end
```

And then you could call your attach function, which wraps up the libraries then, like this:

```elixir
# in your application.ex, as before
:ok = MyApp.EctoNPlusOne.attach()
```

## Options

Here's a full list of options to `attach/2`:

| Option | Default | Meaning |
| --- | --- | --- |
| `:threshold` | `5` | Minimum executions of one query shape |
| `:min_parameter_variants` | `1` | Minimum distinct parameter sets |
| `:application_modules` | required | Non-empty list of top-level application module namespaces |
| `:operations` | `[:select]` | Operations to inspect, or `:all` |
| `:ignore` | always false | Predicate receiving a normalized query candidate |
| `:include_params` | `false` | Retain parameter samples in detections |
| `:max_samples` | `3` | Maximum retained parameter samples |
| `:max_queries` | `1_000` | Maximum distinct shapes retained per process |
| `:window_ms` | `2_000` | Inactivity time before an automatic group expires |
| `:on_detect` | required | One-argument function invoked with the detection |

## Development

```shell
mix deps.get
mix compile
mix test
```

## License

See [LICENSE](LICENSE).
