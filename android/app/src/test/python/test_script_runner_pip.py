"""Host-side checks for the HarmonyOS pip fix (run: python -m unittest, needs pip)."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "main", "python"))


class AppDataDirTest(unittest.TestCase):
    def test_not_derived_from_home(self):
        root = tempfile.mkdtemp()
        os.environ["HOME"] = "/data"  # HarmonyOS-like unwritable HOME
        os.environ["TMPDIR"] = os.path.join(root, "cache", "tmp")
        import script_runner as sr
        sr._APP_DATA_DIR = None
        self.assertEqual(sr._app_data_dir(), os.path.join(root, "files"))
        site = sr._ensure_site_packages()
        self.assertTrue(os.path.isdir(site))
        self.assertTrue(os.environ["PYTHONUSERBASE"].startswith(os.path.join(root, "files")))


class PipPatchTest(unittest.TestCase):
    def test_find_survives_assetpath_error(self):
        import pip._internal.metadata.importlib._envs as envs
        import script_runner as sr

        def broken(self, location, *a, **k):
            yield "dist1"
            raise AttributeError("'AssetPath' object has no attribute 'parent'")

        original = envs._DistributionFinder.find
        try:
            envs._DistributionFinder.find = broken
            sr._PIP_PATCHED = False
            sr._patch_pip_for_chaquopy()
            self.assertEqual(list(envs._DistributionFinder.find(None, "x")), ["dist1"])
        finally:
            envs._DistributionFinder.find = original


class AndroidTagsTest(unittest.TestCase):
    def test_android_wheels_are_preferred_tags(self):
        import script_runner as sr
        tags = sr._android_native_tags()
        self.assertTrue(tags)
        py = "cp%d%d" % sys.version_info[:2]
        self.assertTrue(any(t.interpreter == py and t.platform.startswith("android_21_") for t in tags))


if __name__ == "__main__":
    unittest.main()
