 #!/usr/bin/env python3
import sys, os, json, time, hashlib, shutil, datetime

ADD = 0
DELETE = 1
COOLDOWN_SECONDS = 300  # 5 minutes per file
QUARANTINE_DIR = r"C:\RTGS_quarantine"
STATE_FILE = os.path.join(QUARANTINE_DIR, "quarantine_state.json")

# Paths to ignore from quarantine
IGNORE_PATHS = [
    STATE_FILE.lower()  # state file itself
]

def load_state():
    """Load quarantine state from JSON file."""
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                return json.load(f)
        except:
            return {}
    return {}

def save_state(state):
    """Save quarantine state to JSON file."""
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception as e:
        log_action(f"STATE_SAVE_ERROR: {e}")

def log_action(message):
    """Log messages to the Wazuh active-response log file."""
    with open(r"C:\Program Files (x86)\ossec-agent\active-response\active-responses.log", "a") as log:
        log.write(f"{datetime.datetime.now()}: {message}\n")

if __name__ == "__main__":
    data = json.loads(sys.stdin.readline())
    cmd = data.get("command")
    syscheck = data["parameters"]["alert"]["syscheck"]
    path = syscheck["path"]

    # Ignore quarantine folder & state file
    if path.lower().startswith(QUARANTINE_DIR.lower()) or path.lower() in IGNORE_PATHS:
        sys.exit(0)

    if cmd == "add":
        os.makedirs(QUARANTINE_DIR, exist_ok=True)

        state = load_state()
        now = time.time()

        # Cooldown check per file
        if path in state and now - state[path] < COOLDOWN_SECONDS:
            sys.exit(0)

        try:
            # Calculate file hash
            h1 = hashlib.sha256(open(path, "rb").read()).hexdigest()
        except Exception as e:
            log_action(f"ERROR_HASHING: {e}")
            sys.exit(1)

        basename = os.path.basename(path)
        dest = os.path.join(QUARANTINE_DIR, f"{basename}.quarantine.{int(time.time())}")

        try:
            shutil.move(path, dest)
        except Exception as e:
            log_action(f"DEFAIL {e}")
            sys.exit(1)

        # Update quarantine state
        state[path] = now
        save_state(state)

        # Notify Wazuh Manager
        control = json.dumps({
            "version": 1,
            "origin": {"name": "quarantine_rtgs", "module": "active-response"},
            "command": "check_keys",
            "parameters": {"keys": [dest]}
        })
        print(control)
        sys.stdout.flush()

        resp = json.loads(sys.stdin.readline())
        if resp.get("command") == "continue":
            log_action(f"quarantined {path}")
            time.sleep(120)  # Wait 2 minutes

            try:
                newh = hashlib.sha256(open(dest, "rb").read()).hexdigest()
            except Exception as e:
                log_action(f"ERROR_REHASHING: {e}")
                sys.exit(1)

            # Restore file only if unchanged
            if newh == h1:
                try:
                    shutil.move(dest, path)
                    log_action(f"restored {path}")
                except Exception as e:
                    log_action(f"RESTORE_FAIL {e}")

        sys.exit(0)

    elif cmd == "delete":
        sys.exit(0)