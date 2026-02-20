import sys
import os
import json
import logging

# Path to upstream nicotine+ submodule
VENDOR_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'vendor', 'nicotine-plus'))
sys.path.insert(0, VENDOR_PATH)

try:
    from pynicotine.core import Core
    from pynicotine.config import Config
    from pynicotine.events import log as nic_log
except ImportError as e:
    sys.stderr.write(f"Failed to import Nicotine framework. Did you initialize submodules? {e}\n")
    sys.exit(1)

class SwifotineHelper:
    """
    JSON-RPC out-of-process helper bridging nicotine-plus to standard IO.
    """
    def __init__(self):
        self.session_config = {}
        self.nicotine_core = None
        
        # Setup logging directly to IPC to avoid polluting stdout with arbitrary prints
        logging.basicConfig(level=logging.ERROR, handlers=[logging.NullHandler()])
    
    def emit_event(self, event_name, payload):
        sys.stdout.write(json.dumps({"event": event_name, "payload": payload}) + "\n")
        sys.stdout.flush()

    def respond(self, request_id, result=None, error=None):
        if error is not None:
            res = {"id": request_id, "ok": False, "error": error}
        else:
            res = {"id": request_id, "ok": True, "result": result or {}}
        sys.stdout.write(json.dumps(res) + "\n")
        sys.stdout.flush()

    def handle_request(self, line):
        try:
            req = json.loads(line.strip())
        except json.JSONDecodeError:
            self.emit_event("backend.log", {"level": "error", "message": "Failed to decode JSON request"})
            return

        method = req.get("method")
        params = req.get("params", {})
        req_id = req.get("id", "none")

        if method == "health.ping":
            self.respond(req_id, {"status": "ok"})
        elif method == "session.configure":
            self.session_config.update(params)
            self.respond(req_id, {"configured": True})
        elif method == "session.connect":
            # TODO: Initialize Core and connect
            self.emit_event("connection.state_changed", {
                "state": "connecting", 
                "server_reason": "", 
                "username": self.session_config.get("username")
            })
            self.respond(req_id)
        elif method == "session.disconnect":
            self.emit_event("connection.state_changed", {
                "state": "offline", 
                "server_reason": "disconnected_by_user", 
                "username": self.session_config.get("username")
            })
            self.respond(req_id)
        else:
            self.respond(req_id, error={"code": "MethodNotFound", "message": f"Unknown method: {method}", "details": {}})

    def run(self):
        self.emit_event("backend.log", {"level": "info", "message": "Swifotine Helper initialized and awaiting commands."})
        for line in sys.stdin:
            if not line.strip():
                continue
            self.handle_request(line)

if __name__ == "__main__":
    helper = SwifotineHelper()
    helper.run()
