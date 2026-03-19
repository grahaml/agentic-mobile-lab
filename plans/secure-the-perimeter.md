#01 - Secure Network Perimeter (Cascaded Router)

Objective: Establish a standalone, physically cascaded secondary router to host the AI homelab. This creates two distinct Wi-Fi environments (Home vs. Lab) and uses hardware-level NAT and firewall rules to isolate experimental LLM workloads from personal devices. Tailscale and remote management are deferred to Phase 2.
1. Physical Topology

    The Untouched Core: The ISP Modem remains connected to the primary Eero router. The Eero continues broadcasting the home Wi-Fi SSID (e.g., HomeNetwork).

    The Cascade: Connect an Ethernet cable from a LAN port on the primary Eero to the WAN (Internet) port of the Extra Router.

    The Hardwired Node: Connect the Macbuntu K3s host directly to a LAN port on the Extra Router.

2. Extra Router Configuration (The Sandbox)

Log into the Extra Router's admin panel (typically via a laptop plugged into its LAN port or connected to its default setup Wi-Fi).
A. Network & DHCP Settings

    Router IP Address: Set to 10.0.0.1 (This changes it from the standard 192.168.x.x to prevent subnet collisions with the Eero).

    Subnet Mask: 255.255.255.0

    DHCP Server: Enabled.

    DHCP Range: Set from 10.0.0.100 to 10.0.0.200. (This reserves IPs 2 through 99 for your static cluster nodes).

B. Wireless Settings (The Second SSID)

    SSID Name: Create a distinct name (e.g., Homelab-Net-5G).

    Security: WPA2/WPA3 Personal.

    Band: Force 5GHz only if possible, to ensure the mobile Operators (S10e, rooted phone) have the lowest latency connection to the Macbuntu host.

C. Static IP Assignments (DHCP Reservations)

Bind the MAC addresses of your lab hardware to specific IPs so the cluster routing remains stable.

    Macbuntu (Wired): 10.0.0.11

    Operator Phone 1 (Wi-Fi): 10.0.0.20

    Operator Phone 2 (Wi-Fi): 10.0.0.21

3. Hardware Firewall Rules (Crucial)

By default, the Extra Router allows devices on 10.0.0.x to talk to the internet, which means they route through your Eero network (192.168.4.x). You must explicitly block this to secure the sandbox.

Navigate to the Firewall / Access Control / Routing section of the Extra Router and add these explicit rules:

    Rule 1: Block Lateral Movement (Protect the Home)

        Action: DROP / DENY

        Source: 10.0.0.0/24 (Entire Lab Subnet)

        Destination: 192.168.4.0/24 (Entire Home Subnet)

        Note: This ensures a rogue agent cannot scan your smart TVs or family laptops.

    Rule 2: Air-Gap the Operators (Protect the Data)

        Action: DROP / DENY

        Source IPs: 10.0.0.20, 10.0.0.21 (Mobile Operator Nodes)

        Destination: WAN / 0.0.0.0/0 (The Internet)

        Note: This allows the phones to talk to Macbuntu over the local Wi-Fi switch, but strictly drops their ability to reach external APIs.

4. Phase 1 Workflow: How to Use the Lab

Because Tailscale is out of scope and the Eero NAT blocks inbound traffic:

    When you want to browse the web or watch Netflix, your laptop stays on the HomeNetwork SSID.

    When you want to SSH into Macbuntu or write agent code, you manually switch your laptop's Wi-Fi to the Homelab-Net-5G SSID.

    You are now inside the sandbox and can SSH directly into 10.0.0.11.
