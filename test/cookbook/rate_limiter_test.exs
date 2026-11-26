defmodule Cookbook.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Cookbook.RateLimiter

  @window :timer.minutes(15)

  test "allows hits up to the limit" do
    key = make_ref()

    for _ <- 1..3 do
      assert RateLimiter.check(key, 3, @window) == :ok
      RateLimiter.hit(key, @window)
    end

    assert RateLimiter.check(key, 3, @window) == {:error, :rate_limited}
  end

  test "counts keys separately" do
    limited = make_ref()
    RateLimiter.hit(limited, @window)

    assert RateLimiter.check(limited, 1, @window) == {:error, :rate_limited}
    assert RateLimiter.check(make_ref(), 1, @window) == :ok
  end

  test "removes expired windows on cleanup" do
    key = make_ref()
    hit_at = System.system_time(:millisecond)
    RateLimiter.hit(key, 1)
    # Wait for the 1 ms window to pass, so its entry has expired.
    wait_until(fn -> System.system_time(:millisecond) > hit_at + 1 end)

    send(RateLimiter, :cleanup)
    _ = :sys.get_state(RateLimiter)

    assert :ets.match_object(RateLimiter, {{key, :_}, :_, :_}) == []
  end

  defp wait_until(fun) do
    unless fun.(), do: wait_until(fun)
  end
end
