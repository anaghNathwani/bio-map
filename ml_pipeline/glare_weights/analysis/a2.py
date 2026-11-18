import tensorflow as tf, numpy as np
R="/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/"
it=tf.lite.Interpreter(model_path=R+"BundledBirdModel.tflite"); it.allocate_tensors()
d=it.get_tensor_details()
print(it.get_tensor(107),it.get_tensor(106))
for i in (54,1,53,111,56,409):
    t=d[i]; print(i,t['name'],t['shape'],t['dtype'],t['quantization'])
w=it.get_tensor(54); print(w.dtype, w.shape)
print(w[:4].reshape(4,-1).round(3))
