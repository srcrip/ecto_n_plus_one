defmodule EctoNPlusOne.Accumulator do
  @moduledoc false

  alias EctoNPlusOne.Detection

  @spec capture(map(), map(), map(), keyword(), integer()) :: {map(), term() | nil}
  def capture(groups, measurements, metadata, options, now) do
    if capturable?(metadata, options) do
      query = Detection.normalize_query(metadata.query)
      operation = Detection.operation(query)

      case application_stacktrace(metadata, options) do
        {:ok, stacktrace} ->
          callsite = List.first(stacktrace)
          candidate = candidate(metadata, query, operation, callsite, stacktrace)

          if options[:ignore].(candidate) do
            {groups, nil}
          else
            stacktrace_signature = Detection.stacktrace_signature(stacktrace)
            key = {metadata[:repo], metadata[:source], operation, query, stacktrace_signature}

            updated_groups =
              put_query(
                groups,
                key,
                query,
                operation,
                callsite,
                stacktrace,
                measurements,
                metadata,
                options,
                now
              )

            {updated_groups, key}
          end

        :ignore ->
          {groups, nil}
      end
    else
      {groups, nil}
    end
  end

  @spec new_detection(map(), term(), keyword()) :: {map(), Detection.t() | nil}
  def new_detection(groups, key, options) do
    case Map.fetch(groups, key) do
      {:ok, %{reported?: false} = group} ->
        if detection?(group, options) do
          {Map.update!(groups, key, &Map.put(&1, :reported?, true)), to_detection(group)}
        else
          {groups, nil}
        end

      _other ->
        {groups, nil}
    end
  end

  @spec prune(map(), integer(), non_neg_integer()) :: map()
  def prune(groups, now, window_ms) do
    Map.reject(groups, fn {_key, group} -> now - group.last_seen > window_ms end)
  end

  defp capturable?(%{query: query}, options) when is_binary(query) do
    operation_allowed?(Detection.operation(query), options[:operations])
  end

  defp capturable?(_metadata, _options), do: false

  defp put_query(
         groups,
         key,
         query,
         operation,
         callsite,
         stacktrace,
         measurements,
         metadata,
         options,
         now
       ) do
    case Map.fetch(groups, key) do
      {:ok, group} ->
        if now - group.last_seen > options[:window_ms] do
          Map.put(
            groups,
            key,
            new_group(
              query,
              operation,
              callsite,
              stacktrace,
              measurements,
              metadata,
              options,
              now
            )
          )
        else
          Map.put(groups, key, update_group(group, measurements, metadata, options, now))
        end

      :error ->
        if map_size(groups) < options[:max_queries] do
          Map.put(
            groups,
            key,
            new_group(
              query,
              operation,
              callsite,
              stacktrace,
              measurements,
              metadata,
              options,
              now
            )
          )
        else
          groups
        end
    end
  end

  defp operation_allowed?(_operation, :all), do: true
  defp operation_allowed?(operation, operations), do: operation in operations

  defp candidate(metadata, query, operation, callsite, stacktrace) do
    %{
      callsite: callsite,
      metadata: metadata,
      operation: operation,
      query: query,
      repo: metadata[:repo],
      source: metadata[:source],
      stacktrace: stacktrace
    }
  end

  defp new_group(query, operation, callsite, stacktrace, measurements, metadata, options, now) do
    %{
      callsite: callsite,
      count: 1,
      parameter_signatures: MapSet.new([parameter_signature(metadata)]),
      params: params(metadata, options),
      query: query,
      repo: metadata[:repo],
      source: metadata[:source],
      operation: operation,
      total_time: measurements[:total_time] || 0,
      stacktrace: stacktrace,
      last_seen: now,
      reported?: false
    }
  end

  defp update_group(group, measurements, metadata, options, now) do
    %{
      group
      | count: group.count + 1,
        parameter_signatures:
          MapSet.put(group.parameter_signatures, parameter_signature(metadata)),
        params: add_params(group.params, metadata, options),
        total_time: group.total_time + (measurements[:total_time] || 0),
        last_seen: now
    }
  end

  defp detection?(group, options) do
    group.count >= options[:threshold] and
      MapSet.size(group.parameter_signatures) >= options[:min_parameter_variants]
  end

  defp to_detection(group) do
    struct!(Detection,
      callsite: group.callsite,
      count: group.count,
      parameter_variants: MapSet.size(group.parameter_signatures),
      params: group.params,
      query: group.query,
      repo: group.repo,
      source: group.source,
      operation: group.operation,
      total_time: group.total_time,
      stacktrace: group.stacktrace
    )
  end

  defp application_stacktrace(metadata, options) do
    stacktrace =
      Detection.application_stacktrace(
        metadata[:stacktrace],
        [metadata[:repo]],
        options[:application_modules]
      )

    case stacktrace do
      [] -> :ignore
      stacktrace -> {:ok, stacktrace}
    end
  end

  defp parameter_signature(metadata) do
    metadata
    |> Map.get(:params, :ecto_n_plus_one_missing_params)
    |> :erlang.phash2(4_294_967_296)
  end

  defp params(metadata, options) do
    if options[:include_params] and options[:max_samples] > 0, do: [metadata[:params]], else: []
  end

  defp add_params(samples, metadata, options) do
    if options[:include_params] and length(samples) < options[:max_samples] do
      samples ++ [metadata[:params]]
    else
      samples
    end
  end
end
