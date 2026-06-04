#!/system/bin/sh

# Stop the HBTP daemon first so it releases its open file descriptors.
# chmod alone won't work — the daemon holds the device open and keeps
# feeding events even after permissions are revoked.
stop vendor.hbtp

# Wait a moment for input devices to fully initialize after boot
sleep 15

# Block both hbtp_input and hbtp_vm — the virtual mirror device (hbtp_vm)
# also fires ghost touches independently of hbtp_input.
for event_dir in /sys/class/input/event*; do
    if [ -f "$event_dir/device/name" ]; then
        device_name=$(cat "$event_dir/device/name")
        if [ "$device_name" = "hbtp_input" ] || [ "$device_name" = "hbtp_vm" ]; then
            event_node=$(basename "$event_dir")
            chmod 000 "/dev/input/$event_node"
        fi
    fi
done
