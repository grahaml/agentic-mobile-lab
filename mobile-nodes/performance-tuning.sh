#!/system/bin/sh
# ==========================================
# ⚡ Motorola Edge 2023 (aion) Performance Tuner
# ==========================================
# This script locks CPU frequencies and optimizes 
# the kernel for low-latency AI inference.
# ==========================================

echo "🚀 Starting Performance Tuning for aion (MT6855)..."

# 1. CPU Governor Lock (Set to performance)
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    if [ -d "$policy" ]; then
        echo "performance" > "$policy/scaling_governor"
        # Set min freq to 80% of max freq for a high "floor" without 100% heat
        MAX_FREQ=$(cat "$policy/scaling_max_freq")
        MIN_TARGET=$((MAX_FREQ * 80 / 100))
        echo "$MIN_TARGET" > "$policy/scaling_min_freq"
        echo "✅ Policy $(basename $policy) locked at $MIN_TARGET kHz min."
    fi
done

# 2. Virtual Memory Optimizations
echo "10" > /proc/sys/vm/swappiness
echo "100" > /proc/sys/vm/vfs_cache_pressure
echo "✅ Swappiness reduced to 10 (favoring RAM over swap)."

# 3. Low Memory Killer (LMK) Tuning
# Ensure our agent-lab chroot stays resident
if [ -f /sys/module/lowmemorykiller/parameters/minfree ]; then
    # Standard aggressive profile
    echo "18432,23040,27648,32256,55296,80640" > /sys/module/lowmemorykiller/parameters/minfree
    echo "✅ LMK tuned for background process preservation."
fi

# 4. GPU Performance (MediaTek Specific)
if [ -d /proc/gpufreq ]; then
    # Some older MTK kernels use this
    echo "0" > /proc/gpufreq/gpufreq_var_dump 2>/dev/null
fi

echo "✨ Performance Profile Applied Successfully."
