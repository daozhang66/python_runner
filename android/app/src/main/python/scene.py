# -*- coding: utf-8 -*-
"""
Pythonista-compatible scene module for Python Runner.

Provides a real-time graphics engine that serializes draw commands as JSON
and sends them through script_runner's output queue to Flutter for rendering.
"""
import json
import time
import queue as _queue_mod

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
PORTRAIT = 0
LANDSCAPE = 1
PORTRAIT_UPSIDE_DOWN = 2
LANDSCAPE_RIGHT = 3

# ---------------------------------------------------------------------------
# Helper classes
# ---------------------------------------------------------------------------

class Size:
    __slots__ = ('w', 'h')
    def __init__(self, w=0, h=0):
        self.w = w
        self.h = h
    def __repr__(self):
        return f'Size(w={self.w}, h={self.h})'

class Point:
    __slots__ = ('x', 'y')
    def __init__(self, x=0, y=0):
        self.x = x
        self.y = y
    def __iter__(self):
        yield self.x
        yield self.y
    def __repr__(self):
        return f'Point(x={self.x}, y={self.y})'

class Rect:
    __slots__ = ('x', 'y', 'w', 'h')
    def __init__(self, x=0, y=0, w=0, h=0):
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    def __contains__(self, point):
        if isinstance(point, Point):
            px, py = point.x, point.y
        elif isinstance(point, (tuple, list)):
            px, py = point[0], point[1]
        else:
            return False
        return self.x <= px <= self.x + self.w and self.y <= py <= self.y + self.h
    def __iter__(self):
        yield self.x
        yield self.y
        yield self.w
        yield self.h
    def __repr__(self):
        return f'Rect(x={self.x}, y={self.y}, w={self.w}, h={self.h})'

class Touch:
    __slots__ = ('location', 'prev_location', 'touch_id')
    def __init__(self, location, prev_location=None, touch_id=0):
        self.location = location
        self.prev_location = prev_location or location
        self.touch_id = touch_id

class Color:
    __slots__ = ('r', 'g', 'b', 'a')
    def __init__(self, r=0, g=0, b=0, a=1.0):
        self.r = r; self.g = g; self.b = b; self.a = a

# ---------------------------------------------------------------------------
# Module-level drawing state
# ---------------------------------------------------------------------------
_frame_commands = []
_current_fill = (1.0, 1.0, 1.0, 1.0)   # default white fill
_current_stroke = None
_current_stroke_weight = 1.0
_current_tint = (1.0, 1.0, 1.0, 1.0)

_scene_instance = None
_scene_running = False

class _SceneStop(Exception):
    """Raised to cleanly exit the game loop."""
    pass

# ---------------------------------------------------------------------------
# Drawing functions (Pythonista API)
# ---------------------------------------------------------------------------

def background(r, g, b):
    """Fill the entire screen with a solid color."""
    _frame_commands.append({"c": "bg", "r": r, "g": g, "b": b})

def fill(r, g, b, a=1.0):
    """Set the fill color for subsequent shapes."""
    global _current_fill
    _current_fill = (r, g, b, a)

def no_fill():
    """Disable filling for subsequent shapes."""
    global _current_fill
    _current_fill = None

def stroke(r, g, b, a=1.0):
    """Set the stroke color for subsequent shapes."""
    global _current_stroke
    _current_stroke = (r, g, b, a)

def no_stroke():
    """Disable stroke for subsequent shapes."""
    global _current_stroke
    _current_stroke = None

def stroke_weight(w):
    """Set the stroke width."""
    global _current_stroke_weight
    _current_stroke_weight = w

def tint(r, g, b, a=1.0):
    """Set the tint color (used for text coloring)."""
    global _current_tint
    _current_tint = (r, g, b, a)

def no_tint():
    """Reset tint."""
    global _current_tint
    _current_tint = None

def rect(x, y, w, h):
    """Draw a rectangle."""
    cmd = {"c": "r", "x": x, "y": y, "w": w, "h": h}
    if _current_fill is not None:
        cmd["fl"] = list(_current_fill)
    if _current_stroke is not None:
        cmd["sk"] = list(_current_stroke)
        cmd["sw"] = _current_stroke_weight
    _frame_commands.append(cmd)

def ellipse(x, y, w, h):
    """Draw an ellipse."""
    cmd = {"c": "e", "x": x, "y": y, "w": w, "h": h}
    if _current_fill is not None:
        cmd["fl"] = list(_current_fill)
    if _current_stroke is not None:
        cmd["sk"] = list(_current_stroke)
        cmd["sw"] = _current_stroke_weight
    _frame_commands.append(cmd)

def line(x1, y1, x2, y2):
    """Draw a line."""
    cmd = {"c": "l", "x1": x1, "y1": y1, "x2": x2, "y2": y2}
    sk = _current_stroke or (1.0, 1.0, 1.0, 1.0)
    cmd["sk"] = list(sk)
    cmd["sw"] = _current_stroke_weight
    _frame_commands.append(cmd)

def text(txt, font_name='Helvetica', font_size=16, x=0, y=0, alignment=5):
    """Draw text at position (x, y)."""
    cmd = {"c": "t", "s": str(txt), "f": font_name, "z": font_size, "x": x, "y": y, "a": alignment}
    if _current_tint is not None:
        cmd["fl"] = list(_current_tint)
    elif _current_fill is not None:
        cmd["fl"] = list(_current_fill)
    else:
        cmd["fl"] = [1.0, 1.0, 1.0, 1.0]
    _frame_commands.append(cmd)

def image(name, x, y, w=None, h=None):
    """Placeholder for image drawing (not yet supported)."""
    # Draw a colored rect with text label as placeholder
    old_fill = _current_fill
    fill(0.5, 0.5, 0.5, 0.5)
    _w = w or 64
    _h = h or 64
    rect(x, y, _w, _h)
    fill(*old_fill) if old_fill else no_fill()

# ---------------------------------------------------------------------------
# Scene base class
# ---------------------------------------------------------------------------

class Scene:
    def __init__(self):
        self.size = Size(0, 0)
        self.t = 0.0
        self.dt = 0.0
        self._frame_count = 0

    def setup(self):
        pass

    def update(self):
        pass

    def draw(self):
        pass

    def touch_began(self, touch):
        pass

    def touch_moved(self, touch):
        pass

    def touch_ended(self, touch):
        pass

    def stop(self):
        pass

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _wait_for_size(scene_obj, touch_queue, timeout=5.0):
    """Block until Flutter sends screen dimensions via touch_queue."""
    import script_runner
    deadline = time.time() + timeout
    pending = []
    while time.time() < deadline:
        if not _scene_running:
            break
        try:
            msg = touch_queue.get(timeout=0.1)
            if msg is script_runner._TOUCH_STOP:
                raise _SceneStop()
            if isinstance(msg, dict) and msg.get('type') == 'size':
                w = msg.get('w', 375)
                h = msg.get('h', 667)
                scene_obj.size = Size(w, h)
                return
            else:
                pending.append(msg)
        except _queue_mod.Empty:
            continue
    # Timeout: use default size
    scene_obj.size = Size(375, 667)
    # Put back any non-size messages
    for msg in pending:
        touch_queue.put(msg)

def _process_touches(scene_obj, touch_queue, stop_sentinel):
    """Drain touch_queue and dispatch to scene handlers."""
    while True:
        try:
            msg = touch_queue.get_nowait()
        except _queue_mod.Empty:
            break
        if msg is stop_sentinel:
            raise _SceneStop()
        if not isinstance(msg, dict):
            continue
        t = msg.get('type', '')
        if t == 'size':
            scene_obj.size = Size(msg.get('w', scene_obj.size.w),
                                   msg.get('h', scene_obj.size.h))
            continue
        loc = Point(msg.get('x', 0), msg.get('y', 0))
        prev = Point(msg.get('px', loc.x), msg.get('py', loc.y))
        touch = Touch(loc, prev, msg.get('id', 0))
        try:
            if t == 'began':
                scene_obj.touch_began(touch)
            elif t == 'moved':
                scene_obj.touch_moved(touch)
            elif t == 'ended':
                scene_obj.touch_ended(touch)
        except Exception:
            import traceback
            traceback.print_exc()

# ---------------------------------------------------------------------------
# run() — the game loop
# ---------------------------------------------------------------------------

def run(scene_obj, orientation=PORTRAIT, frame_interval=1, anti_alias=False, show_fps=False):
    """Start the scene game loop."""
    global _scene_instance, _scene_running, _frame_commands
    global _current_fill, _current_stroke, _current_stroke_weight, _current_tint

    import script_runner

    _scene_instance = scene_obj
    _scene_running = True

    # Reset drawing state
    _current_fill = (1.0, 1.0, 1.0, 1.0)
    _current_stroke = None
    _current_stroke_weight = 1.0
    _current_tint = (1.0, 1.0, 1.0, 1.0)

    # Send init message
    init_msg = json.dumps({"orientation": orientation}, separators=(',', ':'))
    script_runner._output_queue.put(("__scene_init__", init_msg))

    target_fps = 30
    frame_time = 1.0 / target_fps

    try:
        # Wait for Flutter to reply with screen dimensions
        _wait_for_size(scene_obj, script_runner._touch_queue)

        # Run setup
        scene_obj.setup()

        last_time = time.time()
        start_time = last_time

        while _scene_running:
            now = time.time()
            scene_obj.dt = now - last_time
            scene_obj.t = now - start_time
            scene_obj._frame_count += 1
            last_time = now

            # Process pending touch events
            _process_touches(scene_obj, script_runner._touch_queue, script_runner._TOUCH_STOP)

            # Clear frame commands
            _frame_commands = []

            # User code
            scene_obj.update()
            scene_obj.draw()

            # Send frame
            if _frame_commands:
                frame_json = json.dumps(_frame_commands, separators=(',', ':'))
                script_runner._output_queue.put(("__scene_frame__", frame_json))

            # Frame rate limiting
            elapsed = time.time() - now
            sleep_time = frame_time - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except _SceneStop:
        pass
    except Exception:
        import traceback
        traceback.print_exc()
    finally:
        _scene_running = False
        try:
            scene_obj.stop()
        except Exception:
            pass
        # Signal Flutter to close scene view
        script_runner._output_queue.put(("__scene_end__", ""))


def stop():
    """Stop the running scene from outside."""
    global _scene_running
    _scene_running = False
