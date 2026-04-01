import sys
import os
import io
import traceback
import threading
import queue as _queue_mod
import gc
import warnings


def _ensure_site_packages():
    """Ensure pip's install target is on sys.path."""
    site_dir = os.path.join(os.environ.get("HOME", "/data/data/com.daozhang.py"), "chaquopy/pip")
    if not os.path.exists(site_dir):
        os.makedirs(site_dir, exist_ok=True)
    if site_dir not in sys.path:
        sys.path.insert(0, site_dir)
    return site_dir


# ---------------------------------------------------------------------------
# Public API: let user scripts check whether stop has been requested.
# Usage:
#   import script_runner
#   if script_runner.stop_requested():
#       break
# ---------------------------------------------------------------------------

def stop_requested():
    """Return True if the user has pressed Stop in the UI.

    Designed for polling / long-running scripts:

        import script_runner
        while True:
            if script_runner.stop_requested():
                print("已停止")
                break
            do_work()
    """
    return _stop_requested.is_set()


# --- Real-time output and stdin support ---

# Thread-safe queue for output lines: items are (type, content) tuples
_output_queue = _queue_mod.Queue()

# Stdin support: use a Queue for thread-safe, race-free blocking reads.
_stdin_queue = _queue_mod.Queue()
_STDIN_STOP = object()  # sentinel to unblock a waiting readline()
_waiting_for_input = False

# Touch/scene support: queue for touch events from Flutter to Python scene module.
_touch_queue = _queue_mod.Queue()
_TOUCH_STOP = object()  # sentinel to stop scene loop

# Persistent stop flag: stays True until the script actually exits.
# Checked in every write() and readline() call so that bare `except:`
# clauses in user code cannot swallow the KeyboardInterrupt forever.
_stop_requested = threading.Event()


class _QueueWriter:
    """Replacement for sys.stdout/stderr that puts lines into a queue."""
    def __init__(self, stream_type):
        self._type = stream_type
        self._line_buf = ""

    def write(self, text):
        if not text:
            return 0
        # Re-raise stop signal so bare `except:` can't swallow it forever
        if _stop_requested.is_set():
            raise KeyboardInterrupt()
        self._line_buf += text
        while "\n" in self._line_buf:
            line, self._line_buf = self._line_buf.split("\n", 1)
            _output_queue.put((self._type, line))
        return len(text)

    def flush(self):
        if self._line_buf:
            _output_queue.put((self._type, self._line_buf))
            self._line_buf = ""

    def isatty(self):
        return False

    @property
    def encoding(self):
        return "utf-8"


class _BlockingStdin:
    """Replacement for sys.stdin that blocks until provide_stdin() is called."""
    def readline(self):
        global _waiting_for_input
        # Check stop flag before even waiting
        if _stop_requested.is_set():
            raise KeyboardInterrupt()
        _waiting_for_input = True
        # Notify Kotlin that input is needed
        _output_queue.put(("__stdin_request__", ""))
        # Use a timeout loop so we can periodically check the stop flag.
        # This ensures that even if the stop signal arrives between checks,
        # we will notice it within 0.2 seconds.
        while True:
            if _stop_requested.is_set():
                _waiting_for_input = False
                raise KeyboardInterrupt()
            try:
                value = _stdin_queue.get(timeout=0.2)
            except _queue_mod.Empty:
                continue
            _waiting_for_input = False
            if value is _STDIN_STOP:
                raise KeyboardInterrupt()
            return value

    def read(self, n=-1):
        return self.readline()

    def isatty(self):
        return False

    @property
    def encoding(self):
        return "utf-8"


def poll_output():
    """Called by Kotlin to get pending output. Returns list of (type, content) tuples.
    Returns empty list if no output available."""
    items = []
    try:
        while True:
            items.append(_output_queue.get_nowait())
    except _queue_mod.Empty:
        pass
    return items


def provide_stdin(value):
    """Called from Kotlin when the user submits input."""
    _stdin_queue.put(value + "\n")


def provide_touch(data_json):
    """Called from Kotlin when a touch event or size info arrives for the scene module."""
    import json
    _touch_queue.put(json.loads(data_json))


def stop_running():
    """Called from Kotlin to force-stop a running script (including scene loops).

    Sets a persistent _stop_requested flag so that even if user code has
    bare `except:` clauses that swallow KeyboardInterrupt, the next
    print() / input() / write() call will raise it again.
    """
    # Set persistent flag FIRST — checked in write() and readline()
    _stop_requested.set()
    # Stop any scene game loop
    try:
        import scene as _scene_mod
        _scene_mod._scene_running = False
    except Exception:
        pass
    # Unblock stdin
    _stdin_queue.put(_STDIN_STOP)
    # Stop scene via touch queue
    _touch_queue.put(_TOUCH_STOP)


def _build_inline_hook():
    """Build a complete inline hook script as fallback when http_debug_hook.py
    cannot be imported. Returns Python code string or None."""
    config_raw = os.environ.get('PYRUNNER_HTTP_HOOK_CONFIG', '')
    if not config_raw:
        return None
    return """
import os, sys, json, time, uuid

_HOOK_CONFIG = json.loads(os.environ.get('PYRUNNER_HTTP_HOOK_CONFIG', '{}'))
_OVERRIDE_ENABLED = _HOOK_CONFIG.get('override_enabled', False)
_RECORD_ENABLED = _HOOK_CONFIG.get('record_requests', True)
_RECORD_BODY = _HOOK_CONFIG.get('record_response_body', False)
_GLOBAL_UA = _HOOK_CONFIG.get('global_user_agent', '')
_GLOBAL_COOKIE = _HOOK_CONFIG.get('global_cookie', '')
_GLOBAL_HEADERS_RAW = _HOOK_CONFIG.get('global_headers', '')
_BODY_PREVIEW_LIMIT = 2048
try:
    _GLOBAL_HEADERS = json.loads(_GLOBAL_HEADERS_RAW) if _GLOBAL_HEADERS_RAW else {}
except Exception:
    _GLOBAL_HEADERS = {}

def _send_record(record):
    if not _RECORD_ENABLED: return
    try:
        print('__HTTP_RECORD__' + json.dumps(record, ensure_ascii=False, default=str), flush=True)
    except Exception: pass

def _apply_overrides(headers):
    if not _OVERRIDE_ENABLED: return headers
    if headers is None: headers = {}
    headers = dict(headers)
    if _GLOBAL_UA: headers['User-Agent'] = _GLOBAL_UA
    if _GLOBAL_COOKIE: headers['Cookie'] = _GLOBAL_COOKIE
    for k, v in _GLOBAL_HEADERS.items(): headers[k] = v
    return headers

def _safe_body_preview(body):
    if not _RECORD_BODY or body is None: return None
    try:
        if isinstance(body, bytes):
            text = body[:_BODY_PREVIEW_LIMIT].decode('utf-8', errors='replace')
        elif isinstance(body, str):
            text = body[:_BODY_PREVIEW_LIMIT]
        else:
            text = str(body)[:_BODY_PREVIEW_LIMIT]
        if len(text) >= _BODY_PREVIEW_LIMIT:
            text += '... (truncated)'
        return text
    except Exception:
        return None

def _safe_headers_dict(headers):
    if headers is None: return {}
    try:
        if isinstance(headers, dict):
            return {str(k): str(v) for k, v in headers.items()}
        return {str(k): str(v) for k, v in dict(headers).items()}
    except Exception:
        return {}

# ── Hook: requests ──
try:
    import requests
    from requests import Session
    _orig_send = Session.send
    def _p_send(self, request, **kw):
        rid = str(uuid.uuid4())[:8]
        t0 = time.time()
        if _OVERRIDE_ENABLED:
            request.headers = _apply_overrides(dict(request.headers))
        rec = {'id': rid, 'timestamp': int(t0*1000), 'method': request.method,
               'url': request.url, 'library': 'requests',
               'request_headers': _safe_headers_dict(request.headers),
               'request_body': _safe_body_preview(request.body) if request.body else None,
               'used_proxy': False, 'ssl_verify': True}
        try:
            resp = _orig_send(self, request, **kw)
            rec['status_code'] = resp.status_code
            rec['response_headers'] = _safe_headers_dict(resp.headers)
            rec['response_body_preview'] = _safe_body_preview(resp.content)
            rec['duration_ms'] = int((time.time()-t0)*1000)
            _send_record(rec)
            return resp
        except Exception as e:
            rec['error_type'] = type(e).__name__
            rec['error_message'] = str(e)[:500]
            rec['duration_ms'] = int((time.time()-t0)*1000)
            _send_record(rec)
            raise
    Session.send = _p_send
except ImportError: pass

# ── Hook: httpx ──
try:
    import httpx
    if hasattr(httpx, 'Client'):
        _orig_cx_send = httpx.Client.send
        def _p_cx_send(self, request, **kw):
            rid = str(uuid.uuid4())[:8]
            t0 = time.time()
            if _OVERRIDE_ENABLED:
                for k, v in _apply_overrides({}).items():
                    request.headers[k] = v
            rec = {'id': rid, 'timestamp': int(t0*1000), 'method': str(request.method),
                   'url': str(request.url), 'library': 'httpx',
                   'request_headers': _safe_headers_dict(request.headers),
                   'used_proxy': False, 'ssl_verify': True}
            try:
                resp = _orig_cx_send(self, request, **kw)
                rec['status_code'] = resp.status_code
                rec['response_headers'] = _safe_headers_dict(resp.headers)
                rec['response_body_preview'] = _safe_body_preview(resp.content)
                rec['duration_ms'] = int((time.time()-t0)*1000)
                _send_record(rec)
                return resp
            except Exception as e:
                rec['error_type'] = type(e).__name__
                rec['error_message'] = str(e)[:500]
                rec['duration_ms'] = int((time.time()-t0)*1000)
                _send_record(rec)
                raise
        httpx.Client.send = _p_cx_send
    if hasattr(httpx, 'AsyncClient'):
        _orig_ax_send = httpx.AsyncClient.send
        async def _p_ax_send(self, request, **kw):
            rid = str(uuid.uuid4())[:8]
            t0 = time.time()
            if _OVERRIDE_ENABLED:
                for k, v in _apply_overrides({}).items():
                    request.headers[k] = v
            rec = {'id': rid, 'timestamp': int(t0*1000), 'method': str(request.method),
                   'url': str(request.url), 'library': 'httpx-async',
                   'request_headers': _safe_headers_dict(request.headers),
                   'used_proxy': False, 'ssl_verify': True}
            try:
                resp = await _orig_ax_send(self, request, **kw)
                rec['status_code'] = resp.status_code
                rec['response_headers'] = _safe_headers_dict(resp.headers)
                rec['response_body_preview'] = _safe_body_preview(resp.content)
                rec['duration_ms'] = int((time.time()-t0)*1000)
                _send_record(rec)
                return resp
            except Exception as e:
                rec['error_type'] = type(e).__name__
                rec['error_message'] = str(e)[:500]
                rec['duration_ms'] = int((time.time()-t0)*1000)
                _send_record(rec)
                raise
        httpx.AsyncClient.send = _p_ax_send
except ImportError: pass

# ── Hook: urllib.request ──
try:
    import urllib.request as _ureq
    _orig_urlopen = _ureq.urlopen
    def _p_urlopen(url, data=None, timeout=None, **kw):
        rid = str(uuid.uuid4())[:8]
        t0 = time.time()
        if isinstance(url, _ureq.Request):
            str_url = url.full_url
            method = url.get_method()
        else:
            str_url = str(url)
            method = 'POST' if data else 'GET'
        rec = {'id': rid, 'timestamp': int(t0*1000), 'method': method,
               'url': str_url, 'library': 'urllib',
               'used_proxy': False, 'ssl_verify': True, 'request_headers': {}}
        try:
            if timeout is not None:
                resp = _orig_urlopen(url, data=data, timeout=timeout, **kw)
            else:
                resp = _orig_urlopen(url, data=data, **kw)
            rec['status_code'] = resp.getcode()
            rec['response_headers'] = _safe_headers_dict(dict(resp.headers))
            if _RECORD_BODY:
                try:
                    body = resp.read()
                    rec['response_body_preview'] = _safe_body_preview(body)
                    import io as _io
                    resp = type('_Resp', (), {
                        'read': lambda s, n=-1: _io.BytesIO(body).read(n),
                        'getcode': lambda s: rec['status_code'],
                        'headers': resp.headers, 'status': resp.status,
                        'geturl': resp.geturl, 'info': resp.info,
                        'close': lambda s: None,
                        '__enter__': lambda s: s, '__exit__': lambda s,*a: None,
                    })()
                except Exception: pass
            rec['duration_ms'] = int((time.time()-t0)*1000)
            _send_record(rec)
            return resp
        except Exception as e:
            rec['error_type'] = type(e).__name__
            rec['error_message'] = str(e)[:500]
            rec['duration_ms'] = int((time.time()-t0)*1000)
            _send_record(rec)
            raise
    _ureq.urlopen = _p_urlopen
except ImportError: pass
"""


def _cleanup_network_modules():
    """Clean up cached network sessions/connectors between script runs.

    Libraries like aiohttp, urllib3, requests cache connection pools
    in module-level globals. If we don't close them, their underlying
    sockets and transports leak across runs.
    """
    # Close aiohttp connector caches
    try:
        if 'aiohttp' in sys.modules:
            aiohttp = sys.modules['aiohttp']
            # Close any module-level default connector
            if hasattr(aiohttp, 'connector') and hasattr(aiohttp.connector, '_default_connector'):
                conn = aiohttp.connector._default_connector
                if conn is not None and not conn.closed:
                    conn.close()
    except Exception:
        pass

    # Close urllib3 connection pools
    try:
        if 'urllib3.poolmanager' in sys.modules:
            pm = sys.modules['urllib3.poolmanager']
            if hasattr(pm, 'PoolManager') and hasattr(pm.PoolManager, '_default_pool'):
                pass  # urllib3 doesn't have a global pool, but clean up module state
    except Exception:
        pass

    # Close requests sessions
    try:
        if 'requests' in sys.modules and 'requests.adapters' in sys.modules:
            adapters = sys.modules['requests.adapters']
            # Invalidate cached adapters
            if hasattr(adapters, '_default_adapter'):
                try:
                    adapters._default_adapter.close()
                except Exception:
                    pass
    except Exception:
        pass

    # Force close any lingering file descriptors for sockets
    # by clearing relevant module-level caches
    try:
        if 'aiohttp.client' in sys.modules:
            client_mod = sys.modules['aiohttp.client']
            # Clear any cached session references
            for attr_name in dir(client_mod):
                obj = getattr(client_mod, attr_name, None)
                if hasattr(obj, 'close') and hasattr(obj, '_connector'):
                    try:
                        obj.close()
                    except Exception:
                        pass
    except Exception:
        pass


def run_script(code, working_dir="", hook_env_json=""):
    """Execute Python code with real-time output and stdin support."""
    _ensure_site_packages()
    global _waiting_for_input
    _waiting_for_input = False

    # Clear the stop flag from any previous run
    _stop_requested.clear()

    # ── Inject hook environment variables ──
    _injected_env_keys = []
    if hook_env_json and hook_env_json.strip():
        try:
            import json as _json
            hook_env = _json.loads(hook_env_json)
            if isinstance(hook_env, dict):
                for k, v in hook_env.items():
                    os.environ[str(k)] = str(v)
                    _injected_env_keys.append(str(k))
        except Exception:
            pass

    # Set working directory
    if working_dir and working_dir.strip():
        workspace = working_dir.strip()
    else:
        workspace = os.path.join(os.environ.get("HOME", "/data/data/com.daozhang.py"), "workspace")
    os.makedirs(workspace, exist_ok=True)
    os.chdir(workspace)

    # Drain any stale stdin/output/touch from a previous run
    while not _stdin_queue.empty():
        try:
            _stdin_queue.get_nowait()
        except _queue_mod.Empty:
            break
    while not _output_queue.empty():
        try:
            _output_queue.get_nowait()
        except _queue_mod.Empty:
            break
    while not _touch_queue.empty():
        try:
            _touch_queue.get_nowait()
        except _queue_mod.Empty:
            break

    old_stdout = sys.stdout
    old_stderr = sys.stderr
    old_stdin = sys.stdin

    sys.stdout = _QueueWriter("stdout")
    sys.stderr = _QueueWriter("stderr")
    sys.stdin = _BlockingStdin()

    exit_code = 0

    import asyncio

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    _original_asyncio_run = asyncio.run

    def _patched_run(coro, **kwargs):
        current_loop = asyncio.get_event_loop()
        if current_loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as pool:
                future = pool.submit(_original_asyncio_run, coro)
                return future.result()
        else:
            return current_loop.run_until_complete(coro)

    asyncio.run = _patched_run

    # Monkey-patch input() to flush prompt before reading
    import builtins
    _original_input = builtins.input

    def _patched_input(prompt=""):
        if _stop_requested.is_set():
            raise KeyboardInterrupt()
        if prompt:
            sys.stdout.write(prompt)
            sys.stdout.flush()
        return sys.stdin.readline().rstrip("\n")

    builtins.input = _patched_input

    # Monkey-patch time.sleep() to be interruptible by stop requests.
    # Splits long sleeps into short segments so we can check the flag.
    import time as _time_mod
    _original_sleep = _time_mod.sleep

    def _patched_sleep(seconds):
        if _stop_requested.is_set():
            raise KeyboardInterrupt()
        if seconds <= 0:
            return
        _SLICE = 0.2
        remaining = float(seconds)
        while remaining > 0:
            if _stop_requested.is_set():
                raise KeyboardInterrupt()
            chunk = min(remaining, _SLICE)
            _original_sleep(chunk)
            remaining -= chunk

    _time_mod.sleep = _patched_sleep

    # ── Auto-inject HTTP debug hook if env is configured ──
    _hook_module = None
    _hook_source = "none"
    if _injected_env_keys and os.environ.get('PYRUNNER_HTTP_HOOK_CONFIG'):
        try:
            # http_debug_hook.py lives in src/main/python/ alongside this file,
            # so Chaquopy packages it as a regular importable module.
            if 'http_debug_hook' in sys.modules:
                # Module already loaded from a previous run — just refresh config
                _hook_module = sys.modules['http_debug_hook']
                _hook_module._reload_config()
                _hook_module._init_hooks()
                _hook_source = "main (refreshed)"
            else:
                import http_debug_hook as _hook_module
                _hook_source = "main"
        except ImportError as _imp_err:
            # Fallback: inline hook
            try:
                _hook_code = _build_inline_hook()
                if _hook_code:
                    exec(_hook_code, {"__name__": "__http_hook__", "__builtins__": __builtins__})
                    _hook_source = "fallback"
            except Exception as _fb_err:
                pass
        except Exception as _other_err:
            pass

        # Diagnostic log — use special prefix so Flutter filters it from user output
        _cfg_body = 'unknown'
        try:
            import json as _dj
            _hc = _dj.loads(os.environ.get('PYRUNNER_HTTP_HOOK_CONFIG', '{}'))
            _cfg_body = str(_hc.get('record_response_body', '?'))
        except Exception:
            pass
        sys.stdout.write("__HOOK_DIAG__{\"source\": \"%s\", \"record_body\": \"%s\"}\n" % (_hook_source, _cfg_body))
        sys.stdout.flush()

    try:
        exec(code, {
            "__name__": "__main__",
            "__builtins__": __builtins__,
            "__stop_requested__": stop_requested,
        })
    except SystemExit as e:
        exit_code = e.code if isinstance(e.code, int) else 1
    except KeyboardInterrupt:
        exit_code = 1
    except Exception:
        traceback.print_exc(file=sys.stderr)
        exit_code = 1
    finally:
        # Clear stop flag so cleanup code runs normally
        _stop_requested.clear()

        sys.stdout.flush()
        sys.stderr.flush()

        sys.stdout = old_stdout
        sys.stderr = old_stderr
        sys.stdin = old_stdin
        builtins.input = _original_input
        asyncio.run = _original_asyncio_run
        _time_mod.sleep = _original_sleep
        # Unblock any readline() still waiting (e.g. script killed mid-input)
        _stdin_queue.put(_STDIN_STOP)
        _waiting_for_input = False
        # Stop any running scene game loop
        _touch_queue.put(_TOUCH_STOP)

        # Suppress ResourceWarning during cleanup
        warnings.filterwarnings("ignore", category=ResourceWarning)

        try:
            if loop is not None and not loop.is_closed():
                # 1. Cancel all pending tasks
                if hasattr(asyncio, 'all_tasks'):
                    pending = asyncio.all_tasks(loop)
                else:
                    pending = asyncio.Task.all_tasks(loop)
                for task in pending:
                    task.cancel()
                if pending:
                    loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))

                # 2. Shutdown async generators
                loop.run_until_complete(loop.shutdown_asyncgens())

                # 3. Shutdown default executor (Python 3.9+)
                if hasattr(loop, 'shutdown_default_executor'):
                    loop.run_until_complete(loop.shutdown_default_executor())

                # 4. Close all transports (underlying sockets/connections)
                # The event loop tracks transports internally via _transports
                if hasattr(loop, '_transports'):
                    for transport in list(loop._transports.values()):
                        if transport is not None:
                            try:
                                transport.close()
                            except Exception:
                                pass

                loop.close()
        except Exception:
            # Force close the loop even if cleanup fails
            try:
                if loop is not None and not loop.is_closed():
                    loop.close()
            except Exception:
                pass

        # 5. Clean up cached aiohttp sessions/connectors from sys.modules
        _cleanup_network_modules()

        # 6. Force garbage collection to trigger __del__ on abandoned objects
        # This closes any remaining unclosed sockets/transports
        gc.collect()
        gc.collect()  # Second pass for reference cycles

        # Restore ResourceWarning filter
        warnings.filterwarnings("default", category=ResourceWarning)

        # ── Clean up injected environment variables ──
        for k in _injected_env_keys:
            os.environ.pop(k, None)

    return {
        "stdout": "",
        "stderr": "",
        "exit_code": exit_code,
    }


def install_package(args):
    """Install a package using pip, with target set to our site-packages."""
    site_dir = _ensure_site_packages()
    import pip
    import json

    # Snapshot dist-info dirs before install
    def _snap():
        if not os.path.exists(site_dir): return set()
        return {e for e in os.listdir(site_dir) if e.endswith(('.dist-info', '.egg-info'))}
    before = _snap()

    full_args = list(args) + ["--target", site_dir]
    pip_result = pip.main(full_args)

    # Record which dist-infos were added by this install
    after = _snap()
    new_entries = after - before
    pkg_name = next((a for a in args if not a.startswith('-') and a != 'install'), '').split('==')[0].lower().replace('-', '_')

    _DEPS_FILE = os.path.join(os.environ.get('HOME', '/data/data/com.daozhang.py'), 'chaquopy/install_deps.json')
    _USER_FILE = os.path.join(os.environ.get('HOME', '/data/data/com.daozhang.py'), 'chaquopy/user_packages.json')
    if pkg_name and new_entries:
        try:
            deps = {}
            if os.path.exists(_DEPS_FILE):
                with open(_DEPS_FILE) as f:
                    deps = json.load(f)
            deps[pkg_name] = list(new_entries)
            with open(_DEPS_FILE, 'w') as f:
                json.dump(deps, f)
        except Exception:
            pass
    # Record user-initiated install with version
    if pkg_name:
        try:
            user_pkgs = {}
            if os.path.exists(_USER_FILE):
                with open(_USER_FILE) as f:
                    user_pkgs = json.load(f)
            # Find the actual installed version from dist-info
            version = 'unknown'
            if os.path.exists(site_dir):
                import pathlib
                from importlib.metadata import PathDistribution
                for entry in os.listdir(site_dir):
                    if entry.lower().replace('-','_').startswith(pkg_name) and entry.endswith('.dist-info'):
                        try:
                            dist = PathDistribution(pathlib.Path(os.path.join(site_dir, entry)))
                            version = dist.version or 'unknown'
                            break
                        except Exception:
                            pass
            user_pkgs[pkg_name] = version
            with open(_USER_FILE, 'w') as f:
                json.dump(user_pkgs, f)
        except Exception:
            pass

    # After installation, refresh sys.path and invalidate caches
    import importlib
    importlib.invalidate_caches()

    # Remove installed package from exclusion list if it was there
    if pkg_name:
        _UNINSTALLED_FILE = os.path.join(os.environ.get('HOME', '/data/data/com.daozhang.py'), 'chaquopy/uninstalled.txt')
        try:
            if os.path.exists(_UNINSTALLED_FILE):
                with open(_UNINSTALLED_FILE) as f:
                    lines = [l.strip() for l in f if l.strip() and l.strip() != pkg_name]
                with open(_UNINSTALLED_FILE, 'w') as f:
                    f.write('\n'.join(lines) + ('\n' if lines else ''))
        except Exception:
            pass

    # Make sure site_dir is at the front of sys.path
    if site_dir in sys.path:
        sys.path.remove(site_dir)
    sys.path.insert(0, site_dir)

    return pip_result


def verify_package(package_name):
    """Verify that a package can actually be imported after installation.
    Returns a dict with 'success' (bool) and 'message' (str).
    """
    _ensure_site_packages()
    import importlib
    importlib.invalidate_caches()

    # Normalize package name: aiohttp -> aiohttp, Pillow -> PIL, etc.
    # Most packages use lowercase with underscores as import name
    import_name = package_name.lower().replace("-", "_")

    # Common package name -> import name mappings
    name_mapping = {
        "pillow": "PIL",
        "scikit-learn": "sklearn",
        "pyyaml": "yaml",
        "python-dateutil": "dateutil",
        "beautifulsoup4": "bs4",
        "opencv-python": "cv2",
        "opencv-python-headless": "cv2",
        "pycryptodome": "Crypto",
    }

    actual_import = name_mapping.get(package_name.lower(), import_name)

    try:
        importlib.import_module(actual_import)
        return {"success": True, "message": "%s 可以正常使用" % package_name}
    except ImportError as e:
        return {
            "success": False,
            "message": "%s 安装文件存在但无法导入 (可能包含不兼容的C扩展): %s" % (package_name, str(e))
        }
    except Exception as e:
        return {
            "success": False,
            "message": "%s 导入时出错: %s" % (package_name, str(e))
        }


def uninstall_package(package_name):
    """Uninstall a package by removing its files from site-packages and clearing all caches.
    Works reliably for both build-time and runtime packages."""
    site_dir = _ensure_site_packages()
    import shutil
    import importlib
    import sys

    pkg_lower = package_name.lower().replace("-", "_")
    removed = False

    if not os.path.exists(site_dir):
        return False

    # 1. 删除匹配的文件和目录
    for entry in os.listdir(site_dir):
        entry_lower = entry.lower().replace("-", "_")
        is_match = (
            entry_lower == pkg_lower
            or entry_lower == pkg_lower + ".py"
            or (entry_lower.startswith(pkg_lower + "-")
                and (
                    entry_lower.endswith(".dist-info")
                    or entry_lower.endswith(".data")
                    or entry_lower.endswith(".egg-info")
                ))
        )
        if is_match:
            path = os.path.join(site_dir, entry)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.remove(path)
            removed = True

    # 2. 再次扫描更宽松的模式，确保无残留
    if os.path.exists(site_dir):
        for entry in os.listdir(site_dir):
            entry_lower = entry.lower().replace("-", "_")
            if (entry_lower.startswith(pkg_lower + "-") or entry_lower.startswith(pkg_lower + ".")) and (
                entry.endswith(".dist-info") or entry.endswith(".egg-info") or entry.endswith(".data")
            ):
                path = os.path.join(site_dir, entry)
                if os.path.isdir(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)
                removed = True

    # 3. 清理所有相关的 sys.modules 条目
    modules_to_remove = [
        key for key in list(sys.modules.keys())
        if key == pkg_lower or key.startswith(pkg_lower + ".")
    ]
    for key in modules_to_remove:
        del sys.modules[key]

    # 4. 清理 importlib 缓存
    importlib.invalidate_caches()

    # 5. 强制重建 pkg_resources.working_set（如果它在缓存中）
    try:
        import pkg_resources
        pkg_resources._initialize_master_working_set()
        # 清理 working_set 中可能的残留
        if hasattr(pkg_resources, 'working_set'):
            pkg_resources.working_set.entries = [e for e in pkg_resources.working_set.entries
                                                 if not (hasattr(e, 'name') and e.name.lower().replace('-', '_') == pkg_lower)]
    except Exception:
        pass

    # Remove from user_packages record
    _USER_FILE = os.path.join(os.environ.get('HOME', '/data/data/com.daozhang.py'), 'chaquopy/user_packages.json')
    try:
        import json as _json
        if os.path.exists(_USER_FILE):
            with open(_USER_FILE) as f:
                user_pkgs = _json.load(f)
            user_pkgs.pop(pkg_lower, None)
            with open(_USER_FILE, 'w') as f:
                _json.dump(user_pkgs, f)
    except Exception:
        pass

    # Also remove dependency dist-infos recorded during install
    import json
    _DEPS_FILE = os.path.join(os.environ.get('HOME', '/data/data/com.daozhang.py'), 'chaquopy/install_deps.json')
    if os.path.exists(_DEPS_FILE):
        try:
            with open(_DEPS_FILE) as f:
                deps = json.load(f)
            if pkg_lower in deps:
                import shutil as _shutil
                for entry in deps[pkg_lower]:
                    path = os.path.join(site_dir, entry)
                    if os.path.isdir(path):
                        _shutil.rmtree(path, ignore_errors=True)
                    elif os.path.exists(path):
                        os.remove(path)
                del deps[pkg_lower]
                with open(_DEPS_FILE, 'w') as f:
                    json.dump(deps, f)
        except Exception:
            pass

    # Record uninstalled package to exclusion file (survives metadata cache)
    _UNINSTALLED_FILE = os.path.join(os.environ.get('HOME', '/data/data/com.daozhang.py'), 'chaquopy/uninstalled.txt')
    try:
        existing = set()
        if os.path.exists(_UNINSTALLED_FILE):
            with open(_UNINSTALLED_FILE) as f:
                existing = set(l.strip() for l in f if l.strip())
        existing.add(pkg_lower)
        with open(_UNINSTALLED_FILE, 'w') as f:
            f.write('\n'.join(sorted(existing)) + '\n')
    except Exception:
        pass

    return removed


def list_packages():
    """List installed packages by directly scanning site-packages and using importlib.metadata.
    Returns accurate list without relying on pkg_resources cache."""
    _ensure_site_packages()
    import importlib
    import importlib.util
    import importlib.metadata
    importlib.invalidate_caches()
    if hasattr(importlib.metadata, '_DISTRIBUTION_CACHE'):
        importlib.metadata._DISTRIBUTION_CACHE.clear()
    try:
        importlib.metadata.packages_distributions.cache_clear()
    except Exception:
        pass

    # Load exclusion list (packages explicitly uninstalled at runtime)
    _UNINSTALLED_FILE = os.path.join(os.environ.get('HOME', '/data/data/com.daozhang.py'), 'chaquopy/uninstalled.txt')
    excluded = set()
    if os.path.exists(_UNINSTALLED_FILE):
        try:
            with open(_UNINSTALLED_FILE) as f:
                excluded = set(l.strip() for l in f if l.strip())
        except Exception:
            pass

    packages = []
    seen_names = set()

    # Scan ALL installed packages (builtin + user-installed) via importlib.metadata
    try:
        for dist in importlib.metadata.distributions():
            name = dist.metadata.get('Name') or dist.name
            if not name:
                continue
            norm = name.lower().replace('-', '_')
            if norm in seen_names or norm in excluded:
                continue
            seen_names.add(norm)
            packages.append({'name': name, 'version': dist.version or 'unknown'})
    except Exception:
        pass

    packages.sort(key=lambda p: p["name"].lower())
    return packages


def _get_package_version(package_path, package_name):
    """Try to get version from a package directory."""
    # Try reading __version__ from __init__.py
    init_file = os.path.join(package_path, "__init__.py")
    if os.path.exists(init_file):
        try:
            with open(init_file) as f:
                content = f.read()
            for line in content.split("\n"):
                line = line.strip()
                if line.startswith("__version__"):
                    # Extract version string
                    parts = line.split("=", 1)
                    if len(parts) == 2:
                        ver = parts[1].strip().strip("'\"")
                        if ver:
                            return ver
        except Exception:
            pass

    # Try VERSION or version.py file
    for vfile in ["VERSION", "version.py", "_version.py"]:
        vpath = os.path.join(package_path, vfile)
        if os.path.exists(vpath):
            try:
                with open(vpath) as f:
                    content = f.read().strip()
                if vfile == "VERSION":
                    return content.split("\n")[0].strip()
                # For .py files, look for __version__
                for line in content.split("\n"):
                    if "__version__" in line:
                        parts = line.split("=", 1)
                        if len(parts) == 2:
                            return parts[1].strip().strip("'\"")
            except Exception:
                pass

    return "unknown"
