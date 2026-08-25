defmodule EctoNPlusOne.DetectionTest do
  use ExUnit.Case, async: true

  alias EctoNPlusOne.Detection

  test "classifies common SQL operations case-insensitively" do
    assert Detection.operation("select * from users") == :select
    assert Detection.operation("INSERT INTO users VALUES ($1)") == :insert
    assert Detection.operation(" update users set active = true") == :update
    assert Detection.operation("DELETE FROM users") == :delete
    assert Detection.operation("ROLLBACK") == :transaction
    assert Detection.operation("VACUUM users") == :other
  end

  test "treats CTEs as selects and skips leading comments" do
    assert Detection.operation("WITH users AS (SELECT 1) SELECT * FROM users") == :select
    assert Detection.operation("-- generated\nSELECT * FROM users") == :select
    assert Detection.operation("/* generated */ SELECT * FROM users") == :select
  end

  test "finds the first application callsite" do
    application_frame = {MyApp.Accounts, :load_profile, 1, [file: ~c"lib/accounts.ex", line: 42]}

    stacktrace = [
      {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 1]},
      {EctoNPlusOne.Telemetry, :handle_event, 4, [file: ~c"lib/telemetry.ex", line: 1]},
      application_frame
    ]

    assert Detection.callsite(stacktrace, [], [MyApp]) == application_frame
    assert Detection.callsite([application_frame], [MyApp.Accounts], [MyApp]) == nil
    assert Detection.callsite(nil, [], [MyApp]) == nil
  end

  test "finds the first callsite inside an allowed module namespace" do
    dependency_frame = {Oban.Repo, :dynamic_dispatch, 4, [file: ~c"lib/oban/repo.ex", line: 296]}

    application_frame =
      {MyApp.Catalog.Loader, :load, 1, [file: ~c"lib/catalog/loader.ex", line: 12]}

    assert Detection.callsite([dependency_frame, application_frame], [], [MyApp]) ==
             application_frame

    assert Detection.callsite([dependency_frame], [], [MyApp, MyAppWeb]) == nil
  end

  test "retains and canonicalizes the complete application stacktrace" do
    query_frame =
      {MyApp.Accounts, :load_profile, [123], [file: ~c"lib/accounts.ex", line: 42]}

    caller_frame =
      {MyAppWeb.ProfileComponent, :update, 2, [file: ~c"lib/profile_component.ex", line: 18]}

    dependency_frame = {Phoenix.LiveView, :call_update, 3, [file: ~c"lib/live_view.ex", line: 1]}

    assert Detection.application_stacktrace(
             [query_frame, caller_frame, dependency_frame],
             [],
             [MyApp, MyAppWeb]
           ) == [query_frame, caller_frame]

    assert Detection.stacktrace_signature([query_frame, caller_frame]) == [
             {MyApp.Accounts, :load_profile, 1, ~c"lib/accounts.ex", 42},
             {MyAppWeb.ProfileComponent, :update, 2, ~c"lib/profile_component.ex", 18}
           ]

    assert Detection.stacktrace_signature([query_frame, query_frame, caller_frame]) == [
             {MyApp.Accounts, :load_profile, 1, ~c"lib/accounts.ex", 42},
             {MyAppWeb.ProfileComponent, :update, 2, ~c"lib/profile_component.ex", 18}
           ]
  end
end
