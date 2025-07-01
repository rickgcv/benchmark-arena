#!/usr/bin/env python3
"""
GPU Monitoring API Server for LLM Benchmark Demo

This script provides a simple API to get GPU statistics that can be consumed
by the web demo. It uses nvidia-ml-py3 to get real GPU metrics.

Install dependencies:
    pip install flask nvidia-ml-py3 flask-cors

Run:
    python gpu_monitor.py

The API will be available at:
    http://localhost:8080/gpu/0  # For GPU 0 (baseline model)
    http://localhost:8080/gpu/1  # For GPU 1 (quantized model)
"""

from flask import Flask, jsonify
from flask_cors import CORS
import time
import threading
try:
    import pynvml
    NVML_AVAILABLE = True
except ImportError:
    NVML_AVAILABLE = False
    print("Warning: nvidia-ml-py3 not available. Using simulated GPU data.")

app = Flask(__name__)
CORS(app)

# Global storage for GPU stats
gpu_stats = {}

def initialize_nvml():
    """Initialize NVIDIA Management Library"""
    if NVML_AVAILABLE:
        try:
            pynvml.nvmlInit()
            return True
        except Exception as e:
            print(f"Failed to initialize NVML: {e}")
            return False
    return False

def get_real_gpu_stats(gpu_id):
    """Get real GPU statistics using NVML"""
    try:
        handle = pynvml.nvmlDeviceGetHandleByIndex(gpu_id)
        
        # Get GPU utilization
        util = pynvml.nvmlDeviceGetUtilizationRates(handle)
        gpu_util = util.gpu
        
        # Get memory info
        mem_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
        mem_used_gb = mem_info.used / (1024**3)
        mem_total_gb = mem_info.total / (1024**3)
        mem_util = (mem_info.used / mem_info.total) * 100
        
        # Get power usage
        try:
            power_watts = pynvml.nvmlDeviceGetPowerUsage(handle) / 1000  # Convert mW to W
        except:
            power_watts = 0
            
        # Get temperature
        try:
            temp_c = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
        except:
            temp_c = 0
            
        return {
            'gpu_id': gpu_id,
            'utilization': gpu_util,
            'memory_used_gb': round(mem_used_gb, 2),
            'memory_total_gb': round(mem_total_gb, 2),
            'memory_utilization': round(mem_util, 1),
            'power_watts': round(power_watts, 1),
            'temperature_c': temp_c,
            'timestamp': time.time()
        }
    except Exception as e:
        print(f"Error getting GPU {gpu_id} stats: {e}")
        return None

def get_simulated_gpu_stats(gpu_id):
    """Generate simulated GPU statistics for demo purposes"""
    import random
    
    # Different base characteristics for each GPU
    if gpu_id == 0:  # Baseline model (higher usage)
        base_util = 75
        base_memory = 12.8
        base_power = 300
    else:  # Quantized model (lower usage)
        base_util = 45
        base_memory = 6.2
        base_power = 180
    
    # Add realistic variation
    variation = (random.random() - 0.5) * 0.2  # ±10%
    
    return {
        'gpu_id': gpu_id,
        'utilization': max(0, min(100, base_util + (base_util * variation))),
        'memory_used_gb': round(max(0, base_memory + (base_memory * variation * 0.1)), 2),
        'memory_total_gb': 16.0 if gpu_id == 0 else 12.0,
        'memory_utilization': round(max(0, base_memory/16.0*100 + (variation * 10)), 1),
        'power_watts': round(max(0, base_power + (base_power * variation * 0.15)), 1),
        'temperature_c': round(70 + variation * 10),
        'timestamp': time.time()
    }

def update_gpu_stats():
    """Background thread to update GPU statistics"""
    nvml_initialized = initialize_nvml() if NVML_AVAILABLE else False
    
    while True:
        for gpu_id in [0, 1]:
            if nvml_initialized:
                stats = get_real_gpu_stats(gpu_id)
            else:
                stats = get_simulated_gpu_stats(gpu_id)
                
            if stats:
                gpu_stats[gpu_id] = stats
        
        time.sleep(2)  # Update every 2 seconds

@app.route('/gpu/<int:gpu_id>')
def get_gpu_stats(gpu_id):
    """API endpoint to get GPU statistics"""
    if gpu_id in gpu_stats:
        return jsonify(gpu_stats[gpu_id])
    else:
        return jsonify({'error': f'GPU {gpu_id} not found'}), 404

@app.route('/gpu/all')
def get_all_gpu_stats():
    """API endpoint to get all GPU statistics"""
    return jsonify(gpu_stats)

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'nvml_available': NVML_AVAILABLE,
        'gpus_monitored': list(gpu_stats.keys()),
        'timestamp': time.time()
    })

if __name__ == '__main__':
    # Start background thread for GPU monitoring
    monitor_thread = threading.Thread(target=update_gpu_stats, daemon=True)
    monitor_thread.start()
    
    print("Starting GPU Monitor API Server...")
    print("Available endpoints:")
    print("  http://localhost:8080/gpu/0     - GPU 0 stats (baseline model)")
    print("  http://localhost:8080/gpu/1     - GPU 1 stats (quantized model)")
    print("  http://localhost:8080/gpu/all   - All GPU stats")
    print("  http://localhost:8080/health    - Health check")
    
    app.run(host='0.0.0.0', port=8080, debug=False) 