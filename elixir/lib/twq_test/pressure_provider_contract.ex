defmodule TwqTest.PressureProviderContract do
  @moduledoc """
  Elixir-side validation for the repo-owned M15 pressure-provider contract.

  This module checks that the derived, live, adapter, session, observer,
  tracker, bundle, and preview pressure-only artifacts remain self-describing
  and structurally consistent with the checked-in contract, without claiming
  that the repo already exposes a real provider SPI.
  """

  alias TwqTest.JSON

  @type validation :: %{
          ok?: boolean(),
          failures: [String.t()],
          checks: [map()]
        }

  @spec load(String.t()) :: map()
  def load(path) when is_binary(path) do
    path
    |> File.read!()
    |> JSON.decode!()
    |> normalize_nulls()
  end

  @spec validate(
          String.t() | map(),
          String.t() | map(),
          :derived | :live | :adapter | :session | :observer | :tracker | :bundle | :preview
        ) ::
          validation()
  def validate(contract_path_or_map, artifact_path_or_map, kind)
      when kind in [:derived, :live, :adapter, :session, :observer, :tracker, :bundle, :preview] do
    contract =
      if is_binary(contract_path_or_map),
        do: load(contract_path_or_map),
        else: normalize_nulls(contract_path_or_map)

    artifact =
      if is_binary(artifact_path_or_map),
        do: load(artifact_path_or_map),
        else: normalize_nulls(artifact_path_or_map)

    {checks, failures} =
      {[], []}
      |> compare_top_level(contract, artifact, kind)
      |> validate_shape(contract, artifact, kind)

    failures = Enum.reverse(failures)

    %{
      ok?: failures == [],
      failures: failures,
      checks: checks
    }
  end

  @spec assert_ok!(validation()) :: validation()
  def assert_ok!(%{ok?: true} = validation), do: validation

  def assert_ok!(%{failures: failures}) do
    raise "pressure-provider contract validation failed:\n" <> Enum.join(failures, "\n")
  end

  defp compare_top_level({checks, failures}, contract, artifact, kind) do
    expected_contract = %{
      "name" => contract["name"],
      "version" => contract["version"],
      "current_signal_field" => contract["current_signal_field"],
      "current_signal_kind" => contract["current_signal_kind"],
      "quiescence_kind" => contract["quiescence_kind"],
      "per_bucket_scope" => contract["per_bucket_scope"],
      "diagnostic_fields" => contract["diagnostic_fields"]
    }

    {checks, failures} =
      compare_exact(
        {checks, failures},
        "provider_scope",
        contract["provider_scope"],
        artifact["provider_scope"]
      )

    {checks, failures} =
      compare_exact(
        {checks, failures},
        "contract",
        expected_contract,
        artifact["contract"]
      )

    case kind do
      :derived ->
        {checks, failures}
        |> compare_exact(
          "metadata.generation_kind",
          get_in(contract, ["derived", "generation_kind"]),
          get_in(artifact, ["metadata", "generation_kind"])
        )
        |> compare_exact(
          "metadata.monotonic_time_kind",
          get_in(contract, ["derived", "monotonic_time_kind"]),
          get_in(artifact, ["metadata", "monotonic_time_kind"])
        )

      :live ->
        {checks, failures}
        |> compare_exact(
          "capture_kind",
          get_in(contract, ["live", "capture_kind"]),
          artifact["capture_kind"]
        )
        |> compare_exact(
          "metadata.generation_kind",
          get_in(contract, ["live", "generation_kind"]),
          get_in(artifact, ["metadata", "generation_kind"])
        )
        |> compare_exact(
          "metadata.monotonic_time_kind",
          get_in(contract, ["live", "monotonic_time_kind"]),
          get_in(artifact, ["metadata", "monotonic_time_kind"])
        )

      :preview ->
        {checks, failures}
        |> compare_exact(
          "preview_kind",
          get_in(contract, ["preview", "preview_kind"]),
          artifact["preview_kind"]
        )
        |> compare_exact(
          "metadata.generation_kind",
          get_in(contract, ["preview", "generation_kind"]),
          get_in(artifact, ["metadata", "generation_kind"])
        )
        |> compare_exact(
          "metadata.monotonic_time_kind",
          get_in(contract, ["preview", "monotonic_time_kind"]),
          get_in(artifact, ["metadata", "monotonic_time_kind"])
        )

      :session ->
        {checks, failures}
        |> compare_exact(
          "session_kind",
          get_in(contract, ["session", "session_kind"]),
          artifact["session_kind"]
        )
        |> compare_exact(
          "view_kind",
          get_in(contract, ["session", "view_kind"]),
          artifact["view_kind"]
        )
        |> compare_exact(
          "metadata.generation_kind",
          get_in(contract, ["session", "generation_kind"]),
          get_in(artifact, ["metadata", "generation_kind"])
        )
        |> compare_exact(
          "metadata.monotonic_time_kind",
          get_in(contract, ["session", "monotonic_time_kind"]),
          get_in(artifact, ["metadata", "monotonic_time_kind"])
        )

      :observer ->
        {checks, failures}
        |> compare_exact(
          "observer_kind",
          get_in(contract, ["observer", "observer_kind"]),
          artifact["observer_kind"]
        )
        |> compare_exact(
          "source_session_kind",
          get_in(contract, ["observer", "source_session_kind"]),
          artifact["source_session_kind"]
        )
        |> compare_exact(
          "source_view_kind",
          get_in(contract, ["observer", "source_view_kind"]),
          artifact["source_view_kind"]
        )
        |> compare_exact(
          "metadata.generation_kind",
          get_in(contract, ["observer", "generation_kind"]),
          get_in(artifact, ["metadata", "generation_kind"])
        )
        |> compare_exact(
          "metadata.monotonic_time_kind",
          get_in(contract, ["observer", "monotonic_time_kind"]),
          get_in(artifact, ["metadata", "monotonic_time_kind"])
        )

      :tracker ->
        {checks, failures}
        |> compare_exact(
          "tracker_kind",
          get_in(contract, ["tracker", "tracker_kind"]),
          artifact["tracker_kind"]
        )
        |> compare_exact(
          "source_session_kind",
          get_in(contract, ["tracker", "source_session_kind"]),
          artifact["source_session_kind"]
        )
        |> compare_exact(
          "source_view_kind",
          get_in(contract, ["tracker", "source_view_kind"]),
          artifact["source_view_kind"]
        )
        |> compare_exact(
          "metadata.generation_kind",
          get_in(contract, ["tracker", "generation_kind"]),
          get_in(artifact, ["metadata", "generation_kind"])
        )
        |> compare_exact(
          "metadata.monotonic_time_kind",
          get_in(contract, ["tracker", "monotonic_time_kind"]),
          get_in(artifact, ["metadata", "monotonic_time_kind"])
        )

      :bundle ->
        {checks, failures}
        |> compare_exact(
          "bundle_kind",
          get_in(contract, ["bundle", "bundle_kind"]),
          artifact["bundle_kind"]
        )
        |> compare_exact(
          "source_session_kind",
          get_in(contract, ["bundle", "source_session_kind"]),
          artifact["source_session_kind"]
        )
        |> compare_exact(
          "source_view_kind",
          get_in(contract, ["bundle", "source_view_kind"]),
          artifact["source_view_kind"]
        )
        |> compare_exact(
          "source_observer_kind",
          get_in(contract, ["bundle", "source_observer_kind"]),
          artifact["source_observer_kind"]
        )
        |> compare_exact(
          "source_tracker_kind",
          get_in(contract, ["bundle", "source_tracker_kind"]),
          artifact["source_tracker_kind"]
        )
        |> compare_exact(
          "metadata.generation_kind",
          get_in(contract, ["bundle", "generation_kind"]),
          get_in(artifact, ["metadata", "generation_kind"])
        )
        |> compare_exact(
          "metadata.monotonic_time_kind",
          get_in(contract, ["bundle", "monotonic_time_kind"]),
          get_in(artifact, ["metadata", "monotonic_time_kind"])
        )

      :adapter ->
        {checks, failures}
        |> compare_exact(
          "adapter_kind",
          get_in(contract, ["adapter", "adapter_kind"]),
          artifact["adapter_kind"]
        )
        |> compare_exact(
          "metadata.generation_kind",
          get_in(contract, ["adapter", "generation_kind"]),
          get_in(artifact, ["metadata", "generation_kind"])
        )
        |> compare_exact(
          "metadata.monotonic_time_kind",
          get_in(contract, ["adapter", "monotonic_time_kind"]),
          get_in(artifact, ["metadata", "monotonic_time_kind"])
        )
    end
  end

  defp validate_shape({checks, failures}, contract, artifact, :derived) do
    snapshots = artifact["snapshots"]

    if is_map(snapshots) and map_size(snapshots) > 0 do
      Enum.reduce(Enum.sort_by(snapshots, &elem(&1, 0)), {checks, failures}, fn {label, snapshot},
                                                                                acc ->
        validate_snapshot_shape(acc, contract, "snapshots.#{label}", snapshot)
      end)
    else
      failure = "derived artifact is missing snapshots"
      check = %{kind: "shape", field: "snapshots", status: "fail", failure: failure}
      {[check | checks], [failure | failures]}
    end
  end

  defp validate_shape({checks, failures}, contract, artifact, :live) do
    captures = artifact["captures"]

    required_capture_fields =
      MapSet.new(get_in(contract, ["live", "required_capture_fields"]) || [])

    if is_map(captures) and map_size(captures) > 0 do
      Enum.reduce(Enum.sort_by(captures, &elem(&1, 0)), {checks, failures}, fn {label, capture},
                                                                               acc ->
        acc =
          Enum.reduce(Enum.sort(required_capture_fields), acc, fn field, {checks, failures} ->
            if Map.has_key?(capture, field) do
              check = %{
                kind: "shape",
                field: "captures.#{label}.#{field}",
                status: "ok",
                failure: nil
              }

              {[check | checks], failures}
            else
              failure = "captures.#{label}: field #{field} missing"

              check = %{
                kind: "shape",
                field: "captures.#{label}.#{field}",
                status: "fail",
                failure: failure
              }

              {[check | checks], [failure | failures]}
            end
          end)

        snapshots = capture["snapshots"]

        if is_list(snapshots) and snapshots != [] do
          Enum.with_index(snapshots)
          |> Enum.reduce(acc, fn {snapshot, index}, acc ->
            validate_snapshot_shape(
              acc,
              contract,
              "captures.#{label}.snapshots[#{index}]",
              snapshot
            )
          end)
        else
          {checks, failures} = acc
          failure = "captures.#{label}: snapshots missing or empty"

          check = %{
            kind: "shape",
            field: "captures.#{label}.snapshots",
            status: "fail",
            failure: failure
          }

          {[check | checks], [failure | failures]}
        end
      end)
    else
      failure = "live artifact is missing captures"
      check = %{kind: "shape", field: "captures", status: "fail", failure: failure}
      {[check | checks], [failure | failures]}
    end
  end

  defp validate_shape({checks, failures}, contract, artifact, :preview) do
    captures = artifact["captures"]

    required_capture_fields =
      MapSet.new(get_in(contract, ["preview", "required_capture_fields"]) || [])

    required_sample_fields =
      MapSet.new(get_in(contract, ["preview", "required_sample_fields"]) || [])

    required_snapshot_fields =
      MapSet.new(get_in(contract, ["preview", "required_snapshot_fields"]) || [])

    if is_map(captures) and map_size(captures) > 0 do
      Enum.reduce(Enum.sort_by(captures, &elem(&1, 0)), {checks, failures}, fn {label, capture},
                                                                               acc ->
        acc =
          Enum.reduce(Enum.sort(required_capture_fields), acc, fn field, {checks, failures} ->
            if Map.has_key?(capture, field) do
              check = %{
                kind: "shape",
                field: "captures.#{label}.#{field}",
                status: "ok",
                failure: nil
              }

              {[check | checks], failures}
            else
              failure = "captures.#{label}: field #{field} missing"

              check = %{
                kind: "shape",
                field: "captures.#{label}.#{field}",
                status: "fail",
                failure: failure
              }

              {[check | checks], [failure | failures]}
            end
          end)

        snapshots = capture["snapshots"]

        if is_list(snapshots) and snapshots != [] do
          Enum.with_index(snapshots)
          |> Enum.reduce(acc, fn {snapshot, index}, acc ->
            acc =
              Enum.reduce(Enum.sort(required_sample_fields), acc, fn field, {checks, failures} ->
                if Map.has_key?(snapshot, field) do
                  check = %{
                    kind: "shape",
                    field: "captures.#{label}.snapshots[#{index}].#{field}",
                    status: "ok",
                    failure: nil
                  }

                  {[check | checks], failures}
                else
                  failure = "captures.#{label}.snapshots[#{index}]: field #{field} missing"

                  check = %{
                    kind: "shape",
                    field: "captures.#{label}.snapshots[#{index}].#{field}",
                    status: "fail",
                    failure: failure
                  }

                  {[check | checks], [failure | failures]}
                end
              end)

            raw_snapshot = snapshot["snapshot"]

            if is_map(raw_snapshot) do
              Enum.reduce(Enum.sort(required_snapshot_fields), acc, fn field,
                                                                       {checks, failures} ->
                if Map.has_key?(raw_snapshot, field) do
                  check = %{
                    kind: "shape",
                    field: "captures.#{label}.snapshots[#{index}].snapshot.#{field}",
                    status: "ok",
                    failure: nil
                  }

                  {[check | checks], failures}
                else
                  failure =
                    "captures.#{label}.snapshots[#{index}]: raw field #{field} missing"

                  check = %{
                    kind: "shape",
                    field: "captures.#{label}.snapshots[#{index}].snapshot.#{field}",
                    status: "fail",
                    failure: failure
                  }

                  {[check | checks], [failure | failures]}
                end
              end)
            else
              {checks, failures} = acc
              failure = "captures.#{label}.snapshots[#{index}]: snapshot missing or not an object"

              check = %{
                kind: "shape",
                field: "captures.#{label}.snapshots[#{index}].snapshot",
                status: "fail",
                failure: failure
              }

              {[check | checks], [failure | failures]}
            end
          end)
        else
          {checks, failures} = acc
          failure = "captures.#{label}: snapshots missing or empty"

          check = %{
            kind: "shape",
            field: "captures.#{label}.snapshots",
            status: "fail",
            failure: failure
          }

          {[check | checks], [failure | failures]}
        end
      end)
    else
      failure = "preview artifact is missing captures"
      check = %{kind: "shape", field: "captures", status: "fail", failure: failure}
      {[check | checks], [failure | failures]}
    end
  end

  defp validate_shape({checks, failures}, contract, artifact, :adapter) do
    captures = artifact["captures"]

    required_capture_fields =
      MapSet.new(get_in(contract, ["adapter", "required_capture_fields"]) || [])

    required_sample_fields =
      MapSet.new(get_in(contract, ["adapter", "required_sample_fields"]) || [])

    required_view_fields =
      MapSet.new(get_in(contract, ["adapter", "required_view_fields"]) || [])

    if is_map(captures) and map_size(captures) > 0 do
      Enum.reduce(Enum.sort_by(captures, &elem(&1, 0)), {checks, failures}, fn {label, capture},
                                                                               acc ->
        acc =
          Enum.reduce(Enum.sort(required_capture_fields), acc, fn field, {checks, failures} ->
            if Map.has_key?(capture, field) do
              check = %{
                kind: "shape",
                field: "captures.#{label}.#{field}",
                status: "ok",
                failure: nil
              }

              {[check | checks], failures}
            else
              failure = "captures.#{label}: field #{field} missing"

              check = %{
                kind: "shape",
                field: "captures.#{label}.#{field}",
                status: "fail",
                failure: failure
              }

              {[check | checks], [failure | failures]}
            end
          end)

        snapshots = capture["snapshots"]

        if is_list(snapshots) and snapshots != [] do
          Enum.with_index(snapshots)
          |> Enum.reduce(acc, fn {snapshot, index}, acc ->
            acc =
              Enum.reduce(Enum.sort(required_sample_fields), acc, fn field, {checks, failures} ->
                if Map.has_key?(snapshot, field) do
                  check = %{
                    kind: "shape",
                    field: "captures.#{label}.snapshots[#{index}].#{field}",
                    status: "ok",
                    failure: nil
                  }

                  {[check | checks], failures}
                else
                  failure = "captures.#{label}.snapshots[#{index}]: field #{field} missing"

                  check = %{
                    kind: "shape",
                    field: "captures.#{label}.snapshots[#{index}].#{field}",
                    status: "fail",
                    failure: failure
                  }

                  {[check | checks], [failure | failures]}
                end
              end)

            view = snapshot["view"]

            if is_map(view) do
              acc =
                Enum.reduce(Enum.sort(required_view_fields), acc, fn field, {checks, failures} ->
                  if Map.has_key?(view, field) do
                    check = %{
                      kind: "shape",
                      field: "captures.#{label}.snapshots[#{index}].view.#{field}",
                      status: "ok",
                      failure: nil
                    }

                    {[check | checks], failures}
                  else
                    failure =
                      "captures.#{label}.snapshots[#{index}]: view field #{field} missing"

                    check = %{
                      kind: "shape",
                      field: "captures.#{label}.snapshots[#{index}].view.#{field}",
                      status: "fail",
                      failure: failure
                    }

                    {[check | checks], [failure | failures]}
                  end
                end)

              validate_snapshot_shape(
                acc,
                contract,
                "captures.#{label}.snapshots[#{index}]",
                snapshot
              )
            else
              {checks, failures} = acc
              failure = "captures.#{label}.snapshots[#{index}]: view missing or not an object"

              check = %{
                kind: "shape",
                field: "captures.#{label}.snapshots[#{index}].view",
                status: "fail",
                failure: failure
              }

              {[check | checks], [failure | failures]}
            end
          end)
        else
          {checks, failures} = acc
          failure = "captures.#{label}: snapshots missing or empty"

          check = %{
            kind: "shape",
            field: "captures.#{label}.snapshots",
            status: "fail",
            failure: failure
          }

          {[check | checks], [failure | failures]}
        end
      end)
    else
      failure = "adapter artifact is missing captures"
      check = %{kind: "shape", field: "captures", status: "fail", failure: failure}
      {[check | checks], [failure | failures]}
    end
  end

  defp validate_shape({checks, failures}, contract, artifact, :session) do
    captures = artifact["captures"]

    required_capture_fields =
      MapSet.new(get_in(contract, ["session", "required_capture_fields"]) || [])

    required_sample_fields =
      MapSet.new(get_in(contract, ["session", "required_sample_fields"]) || [])

    required_session_fields =
      MapSet.new(get_in(contract, ["session", "required_session_fields"]) || [])

    required_view_fields =
      MapSet.new(get_in(contract, ["session", "required_view_fields"]) || [])

    if is_map(captures) and map_size(captures) > 0 do
      Enum.reduce(Enum.sort_by(captures, &elem(&1, 0)), {checks, failures}, fn {label, capture},
                                                                               acc ->
        acc =
          Enum.reduce(Enum.sort(required_capture_fields), acc, fn field, {checks, failures} ->
            if Map.has_key?(capture, field) do
              check = %{
                kind: "shape",
                field: "captures.#{label}.#{field}",
                status: "ok",
                failure: nil
              }

              {[check | checks], failures}
            else
              failure = "captures.#{label}: field #{field} missing"

              check = %{
                kind: "shape",
                field: "captures.#{label}.#{field}",
                status: "fail",
                failure: failure
              }

              {[check | checks], [failure | failures]}
            end
          end)

        snapshots = capture["snapshots"]

        if is_list(snapshots) and snapshots != [] do
          Enum.with_index(snapshots)
          |> Enum.reduce(acc, fn {snapshot, index}, acc ->
            acc =
              Enum.reduce(Enum.sort(required_sample_fields), acc, fn field, {checks, failures} ->
                if Map.has_key?(snapshot, field) do
                  check = %{
                    kind: "shape",
                    field: "captures.#{label}.snapshots[#{index}].#{field}",
                    status: "ok",
                    failure: nil
                  }

                  {[check | checks], failures}
                else
                  failure = "captures.#{label}.snapshots[#{index}]: field #{field} missing"

                  check = %{
                    kind: "shape",
                    field: "captures.#{label}.snapshots[#{index}].#{field}",
                    status: "fail",
                    failure: failure
                  }

                  {[check | checks], [failure | failures]}
                end
              end)

            session = snapshot["session"]

            acc =
              if is_map(session) do
                Enum.reduce(Enum.sort(required_session_fields), acc, fn field,
                                                                        {checks, failures} ->
                  if Map.has_key?(session, field) do
                    check = %{
                      kind: "shape",
                      field: "captures.#{label}.snapshots[#{index}].session.#{field}",
                      status: "ok",
                      failure: nil
                    }

                    {[check | checks], failures}
                  else
                    failure =
                      "captures.#{label}.snapshots[#{index}]: session field #{field} missing"

                    check = %{
                      kind: "shape",
                      field: "captures.#{label}.snapshots[#{index}].session.#{field}",
                      status: "fail",
                      failure: failure
                    }

                    {[check | checks], [failure | failures]}
                  end
                end)
              else
                {checks, failures} = acc

                failure =
                  "captures.#{label}.snapshots[#{index}]: session missing or not an object"

                check = %{
                  kind: "shape",
                  field: "captures.#{label}.snapshots[#{index}].session",
                  status: "fail",
                  failure: failure
                }

                {[check | checks], [failure | failures]}
              end

            view = snapshot["view"]

            if is_map(view) do
              acc =
                Enum.reduce(Enum.sort(required_view_fields), acc, fn field, {checks, failures} ->
                  if Map.has_key?(view, field) do
                    check = %{
                      kind: "shape",
                      field: "captures.#{label}.snapshots[#{index}].view.#{field}",
                      status: "ok",
                      failure: nil
                    }

                    {[check | checks], failures}
                  else
                    failure =
                      "captures.#{label}.snapshots[#{index}]: view field #{field} missing"

                    check = %{
                      kind: "shape",
                      field: "captures.#{label}.snapshots[#{index}].view.#{field}",
                      status: "fail",
                      failure: failure
                    }

                    {[check | checks], [failure | failures]}
                  end
                end)

              validate_snapshot_shape(
                acc,
                contract,
                "captures.#{label}.snapshots[#{index}].view",
                view
              )
            else
              {checks, failures} = acc
              failure = "captures.#{label}.snapshots[#{index}]: view missing or not an object"

              check = %{
                kind: "shape",
                field: "captures.#{label}.snapshots[#{index}].view",
                status: "fail",
                failure: failure
              }

              {[check | checks], [failure | failures]}
            end
          end)
        else
          {checks, failures} = acc
          failure = "captures.#{label}: snapshots missing or empty"

          check = %{
            kind: "shape",
            field: "captures.#{label}.snapshots",
            status: "fail",
            failure: failure
          }

          {[check | checks], [failure | failures]}
        end
      end)
    else
      failure = "session artifact is missing captures"
      check = %{kind: "shape", field: "captures", status: "fail", failure: failure}
      {[check | checks], [failure | failures]}
    end
  end

  defp validate_shape({checks, failures}, contract, artifact, :observer) do
    captures = artifact["captures"]

    required_capture_fields =
      MapSet.new(get_in(contract, ["observer", "required_capture_fields"]) || [])

    if is_map(captures) and map_size(captures) > 0 do
      Enum.reduce(Enum.sort_by(captures, &elem(&1, 0)), {checks, failures}, fn {label, capture},
                                                                               acc ->
        Enum.reduce(Enum.sort(required_capture_fields), acc, fn field, {checks, failures} ->
          if Map.has_key?(capture, field) do
            check = %{
              kind: "shape",
              field: "captures.#{label}.#{field}",
              status: "ok",
              failure: nil
            }

            {[check | checks], failures}
          else
            failure = "captures.#{label}: field #{field} missing"

            check = %{
              kind: "shape",
              field: "captures.#{label}.#{field}",
              status: "fail",
              failure: failure
            }

            {[check | checks], [failure | failures]}
          end
        end)
      end)
    else
      failure = "observer artifact is missing captures"
      check = %{kind: "shape", field: "captures", status: "fail", failure: failure}
      {[check | checks], [failure | failures]}
    end
  end

  defp validate_shape({checks, failures}, contract, artifact, :tracker) do
    captures = artifact["captures"]

    required_capture_fields =
      MapSet.new(get_in(contract, ["tracker", "required_capture_fields"]) || [])

    if is_map(captures) and map_size(captures) > 0 do
      Enum.reduce(Enum.sort_by(captures, &elem(&1, 0)), {checks, failures}, fn {label, capture},
                                                                               acc ->
        Enum.reduce(Enum.sort(required_capture_fields), acc, fn field, {checks, failures} ->
          if Map.has_key?(capture, field) do
            check = %{
              kind: "shape",
              field: "captures.#{label}.#{field}",
              status: "ok",
              failure: nil
            }

            {[check | checks], failures}
          else
            failure = "captures.#{label}: field #{field} missing"

            check = %{
              kind: "shape",
              field: "captures.#{label}.#{field}",
              status: "fail",
              failure: failure
            }

            {[check | checks], [failure | failures]}
          end
        end)
      end)
    else
      failure = "tracker artifact is missing captures"
      check = %{kind: "shape", field: "captures", status: "fail", failure: failure}
      {[check | checks], [failure | failures]}
    end
  end

  defp validate_shape({checks, failures}, contract, artifact, :bundle) do
    captures = artifact["captures"]

    required_capture_fields =
      MapSet.new(get_in(contract, ["bundle", "required_capture_fields"]) || [])

    if is_map(captures) and map_size(captures) > 0 do
      Enum.reduce(Enum.sort_by(captures, &elem(&1, 0)), {checks, failures}, fn {label, capture},
                                                                               acc ->
        Enum.reduce(Enum.sort(required_capture_fields), acc, fn field, {checks, failures} ->
          if Map.has_key?(capture, field) do
            check = %{
              kind: "shape",
              field: "captures.#{label}.#{field}",
              status: "ok",
              failure: nil
            }

            {[check | checks], failures}
          else
            failure = "captures.#{label}: field #{field} missing"

            check = %{
              kind: "shape",
              field: "captures.#{label}.#{field}",
              status: "fail",
              failure: failure
            }

            {[check | checks], [failure | failures]}
          end
        end)
      end)
    else
      failure = "bundle artifact is missing captures"
      check = %{kind: "shape", field: "captures", status: "fail", failure: failure}
      {[check | checks], [failure | failures]}
    end
  end

  defp validate_snapshot_shape({checks, failures}, contract, prefix, snapshot) do
    aggregate = snapshot["aggregate"] || %{}
    flags = snapshot["flags"] || %{}
    per_bucket = get_in(snapshot, ["diagnostics", "per_bucket"]) || %{}

    {checks, failures} =
      Enum.reduce(contract["required_aggregate_fields"] || [], {checks, failures}, fn field,
                                                                                      {checks,
                                                                                       failures} ->
        if Map.has_key?(aggregate, field) do
          check = %{
            kind: "shape",
            field: "#{prefix}.aggregate.#{field}",
            status: "ok",
            failure: nil
          }

          {[check | checks], failures}
        else
          failure = "#{prefix}: aggregate field #{field} missing"

          check = %{
            kind: "shape",
            field: "#{prefix}.aggregate.#{field}",
            status: "fail",
            failure: failure
          }

          {[check | checks], [failure | failures]}
        end
      end)

    {checks, failures} =
      Enum.reduce(contract["required_flag_fields"] || [], {checks, failures}, fn field,
                                                                                 {checks,
                                                                                  failures} ->
        if Map.has_key?(flags, field) do
          check = %{kind: "shape", field: "#{prefix}.flags.#{field}", status: "ok", failure: nil}
          {[check | checks], failures}
        else
          failure = "#{prefix}: flag field #{field} missing"

          check = %{
            kind: "shape",
            field: "#{prefix}.flags.#{field}",
            status: "fail",
            failure: failure
          }

          {[check | checks], [failure | failures]}
        end
      end)

    if flags["has_per_bucket_diagnostics"] == true do
      Enum.reduce(
        contract["per_bucket_fields_by_flag"] || %{},
        {checks, failures},
        fn {gating_flag, fields}, acc ->
          if flags[gating_flag] == true do
            Enum.reduce(fields, acc, fn field, {checks, failures} ->
              if Map.has_key?(per_bucket, field) do
                check = %{
                  kind: "shape",
                  field: "#{prefix}.diagnostics.per_bucket.#{field}",
                  status: "ok",
                  failure: nil
                }

                {[check | checks], failures}
              else
                failure = "#{prefix}: per-bucket field #{field} missing"

                check = %{
                  kind: "shape",
                  field: "#{prefix}.diagnostics.per_bucket.#{field}",
                  status: "fail",
                  failure: failure
                }

                {[check | checks], [failure | failures]}
              end
            end)
          else
            acc
          end
        end
      )
    else
      {checks, failures}
    end
  end

  defp compare_exact({checks, failures}, field, expected, actual) do
    if expected == actual do
      check = %{
        kind: "exact",
        field: field,
        expected: expected,
        actual: actual,
        status: "ok",
        failure: nil
      }

      {[check | checks], failures}
    else
      failure = "#{field} differs (expected #{inspect(expected)}, actual #{inspect(actual)})"

      check = %{
        kind: "exact",
        field: field,
        expected: expected,
        actual: actual,
        status: "fail",
        failure: failure
      }

      {[check | checks], [failure | failures]}
    end
  end

  defp normalize_nulls(:null), do: nil

  defp normalize_nulls(list) when is_list(list) do
    Enum.map(list, &normalize_nulls/1)
  end

  defp normalize_nulls(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, normalize_nulls(value)} end)
  end

  defp normalize_nulls(value), do: value
end
