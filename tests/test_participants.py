"""Batch selection/failure checks; no cluster or credentials required."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def shell(code, *args):
    return subprocess.run(['bash', '-c', 'set -euo pipefail; source scripts/helpers/participants.sh; ' + code, '_', *args],
                          cwd=ROOT, text=True, capture_output=True)


class ParticipantTests(unittest.TestCase):
    def test_default_roster_and_explicit_test(self):
        result = shell('participant_selection; printf "%s\\n" "${participants[@]}"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [f'user{n}' for n in range(1, 51)])
        result = shell('participant_selection --test; printf "%s\\n" "${participants[@]}"')
        self.assertEqual(result.stdout.splitlines(), ['test'])

    def test_range_normalizes_padding(self):
        result = shell('participant_selection 07 09; printf "%s\\n" "${participants[@]}"')
        self.assertEqual(result.stdout.splitlines(), ['user7', 'user8', 'user9'])

    def test_invalid_names_and_ranges_are_rejected(self):
        for args in [('0','1'), ('1','51'), ('3','2'), ('1',), ('--test','1'), ('admin',)]:
            self.assertNotEqual(shell('participant_selection "$@"', *args).returncode, 0, args)
        for name in ['admin', 'user01', 'user51', 'test-admin', '../test', '']:
            self.assertNotEqual(shell('participant_name "$1"', name).returncode, 0, name)
        for name in ['user1', 'user50', 'test']:
            self.assertEqual(shell('participant_name "$1"', name).returncode, 0)

    def test_failure_waits_for_group_and_stops_later_participants(self):
        with tempfile.TemporaryDirectory() as directory:
            log = str(Path(directory) / 'jobs')
            result = shell('''participant_selection 1 4
worker() { printf '%s start\\n' "$1" >> "$job_log"; sleep 0.05; [[ $1 != user2 ]]; }
''' + 'job_log=$1; participant_batch 2 worker', log)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(set(Path(log).read_text().splitlines()), {'user1 start', 'user2 start'})

    def test_complete_batch_and_invalid_concurrency(self):
        with tempfile.TemporaryDirectory() as directory:
            log = str(Path(directory) / 'jobs')
            result = shell('participant_selection 1 5; job_log=$1; worker() { echo "$1" >> "$job_log"; }; participant_batch 2 worker', log)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(set(Path(log).read_text().splitlines()), {f'user{n}' for n in range(1, 6)})
        self.assertNotEqual(shell('participant_selection --test; participant_batch 9 true').returncode, 0)

    def test_keycloak_rejects_unapproved_targets_before_api_access(self):
        result = subprocess.run(['python3', 'scripts/helpers/keycloak-accounts.py', 'create', '/tmp/private-test', 'admin'],
                                cwd=ROOT, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('user1..user50 or test', result.stderr)


if __name__ == '__main__':
    unittest.main()
