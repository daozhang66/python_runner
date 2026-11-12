"""getpass for the script console of Python Runner.

The console's stdin is not a terminal, so the standard library's getpass can
neither switch echo off nor use /dev/tty: it falls back to a plain read and
prints ``GetPassWarning: Can not control echo on the terminal`` (and the prompt
goes to stderr, which the console shows as an error).

This version reads the answer the way ``input()`` does: the prompt appears
normally and the run console takes the answer. The app recognises a password
prompt and never writes the answer to its logs.
"""

import os

__all__ = ["getpass", "getuser", "GetPassWarning"]


class GetPassWarning(UserWarning):
    pass


def getpass(prompt="Password: ", stream=None):
    """Prompt for a password; the app's console collects the answer."""
    import builtins

    return builtins.input(prompt)


# Names the standard module also offers.
unix_getpass = getpass
win_getpass = getpass
fallback_getpass = getpass


def getuser():
    """Name of the user, from the environment or the password database."""
    for name in ("LOGNAME", "USER", "LNAME", "USERNAME"):
        user = os.environ.get(name)
        if user:
            return user
    try:
        import pwd

        return pwd.getpwuid(os.getuid())[0]
    except (ImportError, KeyError, OSError):
        return "user"
