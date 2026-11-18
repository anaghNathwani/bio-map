import tensorflow as tf, numpy as np, json
R="/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/"
it=tf.lite.Interpreter(model_path=R+"BundledBirdModel.tflite"); it.allocate_tensors()
labels=json.load(open(R+"BundledBirdLabels.json"))
print("labels",len(labels),[ (i,l) for i,l in enumerate(labels) if 'Unknown' in l or 'Not a' in l])
for o in it._get_ops_details()[:6]: print(o['index'],o['op_name'],o['inputs'],o['outputs'])
ops=it._get_ops_details(); print("nops",len(ops))
from collections import Counter; print(Counter(o['op_name'] for o in ops))
for o in ops[:8]+ops[-6:]:
    ins=[(i,tuple(it.get_tensor_details()[i]['shape'])) for i in o['inputs'] if i>=0]
    print(o['index'],o['op_name'],ins,o['builtin_options'] if 'builtin_options' in o else '')
print(it.get_input_details()[0]['shape'],it.get_output_details()[0]['shape'])
