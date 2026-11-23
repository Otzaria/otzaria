"""Identity and evidence shared by the two explicitly distinct schedulers."""

BINDINGS = {
    "integration": {
        "bindingMode": "integration",
        "bindingClass": "IntegrationTestWidgetsFlutterBinding",
        "framePolicy": "fullyLive",
        "platformDispatcher": "test",
        "probeTarget": "integration_test/perf_resource_probe_test.dart",
    },
    "framework": {
        "bindingMode": "framework",
        "bindingClass": "WidgetsFlutterBinding",
        "framePolicy": "frameworkRequested",
        "platformDispatcher": "native",
        "probeTarget": "tool/perf_probe/framework_pdf_probe.dart",
    },
}


def binding_identity(mode):
    if mode not in BINDINGS:
        raise ValueError(f"Unknown binding mode: {mode}")
    return dict(BINDINGS[mode])


def validate_binding_identity(value, mode):
    expected = binding_identity(mode)
    for key, wanted in expected.items():
        if not isinstance(value, dict) or type(value.get(key)) is not str or value[key] != wanted:
            raise ValueError(f"Missing or unexpected {mode} binding identity: {key}")


def validate_framework_scheduler(notes, launch_count):
    if type(launch_count) is not int or launch_count < 1 or not isinstance(notes, list):
        raise ValueError("Expected framework scheduling evidence for measured launches")
    evidence = [note for note in notes if isinstance(note, dict)
                and note.get("name") == "framework.scheduler_contract"]
    if len(evidence) != launch_count:
        raise ValueError("Expected one framework scheduling check per measured launch")
    seen = set()
    for note in evidence:
        index = note.get("launchIndex")
        if type(index) is not int or not 0 <= index < launch_count or index in seen:
            raise ValueError("Foreign or duplicate framework scheduling launch")
        seen.add(index)
        record = note.get("frameworkScheduler")
        if (not isinstance(record, dict) or record.get("status") != "passed"
                or record.get("source") != "Timer -> SchedulerBinding.scheduleFrame -> postFrameCallback"
                or record.get("deferredFrameDelivered") is not True
                or record.get("nativePlatformDispatcher") is not True
                or record.get("bindingClass") != "WidgetsFlutterBinding"):
            raise ValueError("The native framework did not deliver a deferred frame")
        for key in ("requestedAtUs", "completedAtUs", "frameTimestampUs"):
            if type(record.get(key)) is not int or record[key] < 0:
                raise ValueError(f"Missing framework scheduling timestamp: {key}")
        if record["completedAtUs"] < record["requestedAtUs"]:
            raise ValueError("The frame predates its request")
