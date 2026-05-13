# Part 4: Bridging the Gap (Tailscale & The Sandbox)

## 1. The Challenge of "Dual-Homing"

By Part 3, we had a robust k3s cluster on Macbuntu and a fleet of mobile nodes ready to work. However, we faced a new architectural hurdle: **Network Isolation vs. Developer Access.**

We wanted a "Cascaded Router" setup to physically isolate the lab from the rest of the house. This meant:
1.  **ISP Modem** -> **Primary Router** (Home/Family Wi-Fi).
2.  **Primary Router** -> **Secondary Router** (The Lab Sandbox).

The problem? If Macbuntu is plugged into the Lab router, it's invisible to your laptop on the Home Wi-Fi. Switching Wi-Fi networks every time you want to check a log is a friction point that kills productivity.

## 2. The Solution: The Tailscale Subnet Bridge

We used **Tailscale** to build a secure "backdoor" into the sandbox. Instead of making every tiny mobile phone run a VPN client (which drains battery and adds complexity), we turned **Macbuntu** into a **Subnet Router**.

### The Topology
*   **The Hub:** Macbuntu is "Dual-Homed." It’s plugged into the Lab router via Ethernet (`10.0.0.11`) and connected to the Home Wi-Fi (`192.168.4.x`).
*   **The Bridge:** Macbuntu runs Tailscale and "advertises" the `10.0.0.0/24` route to the entire Tailnet.
*   **The Result:** From a phone at a coffee shop or a laptop in the living room, you can ping `10.0.0.1` (the Lab Router) or `10.0.0.202` (a Moto Edge worker) directly.

## 3. Implementation: Hardening the Airlock

A bridge is only useful if it has a gatekeeper. We used Linux `iptables` and `sysctl` to ensure this bridge was a one-way street.

### Kernel Forwarding
We enabled IP forwarding so the Linux kernel knows it's allowed to pass packets between the virtual Tailscale interface and the physical Ethernet card.
```bash
net.ipv4.ip_forward = 1
```

### The "Airlock" Rules (iptables)
We configured three critical rules to make the bridge work:
1.  **Forwarding:** Allow traffic *only* from Tailscale to the Lab Ethernet.
2.  **State Tracking:** Allow replies from the Lab nodes back to the authorized Tailscale requester.
3.  **Masquerading (NAT):** Hide the Tailscale IPs from the Lab nodes. When a phone at `10.0.0.202` receives a request, it thinks it's talking to Macbuntu (`10.0.0.11`), which it knows how to answer.

## 4. Verifying the Sandbox (The "Dead Route")

To ensure our agents couldn't "sniff" the home network, we implemented a **Dead Route** on the secondary router. Any traffic destined for the home subnet (`192.168.4.0/24`) is forcibly redirected to a non-existent gateway (`10.0.0.254`).

**The litmus test:**
*   **Macbuntu -> Google:** SUCCESS (Internet is flowing).
*   **Macbuntu -> Home Router:** REJECTED (Isolation is working).
*   **Laptop (Home) -> Lab Node:** SUCCESS (Tailscale Bridge is working).

## 5. Outcome: A Professional-Grade Remote Lab

This setup transforms a collection of old phones and a spare router into a professional-grade AI development environment. You get the **security** of an air-gapped network with the **convenience** of a cloud-hosted service. 

With the networking foundation finalized, we were able to wake up a "sleeping" Moto Edge 2023, locate it at `10.0.0.202`, and trigger a successful inference request—all while securely bridged through the Macbuntu gateway.
