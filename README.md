# `EctoNPlusOne`

Ecto is a lot better than other ORMs in terms of making it possible to construct N+1 queries. It does not auto load
associations, and it has no syntax for auto loading them on record/object access, which many/most ORMs do. If you’re
like me, you’ve been using Ecto so long, you’ve forgotten that other ORMs don’t work this way. But many other ORMs
perform actual queries when doing record access, making it very simple to write N+1 queries.

Whilst Ecto is not susceptible to that particular problem, it is still quite possible to write N+1 queries. All you have
to do is have a loop in which you do some query inside, where the thing you loop over is possible to be some arbitrarily
large value (often itself even coming from another database value).

It's pretty easy to ensure you don't do this on new, small projects, where you can reasonably analyze every query your
doing. But when you accrue more and more code in a large project like a Phoenix application, it's quite possible to end
up writing stuff like this by mistake.

## Detection

`EctoNPlusOne` is designed to help you detect these possible N+1 queries. It works by attaching a Telemetry handler
when your application tree starts, listens to incoming queries, stores some information about them in the process
dictionary, and compares that information when new ones come in from the same process to see if they match a signal that
seems like it could be a potential N+1 situation.

Note two things:

1. This library can only detect possible problems, it is up to you to determine if they are actually problems or false
   positives.
2. Sometimes querying stuff in a loop is what you want to do. There is no foolproof way to 100% detect these situations
   because the detector can't know what you had in mind when you wrote it, if you wrote it intentionally that way.

You may also need to adjust the detection thresholds from their defaults, if you want to make things more or less
sensitive. You can also ignore certain queries, which is detailed below.

Is this performant? This library does end up storing state in the process dictionary, but it's virtually impossible that
you have a single process that is querying so many times that it's going to be a problem or a bottleneck.

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
        Logger.warning("potential N+1 query detected:", count: detection.count, query: detection.query)
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
    Logger.warning("potential N+1 query detected:", count: detection.count, query: detection.query)
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
