defmodule TwqTest do
  @moduledoc """
  Host-side harness entrypoints for pthread_workqueue testing.

  This module stays intentionally small. The useful work lives in the
  supporting modules under `TwqTest.*`.
  """

  alias TwqTest.Env

  @spec env(map()) :: Env.t()
  def env(overrides \\ %{}) do
    Env.load(overrides)
  end
end
