"""tflite_edit.py -- patch constant tensors in a .tflite flatbuffer and write a NEW file (original never touched).

Library:
  m = Model.load(path)                  # parses flatbuffer via the TF object API
  m.tensor_by_name / m.find(substr)     # tensor lookup
  m.get(idx) -> np.ndarray              # constant tensor data (float32 only here)
  m.set(idx, arr)                       # replace data (shape/dtype must match)
  m.save(out)                           # re-serialise
CLI:
  python tflite_edit.py roundtrip IN OUT
  python tflite_edit.py apply IN OUT edits.json     (see apply_edits.py for the recipe format)

Pitfalls (verified in selftest.py):
 * Constant tensors have a `buffer` index; several tensors may share one buffer (checked: set() refuses if shared
   unless force=True).  Buffer 0 is the empty sentinel.
 * The stem/all conv weights are stored as FLOAT32 and a QUANTIZE op (fixed scale/zero-point from the op's output
   tensor) rounds them to int8-grid at run time, clipping outside [min,max] of that grid.  So an edit is automatically
   snapped, but a value beyond the representable range is silently clipped.  Use grid_info() to see scale/range.
 * Do not touch tensors' quantization metadata or the QUANTIZE ops' activation ranges.
 * flatbuffers re-serialisation is not byte-identical to the original layout (offsets/alignment differ); equality is
   checked on outputs (max abs diff 0) and on every tensor's data bytes.
"""
import sys, json, hashlib
import numpy as np
from tensorflow.lite.python import schema_py_generated as S


class Model:
    def __init__(self, obj, path):
        self.m = obj
        self.path = path
        self.sg = obj.subgraphs[0]

    @classmethod
    def load(cls, path):
        buf = bytearray(open(path, "rb").read())
        return cls(S.ModelT.InitFromObj(S.Model.GetRootAsModel(buf, 0)), path)

    def name(self, i):
        n = self.sg.tensors[i].name
        return n.decode() if isinstance(n, bytes) else n

    def find(self, sub):
        return [i for i in range(len(self.sg.tensors)) if sub in self.name(i)]

    def get(self, i):
        t = self.sg.tensors[i]
        b = self.m.buffers[t.buffer].data
        assert t.type == S.TensorType.FLOAT32, "only float32 supported"
        return np.frombuffer(bytes(bytearray(b)), np.float32).reshape(t.shape).copy()

    def shared(self, i):
        b = self.sg.tensors[i].buffer
        return [j for j, t in enumerate(self.sg.tensors) if t.buffer == b and j != i]

    def set(self, i, arr, force=False):
        t = self.sg.tensors[i]
        arr = np.asarray(arr, np.float32)
        assert list(arr.shape) == list(t.shape), (arr.shape, t.shape)
        if self.shared(i) and not force:
            raise ValueError(f"tensor {i} shares its buffer with {self.shared(i)}")
        self.m.buffers[t.buffer].data = np.frombuffer(arr.tobytes(), np.uint8).copy()

    def save(self, out):
        import flatbuffers
        b = flatbuffers.Builder(1 << 20)
        b.Finish(self.m.Pack(b), file_identifier=b"TFL3")
        open(out, "wb").write(bytes(b.Output()))

    def quant_op_for_weight(self, widx):
        """Return (scale, zero_point, qmin, qmax, lo, hi) of the QUANTIZE op that consumes float weight tensor widx."""
        for op in self.sg.operators:
            code = self.m.operatorCodes[op.opcodeIndex]
            bc = max(code.builtinCode, code.deprecatedBuiltinCode)
            if bc == S.BuiltinOperator.QUANTIZE and op.inputs[0] == widx:
                q = self.sg.tensors[op.outputs[0]].quantization
                sc, zp = float(q.scale[0]), int(q.zeroPoint[0])
                dt = self.sg.tensors[op.outputs[0]].type
                qmin, qmax = (0, 255) if dt == S.TensorType.UINT8 else (-128, 127)
                return sc, zp, qmin, qmax, sc * (qmin - zp), sc * (qmax - zp)
        return None


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "roundtrip":
        Model.load(sys.argv[2]).save(sys.argv[3])
        print("wrote", sys.argv[3], sha(sys.argv[3]))
