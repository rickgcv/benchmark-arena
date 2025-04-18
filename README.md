

Start the web server for the benchmark application with:
```
python -m http.server
```

Start up two vllm servers in separate terminals/processes:
```
export CUDA_VISIBLE_DEVICES=0
vllm serve meta-llama/Llama-3.1-8B-Instruct --port 9000

export CUDA_VISIBLE_DEVICES=1
vllm serve RedHatAI/Meta-Llama-3.1-8B-Instruct-quantized.w4a16 --port 9001
```

