#!/usr/bin/env bash
# Shared roster selection. Source from an entry script after changing to repo root.
participant_range() {
  [[ $# == 0 || $# == 2 ]] || { echo 'Provide both START and END, or neither.' >&2; exit 1; }
  local configured_count
  configured_count=$(jq -er '.participantCount' config/source.lock.json)
  [[ $configured_count =~ ^[0-9]{1,2}$ ]] || { echo 'Invalid participantCount.' >&2; exit 1; }
  configured_count=$((10#$configured_count))
  [[ $configured_count -ge 1 && $configured_count -le 50 ]] || {
    echo 'participantCount must be between 1 and 50.' >&2; exit 1;
  }
  first_participant=${1:-1}
  last_participant=${2:-$configured_count}
  [[ $first_participant =~ ^[0-9]{1,2}$ && $last_participant =~ ^[0-9]{1,2}$ ]] || {
    echo 'START and END must be participant numbers.' >&2; exit 1;
  }
  first_participant=$((10#$first_participant))
  last_participant=$((10#$last_participant))
  [[ $first_participant -ge 1 && $first_participant -le $last_participant && $last_participant -le $configured_count ]] || {
    echo "Expected 1 <= START <= END <= $configured_count." >&2; exit 1;
  }
}
