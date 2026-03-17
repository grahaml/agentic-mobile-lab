Turning that collection of devices into a coordinated, autonomous development team is the ultimate 2026 power move for a Security Architect.

This decentralized, multi-agent architecture with a strong focus on **PKI presentation** and **auditability** is structured as a comprehensive, publishable technical article.

---

# The Agentic Mobile Lab: Resurrecting Old Android Hardware for Secure, Multi-Agent Dev Workflows

*Date: March 15, 2026*

The modern developer's graveyard is littered with "failed" hardware: older tablets locked down with ineffective kid-safe modes, mid-range phones retired due to slow background updates, and last-generation laptops. As local-first AI models mature in 2026, these devices represent an untapped reservoir of compute.

This article outlines a battle-tested blueprint for transforming that "useless" hardware into a sophisticated, decentralized "dev team" of autonomous agents. The setup ensures that your **Samsung Tab S5e** (running **Qwen 2.5 1.5B**) and your **Macbuntu** server (running **Mistral 7B**) operate with distinct identities, boundaries, and collaboration channels, creating a secure, audible, and privacy-first engineering ecosystem.

## I. The Architecture: Roles, Boundaries, and Identity

To treat these devices as separate "employees," we must establish clear boundaries and unique cryptographic identities. We do not use user accounts; we use agent-specific identities based on Git config and Discord API tokens.

### Device Fleet and Assigned Personas

| Device | Hardware Context | Role | Identity (Git User) | Assigned LLM | Primary Focus |
| --- | --- | --- | --- | --- | --- |
| **Tablet** | Samsung Tab S5e (6GB RAM) | **Architect / Sr. Dev** | `Agent (TabS5e)` | `qwen2.5-coder:1.5b` | PKI design, Cert rotation logic, UI layout planning. |
| **Server** | MacBook Pro 2018 (Macbuntu, 16GB) | **Tech Lead / heavy Lifter** | `Agent (K3s-Host)` | `mistral:7b-instruct` | Test execution (k3s), code review, heavy debugging. |
| **Phone A** | Google Pixel 5a (Retired 2023) | **Security Auditor** | `Agent (Auditor-P5a)` | `qwen2.5:0.5b` | Log analysis, static code analysis (SAST), PKI compliance check. |

---

## II. The Toolbox: The 2026 Mobile Agent Stack

The entire stack is local-first, privacy-by-default, and designed to minimize latency on older processors.

| Tool | Category | Role |
| --- | --- | --- |
| **LineageOS 22.2** | Operating System | Replaces bloat-heavy stock ROMs. Provides Android 15 features, RAM optimization, and recent security patches for EOL devices. |
| **Termux** | Terminal Emulator | A full Linux userland. This is the command center, the container, and the service manager for the entire local agent operation. |
| **Ollama** | LLM Engine | Native arm64 Termux port. Runs quantized GGUF models with minimal overhead. Exposes a simple API for agent integration. |
| **Aider** | Agentic Editor | The "eyes and hands" of the local agent. Reads files, understands code structures, runs tests, and commits changes directly. |
| **k3s** | Orchestration | Lightweight Kubernetes for local clusters. Manages sandboxed agent execution pods with strict NetworkPolicy enforcement. |
| **code-server** | Native IDE | Runs VS Code UI in a mobile browser. Provides the professional editing environment needed for validation. |
| **Zellij** | Workspace Manager | Terminal multiplexer. Manages persistent sessions for Ollama and code-server, providing workspace organization on small screens. |
| **discord.py** | Collaboration Layer | Framework used to give agents "a voice." They communicate via a dedicated Discord channel for clear command/control loops. |

---

## III. Phase 1: Mobile Device Installation Blueprint (Unlock & Wipe)

This guide focuses on preparing your core Architect/Sr. Dev machine, the **Samsung Tab S5e**, for its new life.

### Part A: The Clean Slate (Unlocking the Bootloader)

*Warning: This process permanently wipes all user data.*

1. **Activate Dev Mode:** On the tablet, go to **Settings > About Tablet > Software Information** and tap **Build Number** 7 times.
2. **Enable Unlocking:** Go to the newly available **Developer Options** menu. Toggle on **OEM Unlocking** and **USB Debugging**.
3. **Unlock Sequence:** Power off the device. While holding **Volume Up + Volume Down**, connect the tablet to your PC. A warning screen appears. **Long-press Volume Up** to enter Device Unlock Mode. Confirm your choice to wipe and unlock. The device reboots to a clean setup screen.

### Part B: Installing LineageOS 22.2 (The Modern Foundation)

You will need `adb` and `fastboot` on your PC.

1. **Download Files:** From the official [LineageOS site](https://download.lineageos.org/devices/gts4lvwifi), download `recovery.img` and the OS installation `zip` package.
2. **Boot to Download Mode:** Power off. Hold **Volume Up + Volume Down** and connect USB.
3. **Flash Recovery:** On your PC terminal, execute:
```bash
fastboot flash recovery recovery.img
fastboot reboot recovery

```


*If on Windows, you may need to use the Odin tool to flash `recovery.tar` to the 'AP' slot.*
4. **Wipe and Sideload:** Within the purple Lineage Recovery interface, select **Factory Reset > Format data**. Then select **Apply Update > Apply from ADB**. On your PC, run:
```bash
adb sideload lineage-22.2-xxxxxxxx-nightly-gts4lvwifi-signed.zip

```


5. **Reboot:** You now have a clean, bloat-free Android 15 foundation.

---

## IV. Phase 2: Building the Agent Persona (Identity & Agents)

Once LineageOS boots, the tablet setup begins. We integrate identity with automation, ensuring every agent action is auditable.

### Setup Step 1: Initialize Termux and The User Repo

1. **Install F-Droid:** The Google Play Store version of Termux is obsolete. Download and install the **F-Droid** app, then search for and install **Termux**.
2. **Add Community Repository:** The TUR repo is required for `code-server` and other advanced tools. Run in Termux:
```bash
pkg update && pkg upgrade -y
pkg install tur-repo -y

```



### Setup Step 2: Establish Cryptographic Identity

1. **Git Configuration:** Set a global unique identity.
```bash
git config --global user.name "Agent (TabS5e)"
git config --global user.email "your-pki-lab@example.com"

```


2. **Generate SSH Key:** A device-specific key is generated for GitHub/GitLab access.
```bash
pkg install openssh -y
ssh-keygen -t ed25519 -C "agent-tabs5e" -f ~/.ssh/id_ed25519 -N ""

```


3. **Authentication CLI:** Install the GitHub CLI (`gh`) or GitLab CLI (`glab`) to allow agents to programmatically create PRs.
```bash
pkg install gh -y
gh auth login

```



### Setup Step 3: Install the "Agentic Stack"

Install the local AI engine, workspace manager, and coding tools:

```bash
pkg install ollama code-server python git pip zellij build-essential binutils -y
pip install aider-chat discord.py

```

### Setup Step 4: Bootstrap the Local LLM

Start Ollama and pull the optimized model for the S5e.

```bash
ollama serve &
ollama pull qwen2.5-coder:1.5b

```

### Setup Step 5: The Zellij Workspace Orchestrator

We package the services into a Zellij layout file for a single-command launch. Save as `~/.config/zellij/layouts/sr-dev.kdl`:

```kdl
layout {
    pane split_direction="vertical" {
        pane name="Ollama Engine" command="ollama" {
            args "serve"
        }
        pane name="Aider (The Architect)" command="aider"
    }
    pane name="code-server IDE" command="code-server" {
        args "--auth" "none" "--port" "8080"
    }
    pane size=1 borderless=true {
        plugin location="zellij:status-bar"
    }
}

```

*To launch the entire lab, run: `zellij --layout sr-dev*`

---

## V. Diagramming the Agent Loops

The value of this architecture is in the autonomous feedback loops, particularly for security tasks like PKI rotation where validation is crucial.

### Diagram 1: The Local Coding Loop (S5e Tablet)

This loop illustrates how you use Aider as an "on-device architect" to rapidly prototype the **PKI rotation script** for your presentation.

> `[User Input: Keyboard/Discord]`
> `      |`
> `      v`
> ` [Zellij Pane: Aider CLI]`
> `      |`
> `      v (API Call to localhost:11434)`
> ` [Termux Process: Ollama (Qwen 2.5 1.5B)]` --`(Model Analysis of code context)`
> `      |`
> `      v (Response)`
> ` [Zellij Pane: Aider CLI]` --`(Generates Code & Commit Message)`
> `      |`
> `      v (Shell Command)`
> `[Git / Local Filesystem]` --`(Modifies pki_rotation.py, Commits with "Agent (TabS5e)" identity)`

### Diagram 2: The Collaboration Loop (Discord/Multi-Agent)

This diagram shows how you facilitate a distinct boundaries workflow. The Tablet agent (Sr. Dev) proposes a change, and the MacBook agent (Tech Lead) automatically reviews it.

> `[User Prompt in #dev-lab: "@Tablet can you write pki_rotation.py and @MacBook please review it?"]`
> `      |`
> `      v`
> `[Discord Channel]`
> `      |`
> `      +---> [@Tablet bot (Qwen)] ---> [Generates pki_rotation.py]` ---> `[Pops into code-server/commits]` ---> `[Posts code link in Discord]`
> `      |`
> `      +---> [@MacBook bot (Mistral)] ---> [Waits for completion]` ---> `[Checks out code]` ---> `[Runs pki_rotation.py via k3s]` ---> `[Post review in Discord]`

---

## VI. Scaling Up: The "Old Phone Graveyard"

Integrating older phones into this setup requires a systematic assessment of their hardware limitations.

### 1. Assessing Compatibility (March 2026 Standards)

The minimum hardware requirement to run Ollama reliably is an `arm64-v8a` processor and Android 10+. However, RAM is the primary bottleneck.

| Tablet/Phone RAM | Ollama Viability | Tip |
| --- | --- | --- |
| **< 3GB RAM** | **Unsupported** | Highly likely to OOM crash even with 0.5B models; best used as a standard monitoring dashboard. |
| **3GB - 4GB RAM** | **Viable (0.5B - 1B)** | Perfect for a single, focused specialist agent (e.g., SAST auditing, log summarization). Use **Qwen 2.5 0.5B** or **Llama 3.2 1B**. |
| **6GB+ RAM** | **Strong (1.5B - 3B)** | Can handle the Architect/Sr. Dev role with larger models. Use **Qwen 2.5 Coder 1.5B** or **DeepSeek-R1 1.5B**. |

### 2. Testing Your Fleet

The standard method for fleet assessment involves running a standardized inference speed benchmark to gauge compatibility.

**Save as `ollama-test.sh` in Termux on any phone:**

```bash
#!/bin/bash
# 2026 Mobile Lab Inference Benchmark

echo "📊 Testing your device for Ollama capability..."
read -p "Enter Model to test (e.g., qwen2.5:0.5b): " MODEL_NAME

echo "🚀 Starting Ollama background service..."
ollama serve > /dev/null 2>&1 &
sleep 5 # Allow time for server initialization

echo "Pulling model (may take time)..."
ollama pull $MODEL_NAME > /dev/null 2>&1

echo "--- INFerence BENCHMARK START ---"
# Measures time for a simple prompt/response
/usr/bin/time -v ollama run $MODEL_NAME "Summarize this sentence: PKI rotation is critical for cloud security architecture." 2>&1 | grep "Tokens per second"

echo "--- INFerence BENCHMARK END ---"
killall ollama
echo "✅ Test complete."

```

*Note: Any result lower than 4 TOK/sec will feel too slow for chat, but may be usable for non-urgent automation tasks.*

---

## Conclusion: The Ultimate Presentation Demo

By transforming that "failed kid-safe" Samsung Tab S5e into a **secure, on-device AI agent**, you haven’t just resurrected hardware; you’ve unlocked a decentralized architecture. For your upcoming **PKI presentation**, demonstrating a "secure collaboration" between your local phone and tablet agents via Discord—where each agent has a unique Git identity and distinct, private context—is a killer practical example of advanced cloud security and agentic workflows in 2026.

This is the ultimate evolution of "Vibe Coding"—where the architect designs, and the automated local lab executes, validates, and reports back, all in a private, closed-loop ecosystem.
