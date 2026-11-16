"""Export/reset one workbench's own MLflow workspace through its native SDK auth."""
import json
import os
from pathlib import Path
import re
import sys
import tarfile
import tempfile
import uuid

import mlflow
from google.protobuf.json_format import MessageToDict
from mlflow import MlflowClient


def pages(method, **kwargs):
    token = None
    while True:
        result = method(page_token=token, **kwargs)
        yield from result
        token = getattr(result, 'token', None)
        if not token:
            return


def serializable(value):
    if isinstance(value, (set, frozenset)):
        return sorted(value, key=str)
    for method in ('to_dict', 'to_dictionary'):
        if hasattr(value, method):
            return getattr(value, method)()
    if hasattr(value, 'to_proto'):
        return MessageToDict(value.to_proto(), preserving_proto_field_name=True)
    if hasattr(value, 'isoformat'):
        return value.isoformat()
    if type(value).__module__.startswith('mlflow.entities.'):
        return {'entity_type': type(value).__name__, **vars(value)}
    raise TypeError(type(value).__name__)


def main():
    mode, namespace, *arguments = sys.argv[1:]
    if mode not in ('export', 'clear') or not re.fullmatch(r'tableschnappi-(?:test|user(?:[1-9]|[1-4][0-9]|50))', namespace):
        raise ValueError('Supply export/clear and an approved participant namespace')
    actual = Path('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read_text().strip()
    if actual != namespace or os.environ.get('MLFLOW_WORKSPACE') != namespace or os.environ.get('MLFLOW_TRACKING_AUTH') != 'kubernetes-namespaced':
        raise ValueError('Workbench namespace/native MLflow identity mismatch')
    client = MlflowClient()
    if mode == 'export':
        inventory = {'namespace': namespace, 'reset_id': uuid.uuid4().hex, 'experiments': [], 'models': [], 'prompts': []}
        metadata = {'experiments': [], 'models': [], 'runs': [], 'traces': [], 'prompts': []}
        with tempfile.TemporaryDirectory(prefix='mlflow-export-') as directory:
            root = Path(directory)
            for experiment in pages(client.search_experiments, view_type=3, max_results=1000):
                item = {'id': experiment.experiment_id, 'name': experiment.name, 'traces': []}
                metadata['experiments'].append(experiment)
                for trace in pages(client.search_traces, experiment_ids=[experiment.experiment_id], max_results=100):
                    item['traces'].append(trace.info.trace_id)
                    metadata['traces'].append(trace)
                for run in pages(client.search_runs, experiment_ids=[experiment.experiment_id], run_view_type=3, max_results=1000):
                    metadata['runs'].append(run)
                    if client.list_artifacts(run.info.run_id):
                        destination = root / 'artifacts' / run.info.run_id
                        destination.mkdir(parents=True)
                        client.download_artifacts(run.info.run_id, '', str(destination))
                inventory['experiments'].append(item)
            for model in pages(client.search_registered_models, max_results=100):
                versions = list(pages(client.search_model_versions, filter_string="name='" + model.name.replace("'", "\\'") + "'", max_results=1000))
                metadata['models'].append({'model': model, 'versions': versions})
                inventory['models'].append(model.name)
            for prompt in pages(client.search_prompts, max_results=1000):
                versions = list(pages(client.search_prompt_versions, name=prompt.name, max_results=1000))
                metadata['prompts'].append({'prompt': prompt, 'versions': versions})
                inventory['prompts'].append(prompt.name)
            (root / 'inventory.json').write_text(json.dumps(inventory))
            (root / 'metadata.json').write_text(json.dumps(metadata, default=serializable))
            with tarfile.open(fileobj=sys.stdout.buffer, mode='w|gz') as archive:
                for path in root.iterdir():
                    archive.add(path, arcname=path.name)
        return
    inventory = json.loads(arguments[0])
    if inventory['namespace'] != namespace or not re.fullmatch('[a-f0-9]{32}', inventory['reset_id']):
        raise ValueError('Backup inventory does not match target')
    # Only delete IDs/names present in the verified backup, never all-workspace data.
    for name in inventory['prompts']:
        client.delete_prompt(name)
    for name in inventory['models']:
        client.delete_registered_model(name)
    for item in inventory['experiments']:
        experiment = client.get_experiment(item['id'])
        if experiment.name != item['name']:
            raise ValueError('Experiment changed after export; inspect before retrying')
        if experiment.lifecycle_stage == 'deleted':
            client.restore_experiment(item['id'])
        for offset in range(0, len(item['traces']), 100):
            client.delete_traces(experiment_id=item['id'], trace_ids=item['traces'][offset:offset + 100])
        # Native experiment deletion is soft. Retire the name so seed hooks can
        # create a fresh canonical experiment without restoring old runs.
        client.rename_experiment(item['id'], 'reset-' + inventory['reset_id'] + '-' + item['id'])
        client.delete_experiment(item['id'])
    print(f"{namespace}: traces/prompts deleted; old experiments/runs retired with native soft deletion")


if __name__ == '__main__':
    main()
