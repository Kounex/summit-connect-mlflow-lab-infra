"""Readiness checks under the participant's native identity; no model calls/writes."""
import json
import os
from pathlib import Path
import sys

import mlflow
import requests
import yaml
from kubernetes import client as kubeclient, config as kubeconfig

namespace, source = sys.argv[1:]
assert os.environ['MLFLOW_WORKSPACE'] == namespace
assert os.environ['MLFLOW_TRACKING_AUTH'] == 'kubernetes-namespaced'
assert os.environ['MODEL_EXTRA_BODY'] in ('true', 'false')
assert os.environ['OPENAI_API_KEY']
assert Path('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read_text().strip() == namespace
assert Path('/opt/app-root/src/.tableschnappi-source').read_text().strip() == source
kubeconfig.load_incluster_config()
core = kubeclient.CoreV1Api()
policy = yaml.safe_load(core.read_namespaced_config_map('tableschnappi-guardrails-config', namespace).data['config.yaml'])
assert policy['rails']['input']['flows'] == []
prompt = mlflow.genai.load_prompt('prompts:/restaurant-assistant-prompt@active', cache_ttl_seconds=0)
baseline = mlflow.genai.load_prompt('prompts:/restaurant-assistant-prompt@baseline', cache_ttl_seconds=0)
assert str(prompt.version) == str(baseline.version) == '1'
if namespace != 'tableschnappi-test':
    client = mlflow.MlflowClient()
    token = None
    while True:
        experiments = client.search_experiments(view_type=1, max_results=100, page_token=token)
        for experiment in experiments:
            assert not client.search_runs([experiment.experiment_id], max_results=1), 'Attendee has rehearsal runs'
            assert not client.search_traces(experiment_ids=[experiment.experiment_id], max_results=1), 'Attendee has rehearsal traces'
        token = experiments.token
        if not token:
            break
response = requests.post(os.environ['MCP_URL'], json={
    'jsonrpc': '2.0', 'id': 'readiness', 'method': 'tools/list', 'params': {}},
    headers={'Accept': 'application/json, text/event-stream'}, timeout=20)
response.raise_for_status()
assert 'get_menu' in response.content.decode('utf-8')
# Real notebook dependencies and source must be available before attendees arrive.
import langgraph
from langchain_openai import ChatOpenAI
nb = json.loads(Path('/opt/app-root/src/tableschnappi/workshop/agent-playground.ipynb').read_text())
assert any('RUN_AGENT = False' in ''.join(c['source']) for c in nb['cells'] if c['cell_type'] == 'code')
print(json.dumps({'namespace': namespace, 'native_auth': True, 'prompt': str(prompt.version),
                  'source': source, 'mcp': True, 'notebook_ready': True}), flush=True)
