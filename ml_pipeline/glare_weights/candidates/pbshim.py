"""Import this BEFORE tensorflow. Only needed with the system Python (protobuf 5 vs TensorFlow 2.21): disables the strict
protobuf version check. With the project venv (ml_pipeline/.venv, TF 2.15.1, the one Stage 2 used) it does nothing."""
try:
    import google.protobuf.runtime_version as _rv
    _rv.ValidateProtobufRuntimeVersion = lambda *a, **k: None
except Exception:
    pass
