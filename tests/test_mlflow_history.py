"""History reset scope/fail-closed checks without MLflow or cluster dependencies."""
import ast
from pathlib import Path
import json
import os
import re
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]


def reset_main(client, namespace='tableschnappi-user1', inventory_namespace=None):
    # Execute the actual entry function; SDK imports are deliberately stubbed.
    tree = ast.parse((ROOT / 'scripts/helpers/mlflow-history.py').read_text())
    function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'main')
    scope = {'Path': Path, 'os': os, 're': re, 'json': json, 'sys': SimpleNamespace(argv=[
        'mlflow-history.py', 'clear', namespace, json.dumps({
            'namespace': inventory_namespace or namespace, 'reset_id': 'a' * 32,
            'prompts': ['own-prompt'], 'models': ['own-model'],
            'experiments': [{'id': '7', 'name': 'own-experiment', 'traces': ['own-trace']}]})]),
        'MlflowClient': Mock(return_value=client)}
    exec(compile(ast.Module(body=[function], type_ignores=[]), '<history-main>', 'exec'), scope)
    return scope


class HistoryTests(unittest.TestCase):
    def test_workspace_identity_mismatch_blocks_sdk_access(self):
        scope = reset_main(Mock())
        with patch.object(Path, 'read_text', return_value='tableschnappi-user2'), patch.dict(os.environ, {
            'MLFLOW_WORKSPACE': 'tableschnappi-user1', 'MLFLOW_TRACKING_AUTH': 'kubernetes-namespaced'}):
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                scope['main']()
        scope['MlflowClient'].assert_not_called()

    def test_foreign_backup_cannot_delete_current_workspace(self):
        client = Mock()
        scope = reset_main(client, inventory_namespace='tableschnappi-user2')
        with patch.object(Path, 'read_text', return_value='tableschnappi-user1'), patch.dict(os.environ, {
            'MLFLOW_WORKSPACE': 'tableschnappi-user1', 'MLFLOW_TRACKING_AUTH': 'kubernetes-namespaced'}):
            with self.assertRaisesRegex(ValueError, 'inventory does not match'):
                scope['main']()
        self.assertEqual(client.mock_calls, [])

    def test_only_backed_up_ids_are_retired(self):
        client = Mock()
        client.get_experiment.return_value = SimpleNamespace(name='own-experiment', lifecycle_stage='active')
        scope = reset_main(client)
        with patch.object(Path, 'read_text', return_value='tableschnappi-user1'), patch.dict(os.environ, {
            'MLFLOW_WORKSPACE': 'tableschnappi-user1', 'MLFLOW_TRACKING_AUTH': 'kubernetes-namespaced'}):
            scope['main']()
        client.delete_prompt.assert_called_once_with('own-prompt')
        client.delete_registered_model.assert_called_once_with('own-model')
        client.delete_traces.assert_called_once_with(experiment_id='7', trace_ids=['own-trace'])
        client.rename_experiment.assert_called_once_with('7', 'reset-' + 'a' * 32 + '-7')
        client.delete_experiment.assert_called_once_with('7')
        client.search_experiments.assert_not_called()


if __name__ == '__main__':
    unittest.main()
