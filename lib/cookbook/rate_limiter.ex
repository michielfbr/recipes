defmodule Cookbook.RateLimiter do
  @moduledoc """
  Counts events per key in fixed time windows, to limit how often something
  may happen, such as failed log in attempts.

  Counts are kept in memory (ETS), so they are per node and reset when the
  app restarts. Expired windows are removed every minute.

      :ok = RateLimiter.check({:login_email, email}, 5, :timer.minutes(15))
      RateLimiter.hit({:login_email, email}, :timer.minutes(15))
  """

  use GenServer

  @table __MODULE__
  @cleanup_interval :timer.minutes(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns `:ok` when `key` was hit fewer than `limit` times in the current
  window of `window_ms` milliseconds, `{:error, :rate_limited}` otherwise.

  Does not count as a hit itself.
  """
  @spec check(term(), pos_integer(), pos_integer()) :: :ok | {:error, :rate_limited}
  def check(key, limit, window_ms) do
    case :ets.lookup(@table, window_key(key, window_ms)) do
      [{_key, count, _expires_at}] when count >= limit -> {:error, :rate_limited}
      _ -> :ok
    end
  end

  @doc """
  Counts a hit for `key` in the current window of `window_ms` milliseconds.
  """
  @spec hit(term(), pos_integer()) :: :ok
  def hit(key, window_ms) do
    {_key, window} = window_key = window_key(key, window_ms)
    expires_at = (window + 1) * window_ms
    :ets.update_counter(@table, window_key, 1, {window_key, 0, expires_at})
    :ok
  end

  defp window_key(key, window_ms) do
    {key, div(System.system_time(:millisecond), window_ms)}
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_cleanup()
    {:ok, nil}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
