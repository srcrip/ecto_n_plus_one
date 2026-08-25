defmodule EctoNPlusOne do
  @moduledoc """
  Detect n+1 queries in Ecto.
  """

  alias EctoNPlusOne.Telemetry

  @operations [:select, :insert, :update, :delete, :transaction, :other]

  @options_schema NimbleOptions.new!(
                    threshold: [
                      type: :pos_integer,
                      default: 5,
                      doc: "minimum matching queries"
                    ],
                    min_parameter_variants: [
                      type: :pos_integer,
                      default: 1,
                      doc: "minimum distinct parameter sets"
                    ],
                    group_by_callsite: [
                      type: :boolean,
                      default: true,
                      doc: "separate query shapes by the complete application stacktrace"
                    ],
                    application_modules: [
                      required: true,
                      type: {:custom, EctoNPlusOne.Options, :validate_application_modules, []},
                      type_doc: "a non-empty list of top-level modules",
                      type_spec: quote(do: [module()]),
                      doc: "require a stacktrace frame inside an application module namespace"
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
                      doc: "predicate receiving a normalized query candidate"
                    ],
                    exclude: [
                      type: {:fun, 1},
                      type_spec: quote(do: (map() -> as_boolean(term()))),
                      doc: "predicate receiving raw Ecto event metadata"
                    ],
                    include_params: [
                      type: :boolean,
                      default: false,
                      doc: "retain parameter samples"
                    ],
                    max_samples: [
                      type: :non_neg_integer,
                      default: 3,
                      doc: "maximum retained parameter lists"
                    ],
                    max_queries: [
                      type: :pos_integer,
                      default: 1_000,
                      doc: "maximum distinct query shapes retained per process"
                    ],
                    window_ms: [
                      type: :pos_integer,
                      default: 2_000,
                      doc: "inactivity window for query groups"
                    ],
                    on_detect: [
                      required: true,
                      type: {:fun, 1},
                      type_spec: quote(do: ([struct()] -> term())),
                      doc: "handler invoked when a query group crosses the thresholds"
                    ]
                  )

  @typedoc "An Ecto Repo module or a non-empty list of Repo modules."
  @type repos :: module() | [module()]

  @typedoc """
  Detection options.

  #{NimbleOptions.docs(@options_schema)}
  """
  @type option :: unquote(NimbleOptions.option_typespec(@options_schema))

  @doc """
  Attach the telemetry handler to one or more of your Ecto repos.

  Do this once in your main application.ex file.
  """
  @spec attach(repos(), [option()]) :: :ok
  def attach(repos, opts) do
    options = validate_options!(opts)
    repos |> event_names!() |> Telemetry.attach(options)
  end

  @doc """
  Detach the telemetry handler.
  """
  @spec detach(repos()) :: :ok
  def detach(repos), do: repos |> event_names!() |> Telemetry.detach()

  defp event_names!(repos) when is_list(repos) do
    case repos |> Enum.map(&event_name!/1) |> Enum.uniq() do
      [] -> raise ArgumentError, "at least one Ecto Repo is required"
      events -> events
    end
  end

  defp event_names!(repo) when is_atom(repo), do: [event_name!(repo)]

  defp event_names!(repo),
    do: raise(ArgumentError, "expected an Ecto Repo module, got: #{inspect(repo)}")

  defp event_name!(repo) when is_atom(repo) do
    case repo.config()[:telemetry_prefix] do
      prefix when is_list(prefix) and prefix != [] ->
        prefix ++ [:query]

      value ->
        raise ArgumentError,
              "#{inspect(repo)} has an invalid :telemetry_prefix: #{inspect(value)}"
    end
  rescue
    UndefinedFunctionError ->
      raise ArgumentError, "expected an Ecto Repo module, got: #{inspect(repo)}"
  end

  defp event_name!(repo),
    do: raise(ArgumentError, "expected an Ecto Repo module, got: #{inspect(repo)}")

  defp validate_options!(opts) when is_list(opts) do
    opts
    |> NimbleOptions.validate!(@options_schema)
    |> Keyword.put_new(:ignore, &never_ignore?/1)
    |> Keyword.put_new(:exclude, &never_ignore?/1)
  end

  defp validate_options!(opts),
    do: raise(ArgumentError, "options must be a keyword list, got: #{inspect(opts)}")

  defp never_ignore?(_query), do: false
end
