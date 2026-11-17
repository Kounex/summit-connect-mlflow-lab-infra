#!/usr/bin/env python3
"""Helm post-renderer: preserve live NeMo policy; roll credential consumers."""
import copy
import json
import os
import subprocess
import sys
import yaml


def retain_policy(desired_data, live_data):
    desired = yaml.safe_load(desired_data['config.yaml'])
    current = yaml.safe_load(live_data['config.yaml'])
    current['models'] = desired['models']
    result = copy.deepcopy(live_data)
    result['config.yaml'] = yaml.safe_dump(current, sort_keys=False, allow_unicode=True)
    return result


def main():
    namespace = os.environ['MODEL_NAMESPACE']
    revision = os.environ['MODEL_REVISION']
    objects = list(yaml.safe_load_all(sys.stdin))
    for obj in objects:
        if not obj:
            continue
        kind, name = obj['kind'], obj['metadata']['name']
        if kind == 'ConfigMap' and name == 'tableschnappi-guardrails-config':
            live = json.loads(subprocess.check_output([
                'oc', 'get', 'configmap', name, '-n', namespace, '-o', 'json']))
            obj['data'] = retain_policy(obj['data'], live['data'])
        if kind == 'Deployment' and name == 'tableschnappi-mlflow-proxy':
            obj['spec']['template'].setdefault('metadata', {}).setdefault('annotations', {})[
                'event.redhat.com/model-revision'] = revision
        if kind == 'Notebook':
            container = next(c for c in obj['spec']['template']['spec']['containers'] if c['name'] == name)
            env = container.setdefault('env', [])
            env[:] = [item for item in env if item['name'] != 'TABLESCHNAPPI_MODEL_REVISION']
            env.append({'name': 'TABLESCHNAPPI_MODEL_REVISION', 'value': revision})
        if kind == 'NemoGuardrails':
            env = obj['spec'].setdefault('env', [])
            env[:] = [item for item in env if item['name'] != 'TABLESCHNAPPI_MODEL_REVISION']
            env.append({'name': 'TABLESCHNAPPI_MODEL_REVISION', 'value': revision})
    yaml.safe_dump_all([obj for obj in objects if obj], sys.stdout, sort_keys=False)


if __name__ == '__main__':
    main()
