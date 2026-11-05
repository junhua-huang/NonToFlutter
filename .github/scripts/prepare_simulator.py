#!/usr/bin/env python3
"""Wait for the selected iOS 27 simulator before starting input-dependent tests."""
import json
import os
import subprocess
import uuid


def main():
    device_id = os.environ["SIMULATOR_UDID"]
    uuid.UUID(device_id)
    devices = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
    matches = [(runtime, device) for runtime, group in devices["devices"].items()
               if "iOS-27" in runtime for device in group
               if device["udid"] == device_id and device["isAvailable"]]
    if len(matches) != 1:
        raise ValueError("Expected one available iOS 27 simulator.")
    subprocess.run(["defaults", "write", "com.apple.iphonesimulator",
                    "ConnectHardwareKeyboard", "-bool", "NO"], check=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", device_id, "-b"],
                   check=True, timeout=180)
    print("Simulator boot completed:", matches[0][1]["name"], flush=True)


if __name__ == "__main__":
    main()
