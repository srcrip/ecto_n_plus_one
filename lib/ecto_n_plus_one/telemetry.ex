defmodule EctoNPlusOne.Telemetry do
  @moduledoc false

  require Logger

  alias EctoNPlusOne.Accumulator

  @storage_key {__MODULE__, :events}

  @spec attach([:telemetry.event_name()], keyword()) :: :ok
  def attach(events, options) do
    Enum.each(events, fn event ->
      :telemetry.detach(handler_id(event))
      :ok = :telemetry.attach(handler_id(event), event, &__MODULE__.handle_event/4, options)
    end)

    :ok
  end

  @spec detach([:telemetry.event_name()]) :: :ok
  def detach(events) do
    Enum.each(events, &:telemetry.detach(handler_id(&1)))
    :ok
  end

  @doc false
  @spec handle_event(:telemetry.event_name(), map(), map(), keyword()) :: :ok
  def handle_event(event, measurements, metadata, options) do
    now = System.monotonic_time(:millisecond)
    event_states = Process.get(@storage_key, %{})
    state = event_states |> Map.get(event, new_state(now)) |> maybe_prune(now, options)
    {groups, key} = Accumulator.capture(state.groups, measurements, metadata, options, now)
    {groups, detection} = Accumulator.new_detection(groups, key, options)
    updated_state = %{state | groups: groups}

    Process.put(@storage_key, Map.put(event_states, event, updated_state))
    report(detection, options)
    :ok
  rescue
    error ->
      log_failure(:error, error, __STACKTRACE__)
      :ok
  catch
    kind, reason ->
      log_failure(kind, reason, __STACKTRACE__)
      :ok
  end

  defp new_state(now), do: %{groups: %{}, last_pruned: now}

  defp maybe_prune(state, now, options) do
    if now - state.last_pruned >= options[:window_ms] do
      %{groups: Accumulator.prune(state.groups, now, options[:window_ms]), last_pruned: now}
    else
      state
    end
  end

  defp report(nil, _options), do: :ok
  defp report(detection, options), do: options[:on_detect].([detection])

  defp handler_id(event), do: {__MODULE__, event}

  defp log_failure(kind, reason, stacktrace) do
    formatted = Exception.format(kind, reason, stacktrace)

    Logger.error(fn ->
      "EctoNPlusOne Telemetry handler failed; the query was allowed to continue:\n" <> formatted
    end)
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end
end
