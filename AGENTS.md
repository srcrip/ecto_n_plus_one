# Project information

This is a simple, minimal elixir library for projects/apps that use Ecto (such as Phoenix) to detect N+1 queries in
production.

The basic idea is we expose a function that connects to the existing Ecto telemetry handlers, and then we process the
incoming queries. We write some data into the process dictionary, and then determine if the query we see after a couple
of repeats *might* be an N+1 query. We can't really know for sure, but it can be a strong signal.
