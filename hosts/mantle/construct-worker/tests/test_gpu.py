"""gpu_state offline: canned nvidia-smi rows, no GPU. Run: python3 -m unittest discover -s tests"""

import os
import unittest
from unittest import mock

from construct_worker import gpu

TOTAL = [["10", "6000", "8192"]]
OLLAMA = 4242


def apps(*rows):
    return lambda _smi, query: TOTAL if "query-gpu" in query else [[str(p), n, str(mb)] for p, n, mb in rows]


class GpuState(unittest.TestCase):
    def test_ollama_counts_as_ours_only_when_asked(self):
        rows = apps((OLLAMA, "[No data]", 3700), (os.getpid(), "python3", 100))
        with mock.patch.object(gpu, "_smi", rows), mock.patch.object(gpu, "_is_ollama", lambda pid: pid == OLLAMA):
            busy = gpu.gpu_state()
            self.assertTrue(busy["busy"])
            self.assertIn("[No data] 3.6 GB", busy["reason"])
            free = gpu.gpu_state(own_ollama=True)
            self.assertFalse(free["busy"])
            self.assertEqual(free["foreignApps"], [])

    def test_other_processes_still_count(self):
        rows = apps((OLLAMA, "[No data]", 3700), (777, "game", 2000))
        with mock.patch.object(gpu, "_smi", rows), mock.patch.object(gpu, "_is_ollama", lambda pid: pid == OLLAMA):
            s = gpu.gpu_state(own_ollama=True)
            self.assertTrue(s["busy"])
            self.assertEqual(s["foreignApps"], [{"name": "game", "memMb": 2000}])

    def test_is_ollama_reads_argv0(self):
        self.assertFalse(gpu._is_ollama(os.getpid()))
        self.assertFalse(gpu._is_ollama(2**22 + 12345))  # no such process


if __name__ == "__main__":
    unittest.main()
