#!/usr/bin/env bash
# Native YAML producers; source from the repository root.
participant_template() {
  oc process --local -f "$2" -p "PARTICIPANT=$1" -o yaml
}
participant_source() {
  oc create configmap workshop-source -n "tableschnappi-$1" --dry-run=client -o yaml \
    --from-file=source.tar.gz=.cache/source.tar.gz --from-file=SOURCE_COMMIT=.cache/SOURCE_COMMIT |
    oc label --local -f - event.redhat.com/owner=darmstadt-demo -o yaml
}
