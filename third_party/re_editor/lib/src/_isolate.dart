part of re_editor;

typedef IsolateRunnable<Req, Res> = Res Function(Req req);
typedef IsolateCallback<Res> = void Function(Res res);

class _IsolateTasker<Req, Res> {
  final String name;
  late bool _closed;
  final IsolateRunnable<Req, Res> _runnable;

  _IsolateTasker(this.name, IsolateRunnable<Req, Res> runnable)
      : _runnable = runnable {
    _closed = false;
  }

  void run(Req req, IsolateCallback<Res> callback) async {
    if (_closed) {
      return;
    }
    final Res message = await compute(_runnable, req, debugLabel: name);
    if (_closed) {
      return;
    }
    callback(message);
  }

  void close() {
    _closed = true;
  }
}
