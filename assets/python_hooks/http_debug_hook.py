"""
HTTP Debug Hook for Python Runner
Monkey-patches requests, httpx, urllib3, aiohttp, urllib.request to intercept
and optionally override HTTP requests.
Communicates captured data back to Flutter via stdout with a special prefix.
"""
import os
import sys
import json
import time
import uuid
import threading
try:
    from urllib.parse import urlparse
except ImportError:
    from urlparse import urlparse

# Thread-local flag to suppress urllib3 recording when called from requests/httpx
_tls = threading.local()

# ── Configuration from environment ──
# Use a mutable dict so hook closures always read the latest config,
# even when the module is re-imported but patched functions persist.
_CFG = {}

def _reload_config():
    """(Re)load configuration from environment. Called at import time and
    can be called again if env vars change between runs."""
    raw = os.environ.get('PYRUNNER_HTTP_HOOK_CONFIG', '{}')
    try:
        hc = json.loads(raw)
    except Exception:
        hc = {}
    _CFG['override_enabled'] = hc.get('override_enabled', False)
    _CFG['record_requests'] = hc.get('record_requests', True)
    _CFG['record_body'] = hc.get('record_response_body', False)
    _CFG['global_ua'] = hc.get('global_user_agent', '')
    _CFG['global_cookie'] = hc.get('global_cookie', '')
    _CFG['default_timeout'] = hc.get('default_timeout', 30)
    _CFG['follow_redirects'] = hc.get('follow_redirects', True)
    _CFG['force_proxy'] = hc.get('force_proxy', False)
    _CFG['domain_rules'] = hc.get('domain_rules', [])
    _CFG['proxy_host'] = os.environ.get('PYRUNNER_PROXY_HOST', '')
    _CFG['proxy_port'] = os.environ.get('PYRUNNER_PROXY_PORT', '')
    _CFG['ssl_verify'] = os.environ.get('PYRUNNER_SSL_VERIFY', '1') == '1'
    _CFG['body_limit'] = 128 * 1024
    raw_headers = hc.get('global_headers', '')
    try:
        _CFG['global_headers'] = json.loads(raw_headers) if raw_headers else {}
    except Exception:
        _CFG['global_headers'] = {}

_reload_config()

# ── Record count limit per script run ──
_record_count = 0
_MAX_RECORDS_PER_SCRIPT = 5000


def _reset_record_count():
    """Reset record counter — called from script_runner at start of each run."""
    global _record_count
    _record_count = 0


def _get_proxy_dict():
    if not _CFG['proxy_host'] or not _CFG['proxy_port']:
        return None
    proxy_url = f"http://{_CFG['proxy_host']}:{_CFG['proxy_port']}"
    return {"http": proxy_url, "https": proxy_url, "http://": proxy_url, "https://": proxy_url}


def _match_domain_rule(url):
    """Find the first matching domain rule for a URL."""
    rules = _CFG.get('domain_rules', [])
    if not rules:
        return None
    try:
        host = urlparse(url).hostname or ''
        host_lower = host.lower()
        for rule in rules:
            pattern = rule.get('domain', '').lower().strip()
            if not pattern:
                continue
            # Support wildcard: *.example.com or exact match
            if pattern.startswith('*.'):
                suffix = pattern[2:]
                if host_lower == suffix or host_lower.endswith('.' + suffix):
                    return rule
            elif host_lower == pattern or host_lower.endswith('.' + pattern):
                return rule
    except Exception:
        pass
    return None


def _send_record(record):
    """Send a captured HTTP record to Flutter via special log line."""
    global _record_count
    if not _CFG['record_requests']:
        return
    _record_count += 1
    if _record_count > _MAX_RECORDS_PER_SCRIPT:
        if _record_count == _MAX_RECORDS_PER_SCRIPT + 1:
            try:
                print(f"__HTTP_RECORD__{{\"note\": \"HTTP 记录已达上限 {_MAX_RECORDS_PER_SCRIPT} 条\"}}", flush=True)
            except Exception:
                pass
        return
    try:
        payload = json.dumps(record, ensure_ascii=False, default=str)
        print(f"__HTTP_RECORD__{payload}", flush=True)
    except Exception:
        pass


def _apply_overrides_to_headers(headers, library_name, url=None):
    """Apply global overrides and domain-specific rules to request headers."""
    if not _CFG['override_enabled']:
        return headers
    if headers is None:
        headers = {}
    if hasattr(headers, 'copy'):
        headers = headers.copy()
    else:
        headers = dict(headers)
    # Global overrides
    if _CFG['global_ua']:
        headers['User-Agent'] = _CFG['global_ua']
    if _CFG['global_cookie']:
        headers['Cookie'] = _CFG['global_cookie']
    if _CFG['global_headers']:
        for k, v in _CFG['global_headers'].items():
            headers[k] = v
    # Domain-specific overrides (higher priority)
    if url:
        rule = _match_domain_rule(url)
        if rule:
            if rule.get('user_agent'):
                headers['User-Agent'] = rule['user_agent']
            if rule.get('cookie'):
                headers['Cookie'] = rule['cookie']
            rule_headers = rule.get('headers')
            if rule_headers and isinstance(rule_headers, dict):
                for k, v in rule_headers.items():
                    headers[k] = v
    return headers


def _detect_content_type(headers):
    """Extract Content-Type from response headers."""
    if headers is None:
        return None
    try:
        if isinstance(headers, dict):
            ct = headers.get('Content-Type') or headers.get('content-type')
        else:
            ct = None
            for k, v in dict(headers).items():
                if k.lower() == 'content-type':
                    ct = v
                    break
        if ct:
            return ct.split(';')[0].strip().lower()
    except Exception:
        pass
    return None


def _safe_body_preview(body, response_headers=None):
    """Capture response body for preview.
    - For image/* content types: full base64 encode (no size limit)
    - For other types: use configured body_limit (default 2KB) to keep memory low
    """
    if body is None:
        return None
    try:
        # Check if this is an image response
        ct = _detect_content_type(response_headers)
        if ct and ct.startswith('image/'):
            if isinstance(body, bytes) and len(body) > 0:
                import base64
                return 'data:' + ct + ';base64,' + base64.b64encode(body).decode('ascii')
            return None

        # Non-image: truncate to limit
        limit = _CFG.get('body_limit', 2048)
        if isinstance(body, bytes):
            if len(body) == 0:
                return None
            text = body[:limit].decode('utf-8', errors='replace')
        elif isinstance(body, str):
            if len(body) == 0:
                return None
            text = body[:limit]
        else:
            text = str(body)[:limit]
        if len(text) >= limit:
            text += '... (truncated)'
        return text
    except Exception:
        return None


def _safe_headers_dict(headers):
    """Convert various header types to a plain dict."""
    if headers is None:
        return {}
    try:
        if isinstance(headers, dict):
            return {str(k): str(v) for k, v in headers.items()}
        return {str(k): str(v) for k, v in dict(headers).items()}
    except Exception:
        return {}


# ══════════════════════════════════════════
#  Hook: requests
# ══════════════════════════════════════════
_HOOKED_REQUESTS = False

def _hook_requests():
    global _HOOKED_REQUESTS
    try:
        import requests
        from requests import Session
    except ImportError:
        return

    # Prevent double-patching across re-imports
    if _HOOKED_REQUESTS or getattr(Session.send, '_pyrunner_hooked', False):
        return
    _HOOKED_REQUESTS = True

    _original_send = Session.send

    def _patched_send(self, request, **kwargs):
        record_id = str(uuid.uuid4())[:8]
        start_time = time.time()
        ts_ms = int(start_time * 1000)

        # Suppress urllib3 hook while inside requests hook
        _tls._in_higher_hook = True
        try:
            # Apply overrides
            if _CFG['override_enabled']:
                request.headers = _apply_overrides_to_headers(
                    dict(request.headers), 'requests', url=request.url)
                if _CFG['default_timeout'] and 'timeout' not in kwargs:
                    kwargs['timeout'] = _CFG['default_timeout']
                if not _CFG['follow_redirects']:
                    kwargs['allow_redirects'] = False
                if not _CFG['ssl_verify']:
                    kwargs['verify'] = False
                proxies = _get_proxy_dict()
                if _CFG['force_proxy'] and proxies and 'proxies' not in kwargs:
                    kwargs['proxies'] = proxies

            used_proxy = bool(kwargs.get('proxies') or
                              getattr(self, 'proxies', None))
            ssl_v = kwargs.get('verify', True)

            record = {
                'id': record_id,
                'timestamp': ts_ms,
                'method': request.method,
                'url': request.url,
                'request_headers': _safe_headers_dict(request.headers),
                'request_body': _safe_body_preview(request.body) if _CFG['record_body'] and request.body else None,
                'used_proxy': used_proxy,
                'ssl_verify': ssl_v is not False,
                'library': 'requests',
            }

            try:
                response = _original_send(self, request, **kwargs)
                elapsed_ms = int((time.time() - start_time) * 1000)
                record['status_code'] = response.status_code
                record['response_headers'] = _safe_headers_dict(response.headers)
                if _CFG['record_body']:
                    try:
                        record['response_body_preview'] = _safe_body_preview(response.content, response.headers)
                    except Exception:
                        pass
                record['duration_ms'] = elapsed_ms
                _send_record(record)
                return response
            except Exception as e:
                elapsed_ms = int((time.time() - start_time) * 1000)
                etype = type(e).__name__
                record['error_type'] = etype
                record['error_message'] = str(e)[:500]
                record['duration_ms'] = elapsed_ms
                _send_record(record)
                raise
        finally:
            _tls._in_higher_hook = False

    _patched_send._pyrunner_hooked = True
    Session.send = _patched_send


# ══════════════════════════════════════════
#  Hook: httpx
# ══════════════════════════════════════════
_HOOKED_HTTPX = False

def _hook_httpx():
    global _HOOKED_HTTPX
    try:
        import httpx
    except ImportError:
        return

    if _HOOKED_HTTPX:
        return
    _HOOKED_HTTPX = True

    # Hook sync Client
    if hasattr(httpx, 'Client') and not getattr(httpx.Client.send, '_pyrunner_hooked', False):
        _original_client_send = httpx.Client.send

        def _patched_client_send(self, request, **kwargs):
            record_id = str(uuid.uuid4())[:8]
            start_time = time.time()
            ts_ms = int(start_time * 1000)

            _tls._in_higher_hook = True
            try:
                if _CFG['override_enabled']:
                    for k, v in _apply_overrides_to_headers({}, 'httpx', url=str(request.url)).items():
                        request.headers[k] = v

                record = {
                    'id': record_id,
                    'timestamp': ts_ms,
                    'method': str(request.method),
                    'url': str(request.url),
                    'request_headers': _safe_headers_dict(request.headers),
                    'request_body': _safe_body_preview(request.content) if _CFG['record_body'] and request.content else None,
                    'used_proxy': False,
                    'ssl_verify': True,
                    'library': 'httpx',
                }

                try:
                    response = _original_client_send(self, request, **kwargs)
                    elapsed_ms = int((time.time() - start_time) * 1000)
                    record['status_code'] = response.status_code
                    record['response_headers'] = _safe_headers_dict(response.headers)
                    if _CFG['record_body']:
                        try:
                            record['response_body_preview'] = _safe_body_preview(response.content, response.headers)
                        except Exception:
                            pass
                    record['duration_ms'] = elapsed_ms
                    _send_record(record)
                    return response
                except Exception as e:
                    elapsed_ms = int((time.time() - start_time) * 1000)
                    record['error_type'] = type(e).__name__
                    record['error_message'] = str(e)[:500]
                    record['duration_ms'] = elapsed_ms
                    _send_record(record)
                    raise
            finally:
                _tls._in_higher_hook = False

        _patched_client_send._pyrunner_hooked = True
        httpx.Client.send = _patched_client_send

    # Hook async Client
    if hasattr(httpx, 'AsyncClient') and not getattr(httpx.AsyncClient.send, '_pyrunner_hooked', False):
        _original_async_send = httpx.AsyncClient.send

        async def _patched_async_send(self, request, **kwargs):
            record_id = str(uuid.uuid4())[:8]
            start_time = time.time()
            ts_ms = int(start_time * 1000)

            _tls._in_higher_hook = True
            try:
                if _CFG['override_enabled']:
                    for k, v in _apply_overrides_to_headers({}, 'httpx', url=str(request.url)).items():
                        request.headers[k] = v

                record = {
                    'id': record_id,
                    'timestamp': ts_ms,
                    'method': str(request.method),
                    'url': str(request.url),
                    'request_headers': _safe_headers_dict(request.headers),
                    'request_body': _safe_body_preview(request.content) if _CFG['record_body'] and request.content else None,
                    'used_proxy': False,
                    'ssl_verify': True,
                    'library': 'httpx-async',
                }

                try:
                    response = await _original_async_send(self, request, **kwargs)
                    elapsed_ms = int((time.time() - start_time) * 1000)
                    record['status_code'] = response.status_code
                    record['response_headers'] = _safe_headers_dict(response.headers)
                    if _CFG['record_body']:
                        try:
                            record['response_body_preview'] = _safe_body_preview(response.content, response.headers)
                        except Exception:
                            pass
                    record['duration_ms'] = elapsed_ms
                    _send_record(record)
                    return response
                except Exception as e:
                    elapsed_ms = int((time.time() - start_time) * 1000)
                    record['error_type'] = type(e).__name__
                    record['error_message'] = str(e)[:500]
                    record['duration_ms'] = elapsed_ms
                    _send_record(record)
                    raise
            finally:
                _tls._in_higher_hook = False

        _patched_async_send._pyrunner_hooked = True
        httpx.AsyncClient.send = _patched_async_send


# ══════════════════════════════════════════
#  Hook: urllib3
# ══════════════════════════════════════════
_HOOKED_URLLIB3 = False

def _hook_urllib3():
    global _HOOKED_URLLIB3
    try:
        import urllib3
        from urllib3 import HTTPConnectionPool
    except ImportError:
        return

    if _HOOKED_URLLIB3 or getattr(HTTPConnectionPool.urlopen, '_pyrunner_hooked', False):
        return
    _HOOKED_URLLIB3 = True

    _original_urlopen = HTTPConnectionPool.urlopen

    def _patched_urlopen(self, method, url, body=None, headers=None, **kwargs):
        # Skip recording if called from within requests/httpx hook
        if getattr(_tls, '_in_higher_hook', False):
            return _original_urlopen(self, method, url, body=body, headers=headers, **kwargs)

        record_id = str(uuid.uuid4())[:8]
        start_time = time.time()
        ts_ms = int(start_time * 1000)

        full_url = f"{self.scheme}://{self.host}:{self.port}{url}" if hasattr(self, 'scheme') else url

        if _CFG['override_enabled']:
            headers = _apply_overrides_to_headers(headers or {}, 'urllib3', url=full_url)
            if _CFG['default_timeout'] and 'timeout' not in kwargs:
                kwargs['timeout'] = _CFG['default_timeout']
            if not _CFG['follow_redirects']:
                kwargs['redirect'] = False

        record = {
            'id': record_id,
            'timestamp': ts_ms,
            'method': method,
            'url': full_url,
            'request_headers': _safe_headers_dict(headers),
            'request_body': _safe_body_preview(body) if _CFG['record_body'] and body else None,
            'used_proxy': False,
            'ssl_verify': True,
            'library': 'urllib3',
        }

        try:
            response = _original_urlopen(self, method, url, body=body, headers=headers, **kwargs)
            elapsed_ms = int((time.time() - start_time) * 1000)
            record['status_code'] = response.status
            record['response_headers'] = _safe_headers_dict(response.headers)
            if _CFG['record_body']:
                try:
                    record['response_body_preview'] = _safe_body_preview(response.data, response.headers)
                except Exception:
                    pass
            record['duration_ms'] = elapsed_ms
            _send_record(record)
            return response
        except Exception as e:
            elapsed_ms = int((time.time() - start_time) * 1000)
            record['error_type'] = type(e).__name__
            record['error_message'] = str(e)[:500]
            record['duration_ms'] = elapsed_ms
            _send_record(record)
            raise

    _patched_urlopen._pyrunner_hooked = True
    HTTPConnectionPool.urlopen = _patched_urlopen


# ══════════════════════════════════════════
#  Hook: aiohttp
# ══════════════════════════════════════════
_HOOKED_AIOHTTP = False

def _hook_aiohttp():
    global _HOOKED_AIOHTTP
    try:
        import aiohttp
    except ImportError:
        return

    if not hasattr(aiohttp, 'ClientSession'):
        return

    if _HOOKED_AIOHTTP or getattr(aiohttp.ClientSession._request, '_pyrunner_hooked', False):
        return
    _HOOKED_AIOHTTP = True

    _original_request = aiohttp.ClientSession._request

    async def _patched_request(self, method, url, **kwargs):
        record_id = str(uuid.uuid4())[:8]
        start_time = time.time()
        ts_ms = int(start_time * 1000)
        str_url = str(url)

        if _CFG['override_enabled']:
            headers = kwargs.get('headers') or {}
            if hasattr(headers, 'copy'):
                headers = dict(headers)
            else:
                headers = dict(headers) if headers else {}
            headers = _apply_overrides_to_headers(headers, 'aiohttp', url=str_url)
            kwargs['headers'] = headers
            if _CFG['default_timeout'] and 'timeout' not in kwargs:
                try:
                    kwargs['timeout'] = aiohttp.ClientTimeout(total=_CFG['default_timeout'])
                except Exception:
                    pass
            if not _CFG['follow_redirects']:
                kwargs['allow_redirects'] = False
            if not _CFG['ssl_verify']:
                kwargs['ssl'] = False
            if _CFG['force_proxy']:
                proxy_dict = _get_proxy_dict()
                if proxy_dict and 'proxy' not in kwargs:
                    kwargs['proxy'] = proxy_dict.get('http', '')

        req_headers = _safe_headers_dict(kwargs.get('headers'))
        req_body = None
        if _CFG['record_body']:
            if kwargs.get('data'):
                req_body = _safe_body_preview(kwargs['data'])
            elif kwargs.get('json'):
                try:
                    req_body = json.dumps(kwargs['json'], ensure_ascii=False)[:_CFG['body_limit']]
                except Exception:
                    pass

        record = {
            'id': record_id,
            'timestamp': ts_ms,
            'method': method.upper(),
            'url': str_url,
            'request_headers': req_headers,
            'request_body': req_body,
            'used_proxy': bool(kwargs.get('proxy')),
            'ssl_verify': kwargs.get('ssl') is not False,
            'library': 'aiohttp',
        }

        try:
            response = await _original_request(self, method, url, **kwargs)
            elapsed_ms = int((time.time() - start_time) * 1000)
            record['status_code'] = response.status
            record['response_headers'] = _safe_headers_dict(response.headers)
            if _CFG['record_body']:
                try:
                    body_bytes = await response.read()
                    record['response_body_preview'] = _safe_body_preview(body_bytes, response.headers)
                except Exception:
                    pass
            record['duration_ms'] = elapsed_ms
            _send_record(record)
            return response
        except Exception as e:
            elapsed_ms = int((time.time() - start_time) * 1000)
            record['error_type'] = type(e).__name__
            record['error_message'] = str(e)[:500]
            record['duration_ms'] = elapsed_ms
            _send_record(record)
            raise

    _patched_request._pyrunner_hooked = True
    aiohttp.ClientSession._request = _patched_request


# ══════════════════════════════════════════
#  Hook: urllib.request
# ══════════════════════════════════════════
_HOOKED_URLLIB_REQUEST = False

def _hook_urllib_request():
    global _HOOKED_URLLIB_REQUEST
    try:
        import urllib.request
    except ImportError:
        return

    if _HOOKED_URLLIB_REQUEST or getattr(urllib.request.urlopen, '_pyrunner_hooked', False):
        return
    _HOOKED_URLLIB_REQUEST = True

    _original_urlopen = urllib.request.urlopen

    def _patched_urlopen(url, data=None, timeout=None, **kwargs):
        record_id = str(uuid.uuid4())[:8]
        start_time = time.time()
        ts_ms = int(start_time * 1000)

        # Determine URL string and headers from Request object or string
        if isinstance(url, urllib.request.Request):
            req_obj = url
            str_url = req_obj.full_url
            method = req_obj.get_method()
            req_headers = _safe_headers_dict(dict(req_obj.header_items()))
            if _CFG['override_enabled']:
                overridden = _apply_overrides_to_headers(
                    dict(req_obj.header_items()), 'urllib', url=str_url)
                for k in list(req_obj.headers.keys()):
                    del req_obj.headers[k]
                for k in list(req_obj.unredirected_hdrs.keys()):
                    del req_obj.unredirected_hdrs[k]
                for k, v in overridden.items():
                    req_obj.add_header(k, v)
                req_headers = _safe_headers_dict(overridden)
        else:
            str_url = str(url)
            method = 'POST' if data else 'GET'
            req_headers = {}
            if _CFG['override_enabled']:
                req_obj = urllib.request.Request(str_url, data=data)
                overridden = _apply_overrides_to_headers({}, 'urllib', url=str_url)
                for k, v in overridden.items():
                    req_obj.add_header(k, v)
                req_headers = _safe_headers_dict(overridden)
                url = req_obj

        if timeout is None and _CFG['override_enabled'] and _CFG['default_timeout']:
            timeout = _CFG['default_timeout']

        record = {
            'id': record_id,
            'timestamp': ts_ms,
            'method': method,
            'url': str_url,
            'request_headers': req_headers,
            'request_body': _safe_body_preview(data) if _CFG['record_body'] and data else None,
            'used_proxy': False,
            'ssl_verify': _CFG['ssl_verify'],
            'library': 'urllib',
        }

        try:
            if timeout is not None:
                response = _original_urlopen(url, data=data, timeout=timeout, **kwargs)
            else:
                response = _original_urlopen(url, data=data, **kwargs)
            elapsed_ms = int((time.time() - start_time) * 1000)
            record['status_code'] = response.getcode()
            record['response_headers'] = _safe_headers_dict(dict(response.headers))
            if _CFG['record_body']:
                try:
                    body = response.read()
                    record['response_body_preview'] = _safe_body_preview(body, dict(response.headers))
                    import io
                    response = _UrllibResponseWrapper(response, body)
                except Exception:
                    pass
            record['duration_ms'] = elapsed_ms
            _send_record(record)
            return response
        except Exception as e:
            elapsed_ms = int((time.time() - start_time) * 1000)
            record['error_type'] = type(e).__name__
            record['error_message'] = str(e)[:500]
            record['duration_ms'] = elapsed_ms
            _send_record(record)
            raise

    _patched_urlopen._pyrunner_hooked = True
    urllib.request.urlopen = _patched_urlopen


class _UrllibResponseWrapper:
    """Wrapper that allows re-reading response body after we consumed it for preview."""
    def __init__(self, original, body_bytes):
        import io
        self._original = original
        self._body = body_bytes
        self._stream = io.BytesIO(body_bytes)

    def read(self, n=-1):
        return self._stream.read(n)

    def readline(self):
        return self._stream.readline()

    def readlines(self):
        return self._stream.readlines()

    def getcode(self):
        return self._original.getcode()

    def geturl(self):
        return self._original.geturl()

    @property
    def headers(self):
        return self._original.headers

    @property
    def status(self):
        return self._original.status

    @property
    def reason(self):
        return self._original.reason

    def info(self):
        return self._original.info()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self._original.close()

    def close(self):
        self._original.close()


# ══════════════════════════════════════════
#  Initialize all hooks
# ══════════════════════════════════════════
def _init_hooks():
    if not _CFG['record_requests'] and not _CFG['override_enabled']:
        return
    _hook_requests()
    _hook_httpx()
    _hook_urllib3()
    _hook_aiohttp()
    _hook_urllib_request()

# Auto-initialize when imported
_init_hooks()
