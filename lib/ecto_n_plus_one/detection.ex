defmodule EctoNPlusOne.Detection do
  @moduledoc """
  Information about a potential N+1 query passed to the configured `:on_detect` callback.

  A detection represents one parameterized query shape after it crosses the configured
  execution and parameter-variant thresholds.

  The fields are:

    * `:query` - the parameterized SQL string with surrounding whitespace removed
    * `:repo` and `:source` - the Repo and Ecto source that emitted the query
    * `:operation` - the classified SQL operation
    * `:count` - executions observed in the active window when detection occurred
    * `:parameter_variants` - distinct parameter signatures observed
    * `:params` - retained parameter samples, empty unless `:include_params` is enabled
    * `:callsite` - the nearest frame under a configured application module
    * `:stacktrace` - every matching application frame used to group the query
    * `:total_time` - accumulated Ecto `:total_time` in native time units
  """

  @enforce_keys [
    :callsite,
    :count,
    :operation,
    :parameter_variants,
    :params,
    :query,
    :repo,
    :source,
    :stacktrace,
    :total_time
  ]
  defstruct [
    :callsite,
    :count,
    :operation,
    :parameter_variants,
    :params,
    :query,
    :repo,
    :source,
    :total_time,
    :stacktrace
  ]

  @type operation :: :select | :insert | :update | :delete | :transaction | :other

  @typedoc "A potential N+1 query detected from Ecto telemetry events."
  @type t :: %__MODULE__{
          callsite: Exception.stacktrace_entry(),
          count: pos_integer(),
          operation: operation(),
          parameter_variants: pos_integer(),
          params: [term()],
          query: String.t(),
          repo: module(),
          source: term(),
          total_time: non_neg_integer(),
          stacktrace: Exception.stacktrace()
        }

  @doc false
  @spec normalize_query(String.t()) :: String.t()
  def normalize_query(query), do: String.trim(query)

  @doc false
  @spec application_stacktrace(Exception.stacktrace() | nil, [module() | nil], [module()]) ::
          Exception.stacktrace()
  def application_stacktrace(stacktrace, ignored_modules, application_modules)
      when is_list(stacktrace) do
    namespaces = Enum.map(application_modules, &namespace/1)
    Enum.filter(stacktrace, &application_frame?(&1, ignored_modules, namespaces))
  end

  def application_stacktrace(_stacktrace, _ignored_modules, _application_modules), do: []

  @doc false
  @spec stacktrace_signature(Exception.stacktrace()) :: list()
  def stacktrace_signature(stacktrace) do
    stacktrace
    |> Enum.map(&frame_signature/1)
    |> Enum.dedup()
  end

  @doc false
  @spec operation(String.t()) :: operation()
  def operation(query) do
    query
    |> skip_comments()
    |> first_word()
    |> String.upcase()
    |> classify()
  end

  # Walks past leading whitespace and comments only, so the cost does not grow
  # with the length of the query.
  defp skip_comments(<<char, rest::binary>>) when char in ~c" \t\n\r\f\v",
    do: skip_comments(rest)

  defp skip_comments(<<"--", rest::binary>>) do
    case :binary.split(rest, "\n") do
      [_comment, rest] -> skip_comments(rest)
      [_comment] -> ""
    end
  end

  defp skip_comments(<<"/*", rest::binary>> = query) do
    case :binary.split(rest, "*/") do
      [_comment, rest] -> skip_comments(rest)
      [_unterminated] -> query
    end
  end

  defp skip_comments(query), do: query

  defp first_word(query) do
    case :binary.match(query, [" ", "\t", "\n", "\r", "\f", "\v"]) do
      {index, _length} -> binary_part(query, 0, index)
      :nomatch -> query
    end
  end

  defp classify("SELECT"), do: :select
  defp classify("WITH"), do: :select
  defp classify("INSERT"), do: :insert
  defp classify("UPDATE"), do: :update
  defp classify("DELETE"), do: :delete

  defp classify(word) when word in ["BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "RELEASE"],
    do: :transaction

  defp classify(_word), do: :other

  defp application_frame?(
         {module, _function, _arity_or_args, _location},
         ignored_modules,
         namespaces
       )
       when is_atom(module) do
    module_name = Atom.to_string(module)

    module not in ignored_modules and
      Enum.any?(namespaces, fn {name, prefix} ->
        module_name == name or String.starts_with?(module_name, prefix)
      end)
  end

  defp application_frame?(_frame, _ignored_modules, _namespaces), do: false

  defp frame_signature({module, function, arity_or_args, location}) do
    {module, function, arity(arity_or_args), location[:file], location[:line]}
  end

  defp arity(arity) when is_integer(arity), do: arity
  defp arity(arguments) when is_list(arguments), do: length(arguments)

  defp namespace(module) do
    name = Atom.to_string(module)
    {name, name <> "."}
  end
end
