defmodule EctoNPlusOne.Test do
  @default_threshold 3
  @default_min_parameter_variants 2
  @moduledoc """
  Tools for asserting in a test that a block of code does not perform N+1 queries.

  The runtime detector attached with `EctoNPlusOne.attach/2` doesn't work well inside tests; fixture setup,
  repeated renders, and the code under test all run in one process within one detection window, so ordinary queries
  look like N+1s.

  This module instead scopes detection to exactly one block of code:

      use EctoNPlusOne.Test,
        repos: MyApp.Repo,
        application_modules: [MyApp, MyAppWeb]

      test "the dashboard does not have an N+1", %{conn: conn} do
        insert_posts(5)

        {:ok, _view, html} =
          assert_no_n_plus_one(fn ->
            live(conn, ~p"/dashboard")
          end)

        assert html =~ "Posts"
      end

  Only queries executed *during the block* are considered, and only when they come from the test process itself
  or a process it (transitively) started, such as the LiveView process spawned by `Phoenix.LiveViewTest.live/2`.
  Fixture queries before the block, queries from concurrently running async tests, and the sandbox's own
  transaction management are all excluded.

  Within the block, a query group fails the assertion when the same SQL is executed from the same application callsite
  at least `:threshold` times (default #{@default_threshold}) with at least `:min_parameter_variants`
  distinct parameter sets (default #{@default_min_parameter_variants}). Requiring distinct parameters is what
  makes the check precise in tests; a page that runs one query per record in a loop produces one execution per record,
  each with different parameters, while a query that merely runs once per render (once in the disconnected state, then
  again in the connected LiveView mount) repeats with the *same* parameters and thus passes.

  ## Requirements

  Your test Repo must be configured with `stacktrace: true`, otherwise queries cannot be grouped by callsite.
  `assert_no_n_plus_one/2` raises with an explanation if query events arrive without stacktraces.

  ## Default options with `use`

  To avoid repeating `:repos` and `:application_modules` in every test, `use` this module (typically inside your
  `ConnCase`/`DataCase` template) to define wrappers with those defaults baked in:

      use EctoNPlusOne.Test,
        repos: MyApp.Repo,
        application_modules: [MyApp, MyAppWeb]

      test "no N+1", %{conn: conn} do
        assert_no_n_plus_one(fn -> live(conn, ~p"/dashboard") end)
      end

  If you don't want to set a global `use`, you can pass the `:repos` and `:application_modules` options on each call:

      test "no N+1", %{conn: conn} do
        EctoNPlusOne.Test.assert_no_n_plus_one(fn -> live(conn, ~p"/dashboard") end,
          repos: MyApp.Repo,
          application_modules: [MyApp, MyAppWeb]
        )
      end

  ## Ignoring intentional loops

  A query intentionally executed in a loop can be excluded per call with the `:ignore` predicate, or the
  `:threshold`/`:min_parameter_variants` options can be raised so the deliberate repetition stays below them.
  """

  alias EctoNPlusOne.{Accumulator, Detection}

  defmodule NPlusOneDetectedError do
    @moduledoc """
    Raised by `EctoNPlusOne.Test.assert_no_n_plus_one/2` when the checked block appears to perform an N+1 query.

    The `:detections` field holds the offending `EctoNPlusOne.Detection` structs.
    """
    defexception [:message, :detections]
  end

  @operations [:select, :insert, :update, :delete, :transaction, :other]

  # Queries in one test block conceptually belong to one page render, so groups never expire;
  # the window only needs to outlast any plausible test run.
  @window_ms to_timeout(minute: 30)

  @options_schema NimbleOptions.new!(
                    repos: [
                      required: true,
                      type: {:custom, EctoNPlusOne.Options, :validate_repos, []},
                      type_doc: "an Ecto Repo module or a non-empty list of Repo modules",
                      type_spec: quote(do: module() | [module()]),
                      doc: "the Repo(s) whose queries are checked"
                    ],
                    application_modules: [
                      required: true,
                      type: {:custom, EctoNPlusOne.Options, :validate_application_modules, []},
                      type_doc: "a non-empty list of top-level application modules",
                      type_spec: quote(do: [module()]),
                      doc: "require a stacktrace frame inside an application module namespace"
                    ],
                    threshold: [
                      type: :pos_integer,
                      default: 3,
                      doc: "minimum matching queries before raising an error"
                    ],
                    min_parameter_variants: [
                      type: :pos_integer,
                      default: 2,
                      doc:
                        "minimum distinct parameter sets on duplicated queries before raising an error"
                    ],
                    operations: [
                      type: {:or, [{:in, [:all]}, {:list, {:in, @operations}}]},
                      default: [:select],
                      type_doc: "`:all` or a list of SQL operation names",
                      type_spec: quote(do: :all | [atom()]),
                      doc: "SQL operations to inspect"
                    ],
                    ignore: [
                      type: {:fun, 1},
                      type_spec: quote(do: (map() -> as_boolean(term()))),
                      doc:
                        "predicate receiving a normalized query candidate; return true to ignore it"
                    ],
                    include_params: [
                      type: :boolean,
                      default: true,
                      doc: "retain parameter samples in detections and failure messages"
                    ],
                    max_samples: [
                      type: :non_neg_integer,
                      default: 3,
                      doc: "maximum retained parameter lists"
                    ],
                    max_queries: [
                      type: :pos_integer,
                      default: 1_000,
                      doc: "maximum distinct query shapes retained"
                    ]
                  )

  @typedoc """
  Options for `assert_no_n_plus_one/2` and `detect_n_plus_one_queries/2`.

  #{NimbleOptions.docs(@options_schema)}
  """
  @type option :: unquote(NimbleOptions.option_typespec(@options_schema))

  defmacro __using__(default_options) do
    quote do
      @doc "See `EctoNPlusOne.Test.assert_no_n_plus_one/2`."
      def assert_no_n_plus_one(fun, options \\ []) do
        EctoNPlusOne.Test.assert_no_n_plus_one(
          fun,
          Keyword.merge(unquote(default_options), options)
        )
      end

      @doc "See `EctoNPlusOne.Test.detect_n_plus_one_queries/2`."
      def detect_n_plus_one_queries(fun, options \\ []) do
        EctoNPlusOne.Test.detect_n_plus_one_queries(
          fun,
          Keyword.merge(unquote(default_options), options)
        )
      end
    end
  end

  @doc """
  Raises `EctoNPlusOne.Test.NPlusOneDetectedError` if `fun` appears to perform an N+1 query; otherwise returns `fun`'s result.

      {:ok, _view, html} =
        assert_no_n_plus_one(
          fn -> live(conn, ~p"/dashboard") end,
          repos: MyApp.Repo,
          application_modules: [MyApp, MyAppWeb]
        )

  See the module documentation for how detection works and `t:option/0` for the options.
  """
  @spec assert_no_n_plus_one((-> result), [option()]) :: result when result: term()
  def assert_no_n_plus_one(fun, options) do
    case detect_n_plus_one_queries(fun, options) do
      {result, []} ->
        result

      {_result, detections} ->
        raise NPlusOneDetectedError,
          message: format_detections(detections),
          detections: detections
    end
  end

  @doc """
  Run `fun` and return `{result, detections}`, where `detections` lists every potential N+1 query the block performed.

  `assert_no_n_plus_one/2` is built on this; use it directly to write custom assertions.
  """
  @spec detect_n_plus_one_queries((-> result), [option()]) :: {result, [Detection.t()]}
        when result: term()
  def detect_n_plus_one_queries(fun, options) when is_function(fun, 0) do
    options = validate_options!(options)
    events = EctoNPlusOne.event_names!(options[:repos])
    ref = make_ref()
    config = %{ref: ref, test_pid: self()}

    Enum.each(events, fn event ->
      :ok = :telemetry.attach(handler_id(ref, event), event, &__MODULE__.handle_event/4, config)
    end)

    result =
      try do
        fun.()
      after
        Enum.each(events, &:telemetry.detach(handler_id(ref, &1)))
      end

    {result, ref |> drain() |> analyze(options)}
  end

  @doc false
  @spec handle_event(:telemetry.event_name(), map(), map(), map()) :: :ok
  def handle_event(_event, measurements, metadata, config) do
    if from_test?(config.test_pid) do
      now = System.monotonic_time(:millisecond)
      send(config.test_pid, {config.ref, now, measurements, metadata})
    end

    :ok
  catch
    _kind, _reason -> :ok
  end

  # The handler runs in whatever process executed the query.
  # Collects the query when that process is the test process itself or was (transitively) started by it.
  defp from_test?(test_pid) do
    self() == test_pid or
      test_pid in resolve_pids(Process.get(:"$callers", [])) or
      test_pid in resolve_pids(Process.get(:"$ancestors", []))
  end

  defp resolve_pids(processes) when is_list(processes) do
    Enum.flat_map(processes, fn
      pid when is_pid(pid) ->
        [pid]

      name when is_atom(name) ->
        case Process.whereis(name) do
          nil -> []
          pid -> [pid]
        end

      _other ->
        []
    end)
  end

  defp drain(ref, acc \\ []) do
    receive do
      {^ref, now, measurements, metadata} -> drain(ref, [{now, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp analyze(query_events, options) do
    ensure_stacktraces!(query_events)

    query_events
    |> Enum.reduce(%{}, fn {now, measurements, metadata}, groups ->
      {groups, _key} = Accumulator.capture(groups, measurements, metadata, options, now)
      groups
    end)
    |> Accumulator.detections(options)
    |> merge_detections()
  end

  # One callsite can be reached through several application stacks inside the block, most commonly
  # a LiveView's disconnected and connected mounts. Grouping (and thus the thresholds) is per-stack,
  # exactly like the runtime detector, but detections that crossed the thresholds independently are
  # merged here so a failure reports each offending query once.
  defp merge_detections(detections) do
    detections
    |> Enum.group_by(&{&1.repo, &1.source, &1.operation, &1.query, &1.callsite})
    |> Enum.map(fn {_key, [first | rest]} ->
      Enum.reduce(rest, first, fn detection, merged ->
        %{
          merged
          | count: merged.count + detection.count,
            parameter_variants: max(merged.parameter_variants, detection.parameter_variants),
            total_time: merged.total_time + detection.total_time
        }
      end)
    end)
    |> Enum.sort_by(&{&1.count, &1.parameter_variants}, :desc)
  end

  defp ensure_stacktraces!([]), do: :ok

  defp ensure_stacktraces!(query_events) do
    has_stacktrace? =
      Enum.any?(query_events, fn {_now, _measurements, metadata} ->
        is_list(metadata[:stacktrace])
      end)

    if not has_stacktrace? do
      raise ArgumentError, """
      none of the captured Ecto query events carried a stacktrace, so queries cannot be grouped by callsite.

      Enable stacktraces for your test Repo, for example in config/test.exs:

          config :my_app, MyApp.Repo,
            # ...
            stacktrace: true
      """
    end

    :ok
  end

  defp validate_options!(options) when is_list(options) do
    options
    |> NimbleOptions.validate!(@options_schema)
    |> Keyword.put_new(:ignore, fn _query -> false end)
    |> Keyword.put(:window_ms, @window_ms)
  end

  defp validate_options!(options) do
    raise ArgumentError, "options must be a keyword list, got: #{inspect(options)}"
  end

  defp handler_id(ref, event), do: {__MODULE__, ref, event}

  defp format_detections(detections) do
    formatted =
      detections
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", &format_detection/1)

    """
    potential N+1 #{pluralize(detections)} detected during the checked block:

    #{formatted}

    If a repeated query above is intentional, raise :threshold or \
    :min_parameter_variants, or exclude it with an :ignore predicate.\
    """
  end

  defp pluralize([_detection]), do: "query"
  defp pluralize(_detections), do: "queries"

  defp format_detection({detection, index}) do
    """
      #{index}) #{detection.count} executions with #{detection.parameter_variants} distinct parameter sets (#{inspect(detection.repo)}, source #{inspect(detection.source)})

         #{detection.query}

         callsite: #{detection.callsite |> Exception.format_stacktrace_entry() |> String.trim()}\
    """ <> format_params(detection.params)
  end

  defp format_params([]), do: ""

  defp format_params(params),
    do: "\n     sample parameters: #{inspect(params, charlists: :as_lists)}"
end
