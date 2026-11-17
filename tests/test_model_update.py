"""Model updates must retain attendees' live guardrail configuration."""
import importlib.util
from pathlib import Path
import unittest

HAS_YAML = importlib.util.find_spec('yaml') is not None


@unittest.skipUnless(HAS_YAML, 'Model update tests require PyYAML')
class ModelUpdateTests(unittest.TestCase):
    def test_only_models_change_in_live_policy(self):
        import yaml
        path = Path(__file__).resolve().parents[1] / 'scripts/helpers/model-renderer/render.py'
        spec = importlib.util.spec_from_file_location('model_renderer', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        current = {'models': [{'model': 'old'}], 'passthrough': True,
                   'rails': {'input': {'flows': ['self check input']}},
                   'prompts': [{'task': 'self_check_input', 'content': 'Keep my custom policy'}]}
        desired = {'models': [{'model': 'new', 'parameters': {'base_url': 'https://model.example.com/v1'}}],
                   'rails': {'input': {'flows': []}}}
        live_data = {'config.yaml': yaml.safe_dump(current), 'rails.co': 'my refusal', 'custom.co': 'my flow'}
        original = dict(live_data)
        result = module.retain_policy({'config.yaml': yaml.safe_dump(desired)}, live_data)
        updated = yaml.safe_load(result['config.yaml'])
        self.assertEqual(updated['models'], desired['models'])
        self.assertEqual({k:v for k,v in updated.items() if k != 'models'},
                         {k:v for k,v in current.items() if k != 'models'})
        self.assertEqual(result['rails.co'], 'my refusal')
        self.assertEqual(result['custom.co'], 'my flow')
        self.assertEqual(live_data, original)


    def test_notebook_revision_uses_supported_container_env(self):
        import contextlib
        import io
        import os
        from unittest.mock import patch
        import yaml
        path = Path(__file__).resolve().parents[1] / 'scripts/helpers/model-renderer/render.py'
        spec = importlib.util.spec_from_file_location('model_renderer', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        objects = [
            {'kind': 'Notebook', 'metadata': {'name': 'user1'},
             'spec': {'template': {'spec': {'containers': [{'name': 'user1', 'env': []}]}}}},
            {'kind': 'NemoGuardrails', 'metadata': {'name': 'tableschnappi-guardrails'}, 'spec': {'env': []}},
            {'kind': 'Deployment', 'metadata': {'name': 'tableschnappi-mlflow-proxy'}, 'spec': {'template': {}}},
        ]
        output = io.StringIO()
        with patch.dict(os.environ, MODEL_NAMESPACE='tableschnappi-user1', MODEL_REVISION='revision'), \
                patch('sys.stdin', io.StringIO(yaml.safe_dump_all(objects))), contextlib.redirect_stdout(output):
            module.main()
        notebook, nemo, assistant = list(yaml.safe_load_all(output.getvalue()))
        self.assertNotIn('metadata', notebook['spec']['template'])
        self.assertIn({'name': 'TABLESCHNAPPI_MODEL_REVISION', 'value': 'revision'},
                      notebook['spec']['template']['spec']['containers'][0]['env'])
        self.assertIn({'name': 'TABLESCHNAPPI_MODEL_REVISION', 'value': 'revision'}, nemo['spec']['env'])
        self.assertEqual(assistant['spec']['template']['metadata']['annotations']['event.redhat.com/model-revision'],
                         'revision')


if __name__ == '__main__':
    unittest.main()
