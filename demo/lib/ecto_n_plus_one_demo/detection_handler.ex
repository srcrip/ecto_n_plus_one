defmodule EctoNPlusOneDemo.DetectionHandler do
  @moduledoc """
  Example user-defined handler that delivers a detection to the current process.

  A real application could replace this with error reporting, structured logs,
  or a development notification. The library does not decide how to alert.
  """

  require Logger

  @message_tag {__MODULE__, :detected}

  def handle(detection) do
    log_detection(detection)
    send(self(), {@message_tag, detection})
    :ok
  end

  def take do
    receive do
      {@message_tag, detection} -> detection
    after
      0 -> nil
    end
  end

  defp log_detection(detection) do
    Logger.warning(fn ->
      "🚨 EctoNPlusOne demo detected N+1: #{detection.count}x #{detection.operation} " <>
        "with #{detection.parameter_variants} parameter variants " <>
        "source=#{inspect(detection.source)} query=#{inspect(detection.query)}"
    end)
  end
end
